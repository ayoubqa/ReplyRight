import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

@main
struct ReplyRightApp: App {
    @State private var app: AppModel

    init() {
        Self.applyLaunchArguments()
        Self.applyAppearance()
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }

    /// Lets UI tests start from a known state: `-rr-reset` wipes local data,
    /// `-rr-skip-onboarding` marks first-run setup as done.
    private static func applyLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        let store = SharedStore.shared
        if arguments.contains("-rr-reset") {
            store.eraseEverything()
        }
        if arguments.contains("-rr-skip-onboarding") {
            var settings = store.loadSettings()
            settings.hasOnboarded = true
            settings.confirmedAdult = true
            store.saveSettings(settings)
        }
    }

    /// Bars sit on the same ground as the screens, with titles in the display face.
    private static func applyAppearance() {
        let ground = UIColor.dynamic(Palette.background)
        let text = UIColor.dynamic(Palette.textPrimary)
        let quiet = UIColor.dynamic(Palette.textTertiary)
        let voice = UIColor.dynamic(Palette.accent)

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = ground
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: text, .font: RRFonts.displayUIFont(size: 18)]
        navigation.largeTitleTextAttributes = [.foregroundColor: text, .font: RRFonts.displayUIFont(size: 32)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = ground
        tabs.shadowColor = UIColor.dynamic(Palette.line)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = quiet
            item.normal.titleTextAttributes = [.foregroundColor: quiet]
            item.selected.iconColor = voice
            item.selected.titleTextAttributes = [.foregroundColor: voice]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}

/// Decides between first-run onboarding and the main interface, and hosts
/// everything that can appear over any screen: settings, keyboard setup, the
/// paywall, the connection screen and toasts.
///
/// SwiftUI presents one sheet at a time from a view. Settings opens the paywall
/// from inside itself, so while Settings is up the paywall is attached there
/// instead of here.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app

        ZStack {
            if app.settings.hasOnboarded && app.settings.confirmedAdult {
                MainTabs()
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.rrGentle, value: app.settings.hasOnboarded)
        .tint(Color.rrAccent)
        .preferredColorScheme(app.colorScheme)
        .rrToast($app.toast)
        .sheet(item: app.showsSettings ? Binding<PaywallReason?>.constant(nil) : $app.paywall) { reason in
            PaywallView(reason: reason)
                .environment(app)
                .preferredColorScheme(app.colorScheme)
        }
        .sheet(isPresented: $app.showsSettings) {
            SettingsSheet()
                .environment(app)
                .tint(Color.rrAccent)
                .preferredColorScheme(app.colorScheme)
                .rrToast($app.toast)
                .sheet(item: $app.paywall) { reason in
                    PaywallView(reason: reason)
                        .environment(app)
                        .preferredColorScheme(app.colorScheme)
                }
        }
        .sheet(isPresented: $app.showsKeyboardSetup) {
            KeyboardSetupJourney()
                .environment(app)
                .tint(Color.rrAccent)
                .preferredColorScheme(app.colorScheme)
        }
        .sheet(isPresented: $app.showsConnection) {
            NavigationStack {
                ConnectionView(isSheet: true)
            }
            .environment(app)
            .tint(Color.rrAccent)
            .preferredColorScheme(app.colorScheme)
        }
        .task {
            await app.purchases.loadProducts()
            await app.refresh(force: true)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await app.refresh() }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        // Four tabs: Reply, Coach, Keyboard and People. Settings opens from the
        // profile button at the top of each tab.
        TabView(selection: $app.selectedTab) {
            HomeTab()
                .tabItem { Label("Reply", systemImage: "quote.opening") }
                .tag(AppModel.Tab.home)

            CoachTab()
                .tabItem { Label("Coach", systemImage: "graduationcap") }
                .tag(AppModel.Tab.coach)

            KeyboardTab()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(AppModel.Tab.keyboard)
                .badge(app.keyboardStatus == .notSetUp || app.keyboardStatus.isReady ? 0 : 1)

            PeopleTab()
                .tabItem { Label("People", systemImage: "person.2") }
                .tag(AppModel.Tab.people)
        }
    }
}
