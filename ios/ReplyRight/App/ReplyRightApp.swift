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
/// everything that can appear over any screen: the paywall, the connection
/// screen and toasts.
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
        .sheet(item: $app.paywall) { reason in
            PaywallView(reason: reason)
                .environment(app)
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

        TabView(selection: $app.selectedTab) {
            HomeTab()
                .tabItem { Label("Reply", systemImage: "quote.opening") }
                .tag(AppModel.Tab.home)

            CoachTab()
                .tabItem { Label("Coach", systemImage: "graduationcap") }
                .tag(AppModel.Tab.coach)

            LibraryTab()
                .tabItem { Label("Notebook", systemImage: "book.closed") }
                .tag(AppModel.Tab.library)

            YouTab()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(AppModel.Tab.you)
        }
    }
}
