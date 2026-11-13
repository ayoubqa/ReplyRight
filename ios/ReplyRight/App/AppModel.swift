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
    var mode: CoachMode = .ask
    var question: String?
    var conversation: String
    var draft: String
    var crushID: UUID?
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
    /// The conversation currently being worked on. One at a time, shared so any tab can start a flow.
    let compose = ComposeModel()

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

    // Whether the server can be reached and what kind of answers it gives.
    var connection: ConnectionState = .unknown
    /// "development", "staging" or "production", as the server describes itself.
    var serverEnvironment: String?
    var lastChecked: Date?
    var probe: ProbeResult?
    var probeError: APIError?
    var isProbing = false
    /// Set to show the connection screen from anywhere.
    var showsConnection = false

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

    /// The server this build is talking to right now, and why that one.
    var backend: BackendTarget {
        AppConfig.backend(settings: settings)
    }

    var apiBaseURL: URL { backend.url }

    // MARK: Refreshing

    /// Brings subscription and service state up to date. Cheap enough to call whenever the app becomes active.
    func refresh(force: Bool = false) async {
        reloadSharedState()
        await purchases.refreshEntitlements()

        // A broken connection is rechecked every time; a healthy one once a minute.
        let interval: TimeInterval = connection.isProblem || connection == .unknown ? 5 : 60
        guard force || Date().timeIntervalSince(lastStatusRefresh) > interval else { return }
        await checkConnection()
    }

    /// Asks the server how it is. The result drives the connection indicator
    /// everywhere in the app, so a failure here is shown, never swallowed.
    func checkConnection() async {
        lastStatusRefresh = Date()
        // Only show "checking" when there is nothing better to show, so a healthy indicator does not flicker.
        if !connection.canAnswer || connection == .unknown {
            connection = .checking
        }
        do {
            let status = try await api.status()
            plans = status.plans
            usage = status.usage
            mode = status.mode
            serverEnvironment = status.environment
            connection = ConnectionState(status: status)
            store.saveService(ServiceSnapshot(usage: status.usage, plans: status.plans, mode: status.mode))
        } catch let error as APIError {
            if error != .cancelled {
                connection = .unreachable(error)
            }
        } catch {
            connection = .unreachable(.serverUnreachable(.other))
        }
        lastChecked = Date()
    }

    /// Asks the server to make one small, fixed AI call, to prove the key and
    /// model really work. Nothing from the user is sent.
    func runProbe() async {
        guard !isProbing else { return }
        isProbing = true
        probe = nil
        probeError = nil
        do {
            probe = try await api.probe()
        } catch let error as APIError {
            probeError = error
        } catch {
            probeError = .unexpectedResponse
        }
        isProbing = false
        await checkConnection()
    }

    /// Points the app at another server. Development builds only; a release build ignores both values.
    func setBackend(environment: BackendEnvironment?, customURL: String?) {
        var updated = settings
        updated.apiEnvironment = environment?.rawValue
        let clean = customURL?.trimmed ?? ""
        updated.apiBaseURLOverride = clean.isEmpty ? nil : clean
        settings = updated
        connection = .unknown
        serverEnvironment = nil
        probe = nil
        probeError = nil
        mode = nil
        Task { await checkConnection() }
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
        // An answer is the best evidence there is about the connection.
        switch mode {
        case .demo:
            connection = .demo
        case .live:
            if case .live = connection {} else {
                connection = .live(model: nil)
            }
        }
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
            noteFailure(error)
            return error.userMessage
        }
    }

    /// Keeps the connection indicator honest after a failed request.
    func noteFailure(_ error: APIError) {
        if error.isConnectionProblem {
            connection = .unreachable(error)
        } else if case .unavailable = error {
            // The server answered but its AI did not. Ask it why.
            Task { await checkConnection() }
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

    func toggleSaved(text: String, style: String, intent: Intent?, crushID: UUID? = nil) {
        let clean = text.trimmed
        guard !clean.isEmpty else { return }
        if let index = savedReplies.firstIndex(where: { $0.text == clean }) {
            savedReplies.remove(at: index)
            toast = "Removed from saved."
        } else {
            savedReplies.insert(SavedReply(text: clean, style: style, intent: intent, crushID: crushID), at: 0)
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

    /// Adds a new profile or replaces the stored one with the same id.
    func savePerson(_ person: CrushProfile) {
        var updated = person
        updated.updatedAt = Date()
        if let index = people.firstIndex(where: { $0.id == person.id }) {
            people[index] = updated
        } else {
            people.insert(updated, at: 0)
        }
    }

    func savedReplies(for id: UUID) -> [SavedReply] {
        savedReplies.filter { $0.crushID == id }
    }

    func sessions(for id: UUID) -> [SavedSession] {
        sessions.filter { $0.crushID == id }
    }

    /// Permanently removes a profile and everything attached to it: photo,
    /// replies and conversations saved for that person, and keyboard context about them.
    func deletePerson(_ id: UUID) {
        store.deletePerson(id)
        // The store did the work on disk. Bring memory in line without writing it all again.
        people = store.loadPeople()
        savedReplies = store.loadSavedReplies()
        sessions = store.loadSessions()
        settings = store.loadSettings()
        keyboardContext = store.loadKeyboardContext()
        if compose.crush?.id == id {
            compose.crush = nil
        }
        Haptics.success()
        toast = "Deleted for good."
    }

    /// Writes everything held about one person to a temporary file the user can save or share.
    func exportPerson(_ id: UUID) -> URL? {
        guard let person = self.person(id), let data = store.exportPerson(id) else { return nil }
        let safeName = person.alias.trimmed.replacingOccurrences(of: "/", with: "-")
        let name = "ReplyRight - \(safeName.isEmpty ? "profile" : safeName).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    // MARK: Keyboard handoff

    /// Makes conversation text available to the ReplyRight keyboard. Only ever called from an explicit tap.
    func handToKeyboard(_ text: String, crush: CrushProfile?) {
        let context = KeyboardContext(text: text, source: .app, crush: crush?.payload, crushID: crush?.id)
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

    // MARK: Starting a flow

    /// Opens the conversation screen on the Home tab, optionally with the goal already chosen.
    func startCompose(intent: Intent? = nil) {
        compose.reset()
        if let intent {
            compose.intent = intent
            compose.intentWasChosen = true
        }
        selectedTab = .home
        homePath = [.input]
    }

    /// Continues with something the user shared to ReplyRight from another app.
    func openInbox() {
        guard let item = inbox else { return }
        compose.reset()
        compose.text = item.text
        compose.addPrepared(store.inboxImages(for: item))
        dismissInbox()
        selectedTab = .home
        homePath = [.input]
    }

    /// Reopens a saved session so new replies can be written for it.
    func reopen(_ session: SavedSession) {
        compose.load(session: session, person: person(session.crushID))
        selectedTab = .home
        homePath = [.replies]
    }

    // MARK: Coach

    func askCoach(question: String? = nil, conversation: String = "", draft: String = "", crushID: UUID? = nil) {
        coachSeed = CoachSeed(mode: .ask, question: question, conversation: conversation, draft: draft, crushID: crushID)
        selectedTab = .coach
    }

    /// Opens the coach to look at one message the user wrote.
    func reviewWithCoach(draft: String, conversation: String = "", crushID: UUID? = nil) {
        coachSeed = CoachSeed(mode: .review, question: nil, conversation: conversation, draft: draft, crushID: crushID)
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
            store.erase(.people)
            people = []
            var updated = settings
            updated.lastCrushID = nil
            updated.keyboardCrushID = nil
            settings = updated
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
