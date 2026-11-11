import Foundation
import Observation
import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// Where a flow in the Home tab can go.
enum HomeRoute: Hashable {
    /// Add or review the conversation before it is read.
    case input
    /// What ReplyRight understood, and choosing what the reply should do.
    case understanding
    /// The three suggestions.
    case replies
    /// Rework a draft the user already wrote.
    case polish
    case starter(StarterKind)
    case session(UUID)
}

enum StarterKind: Hashable {
    /// Start a conversation, or restart a quiet one.
    case opener
    /// Suggest meeting up.
    case askOut
}

/// Why the paywall is being shown, so it can say something relevant.
enum PaywallReason: Identifiable, Equatable {
    case general
    case limit(String)
    case intent(Intent)
    case coach
    case voiceSamples

    var id: String {
        switch self {
        case .general: return "general"
        case .limit: return "limit"
        case .intent(let intent): return "intent-\(intent.rawValue)"
        case .coach: return "coach"
        case .voiceSamples: return "voice"
        }
    }

    var lead: String {
        switch self {
        case .general: return "Go further with "
        case .limit: return "That's today's free replies. Keep going with "
        case .intent: return "This one's part of "
        case .coach: return "More time with your coach, with "
        case .voiceSamples: return "Sound even more like you with "
        }
    }

    var detail: String {
        switch self {
        case .general:
            return "Everything ReplyRight can do, whenever you need it."
        case .limit(let message):
            return message
        case .intent(let intent):
            return "\u{201C}\(intent.title)\u{201D} unlocks with Pro, along with every other way to reply."
        case .coach:
            return "Free includes a few coaching questions a day. Pro gives you room for a real conversation."
        case .voiceSamples:
            return "Pro learns from messages you've actually sent, so suggestions match your rhythm, not just your settings."
        }
    }
}

/// Context handed to the coach from elsewhere in the app.
struct CoachSeed: Equatable {
    var question: String?
    var conversation: String
    var draft: String
}

/// The app's shared state: what the user has set up, what the server last
/// reported, and where the interface currently is.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case home
        case coach
        case library
        case you
    }

    let store: SharedStore
    let api: APIClient
    let purchases: StoreService

    // Things the user owns. Each change is written straight to the device.
    var settings: AppSettings {
        didSet {
            store.saveSettings(settings)
            Haptics.isEnabled = settings.hapticsEnabled
        }
    }
    var voice: VoiceProfile {
        didSet { store.saveVoice(voice) }
    }
    var people: [CrushProfile] {
        didSet { store.savePeople(people) }
    }
    var savedReplies: [SavedReply] {
        didSet { store.saveSavedReplies(savedReplies) }
    }
    var sessions: [SavedSession] {
        didSet { store.saveSessions(sessions) }
    }
    var styles: [FavouriteStyle] {
        didSet { store.saveStyles(styles) }
    }

    // What the server last told us.
    var usage: Usage?
    var plans: PlanCatalog
    var mode: GenerationMode?

    // Handed over from the share sheet or kept for the keyboard.
    var inbox: SharedInboxItem?
    var keyboardContext: KeyboardContext?

    // Navigation and transient UI.
    var selectedTab: Tab = .home
    var homePath: [HomeRoute] = []
    var paywall: PaywallReason?
    var toast: String?
    var coachSeed: CoachSeed?

    @ObservationIgnored private var lastStatusRefresh = Date.distantPast

    init(store: SharedStore = .shared) {
        self.store = store
        self.api = APIClient.standard(component: "app", store: store)
        self.purchases = StoreService(store: store)

        let loadedSettings = store.loadSettings()
        self.settings = loadedSettings
        self.voice = store.loadVoice()
        self.people = store.loadPeople()
        self.savedReplies = store.loadSavedReplies()
        self.sessions = store.loadSessions()
        self.styles = store.loadStyles()

        let service = store.loadService()
        self.usage = service.usage
        self.plans = service.plans
        self.mode = service.mode
        self.inbox = store.loadInbox()
        self.keyboardContext = store.loadKeyboardContext()

        Haptics.isEnabled = loadedSettings.hapticsEnabled
    }

    // MARK: Plan

    /// Pro as StoreKit sees it on this device. Used to decide what to show.
    /// The backend verifies the signed transaction itself before granting anything.
    var isPro: Bool { purchases.isPro }
    var tier: Tier { isPro ? .pro : .free }
    var plan: PlanInfo { plans.plan(for: tier) }

    func isLocked(_ intent: Intent) -> Bool {
        !plan.includes(intent)
    }

    /// Replies left today, when the server has told us.
    var remainingGenerations: Int? {
        guard let usage else { return nil }
        // Before the server has seen a new subscription it may still report the free allowance.
        if isPro && usage.tier == .free { return nil }
        return usage.generations.remaining
    }

    var colorScheme: ColorScheme? {
        switch settings.appearance {
        case .evening: return .dark
        case .daylight: return .light
        case .system: return nil
        }
    }

    var apiBaseURL: URL {
        AppConfig.apiBaseURL(override: settings.apiBaseURLOverride)
    }

    // MARK: Refreshing

    /// Brings subscription and service state up to date. Cheap enough to call whenever the app becomes active.
    func refresh(force: Bool = false) async {
        reloadSharedState()
        await purchases.refreshEntitlements()

        guard force || Date().timeIntervalSince(lastStatusRefresh) > 60 else { return }
        lastStatusRefresh = Date()
        do {
            let status = try await api.status()
            plans = status.plans
            usage = status.usage
            mode = status.mode
            store.saveService(ServiceSnapshot(usage: status.usage, plans: status.plans, mode: status.mode))
        } catch {
            // Status is a nicety. The app keeps working from the last known values.
        }
    }

    /// Picks up anything the share sheet or keyboard left in the shared container.
    func reloadSharedState() {
        inbox = store.loadInbox()
        keyboardContext = store.loadKeyboardContext()
    }

    func record(_ usage: Usage, mode: GenerationMode) {
        self.usage = usage
        self.mode = mode
        store.record(usage: usage, mode: mode)
    }

    // MARK: Errors and upgrades

    /// Turns an API error into a message for the screen, opening the paywall when that is the way forward.
    func present(_ error: APIError) -> String {
        if let usage = error.usage {
            self.usage = usage
        }
        switch error {
        case .limitReached(let message, _):
            if isPro {
                return "Your subscription is active on this iPhone, but the server hasn't confirmed it yet. Give it a minute and try again."
            }
            paywall = .limit(message)
            return message
        case .upgradeRequired(let message, _):
            if isPro {
                return "Your subscription is active on this iPhone, but the server hasn't confirmed it yet. Give it a minute and try again."
            }
            paywall = .general
            return message
        default:
            return error.userMessage
        }
    }

    /// Returns true when the feature is available. Otherwise shows the paywall and returns false.
    func requirePro(_ reason: PaywallReason) -> Bool {
        if isPro { return true }
        Haptics.warning()
        paywall = reason
        return false
    }

    // MARK: Replies

    /// Copies a reply to the clipboard. If the user reworked it and has opted in, keeps it as a voice example.
    func copy(_ text: String, original: String? = nil) {
        let clean = text.trimmed
        guard !clean.isEmpty else { return }
        UIPasteboard.general.string = clean
        Haptics.success()

        if settings.learnFromEdits, let original, let sample = VoiceLearning.candidate(original: original, edited: clean) {
            voice.addSample(sample, source: .learned)
            toast = "Copied. Added to My Voice."
        } else {
            toast = Microcopy.pick(Microcopy.copied, seed: clean.count)
        }
    }

    func isSaved(_ text: String) -> Bool {
        savedReplies.contains { $0.text == text }
    }

    func toggleSaved(text: String, style: String, intent: Intent?) {
        let clean = text.trimmed
        guard !clean.isEmpty else { return }
        if let index = savedReplies.firstIndex(where: { $0.text == clean }) {
            savedReplies.remove(at: index)
            toast = "Removed from saved."
        } else {
            savedReplies.insert(SavedReply(text: clean, style: style, intent: intent), at: 0)
            Haptics.success()
            toast = "Saved. It's in your keyboard too."
        }
    }

    func save(_ session: SavedSession) {
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
        Haptics.success()
        toast = "Session saved."
    }

    // MARK: People

    func person(_ id: UUID?) -> CrushProfile? {
        guard let id else { return nil }
        return people.first { $0.id == id }
    }

    // MARK: Keyboard handoff

    /// Makes conversation text available to the ReplyRight keyboard. Only ever called from an explicit tap.
    func handToKeyboard(_ text: String, crush: CrushProfile?) {
        let context = KeyboardContext(text: text, source: .app, crush: crush?.payload)
        guard !context.text.isEmpty else { return }
        store.saveKeyboardContext(context)
        keyboardContext = context
        Haptics.success()
        toast = "Ready in your ReplyRight keyboard."
    }

    func clearKeyboardContext() {
        store.clearKeyboardContext()
        keyboardContext = nil
    }

    func dismissInbox() {
        store.clearInbox()
        inbox = nil
    }

    // MARK: Coach

    func askCoach(question: String? = nil, conversation: String = "", draft: String = "") {
        coachSeed = CoachSeed(question: question, conversation: conversation, draft: draft)
        selectedTab = .coach
    }

    // MARK: Erasing

    func erase(_ category: SharedStore.Category) {
        switch category {
        case .sharedContext:
            store.erase(.sharedContext)
            inbox = nil
            keyboardContext = nil
        case .savedReplies:
            savedReplies = []
        case .sessions:
            sessions = []
        case .people:
            people = []
            settings.lastCrushID = nil
        case .voice:
            voice = .standard
        case .styles:
            styles = []
        }
        toast = "Deleted."
    }

    /// Deletes everything the user created and returns the app to its first-run state.
    func eraseEverything() {
        store.eraseEverything()
        savedReplies = []
        sessions = []
        people = []
        styles = []
        voice = .standard
        inbox = nil
        keyboardContext = nil
        homePath = []
        coachSeed = nil
        selectedTab = .home
        settings = AppSettings()
    }
}
