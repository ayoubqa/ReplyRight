import ReplyRightCore
import ReplyRightUI
import SwiftUI

@main
struct ReplyRightApp: App {
    @State private var app: AppModel

    init() {
        Self.applyLaunchArguments()
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
}

/// Decides between first-run onboarding and the main interface, and hosts
/// everything that can appear over any screen: the paywall and toasts.
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
                .tabItem { Label("Home", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(AppModel.Tab.home)

            CoachTab()
                .tabItem { Label("Coach", systemImage: "lightbulb") }
                .tag(AppModel.Tab.coach)

            LibraryTab()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(AppModel.Tab.library)

            YouTab()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
                .tag(AppModel.Tab.you)
        }
    }
}
