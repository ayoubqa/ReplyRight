import Foundation

// Request and response types for API v1. They mirror
// `backend/src/lib/domain/contracts.ts`; change both sides together.

/// Server-side limits, applied on the client before sending so requests are never rejected for size.
public enum RequestLimits {
    public static let conversationChars = 6000
    public static let transcriptLines = 80
    public static let transcriptLineChars = 1000
    public static let instructionChars = 200
    public static let situationChars = 600
    public static let draftChars = 1000
    public static let maxImages = 4
    public static let maxImageBytes = 4 * 1024 * 1024
    public static let avoidReplies = 9
    public static let coachMessages = 24
    public static let coachMessageChars = 1500

    static func clip(_ text: String, _ limit: Int) -> String {
        String(text.trimmed.prefix(limit))
    }

    static func clean(_ transcript: [TranscriptLine]) -> [TranscriptLine] {
        transcript
            .map { TranscriptLine(speaker: $0.speaker, text: clip($0.text, transcriptLineChars)) }
            .filter { !$0.text.isEmpty }
            .suffix(transcriptLines)
            .map { $0 }
    }
}

public enum GenerationMode: String, Codable, Sendable {
    /// Replies written by the AI provider.
    case live
    /// Pre-written samples. The server has no AI provider configured.
    case demo
}

public enum Tier: String, Codable, Sendable {
    case free
    case pro
}

public struct Usage: Codable, Equatable, Sendable {
    public struct Counter: Codable, Equatable, Sendable {
        public var used: Int
        public var limit: Int
        public var remaining: Int

        public init(used: Int, limit: Int, remaining: Int) {
            self.used = used
            self.limit = limit
            self.remaining = remaining
        }
    }

    public var tier: Tier
    public var generations: Counter
    public var coach: Counter
    /// ISO 8601 timestamp of the next daily reset.
    public var resetsAt: String

    public init(tier: Tier, generations: Counter, coach: Counter, resetsAt: String) {
        self.tier = tier
        self.generations = generations
        self.coach = coach
        self.resetsAt = resetsAt
    }

    public var resetDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetsAt)
    }
}

/// The wrapper around every successful AI response.
public struct Envelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    public var mode: GenerationMode
    public var provider: String
    public var model: String?
    public var usage: Usage
    public var result: Payload

    public init(mode: GenerationMode, provider: String, model: String?, usage: Usage, result: Payload) {
        self.mode = mode
        self.provider = provider
        self.model = model
        self.usage = usage
        self.result = result
    }
}

// MARK: - Analyze

public struct AnalyzeRequest: Encodable, Sendable {
    public var conversation: String
    public var crush: CrushPayload?
    public var locale: String

    public init(conversation: String, crush: CrushPayload? = nil, locale: String = AppConfig.appLocale) {
        self.conversation = ConversationText.clampRecent(conversation, limit: RequestLimits.conversationChars)
        self.crush = crush
        self.locale = locale
    }
}

// MARK: - Replies

public struct RepliesRequest: Encodable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Answer a conversation.
        case reply
        /// Open one, or restart a quiet one.
        case starter
    }

    public var kind: Kind
    public var conversation: String
    public var transcript: [TranscriptLine]
    public var situation: String
    public var intent: Intent
    public var instruction: String
    public var draft: String
    public var avoid: [String]
    public var voice: VoicePayload?
    public var crush: CrushPayload?
    public var locale: String

    public init(
        kind: Kind = .reply,
        conversation: String = "",
        transcript: [TranscriptLine] = [],
        situation: String = "",
        intent: Intent = .natural,
        instruction: String = "",
        draft: String = "",
        avoid: [String] = [],
        voice: VoicePayload? = nil,
        crush: CrushPayload? = nil,
        locale: String = AppConfig.appLocale
    ) {
        self.kind = kind
        self.conversation = ConversationText.clampRecent(conversation, limit: RequestLimits.conversationChars)
        self.transcript = RequestLimits.clean(transcript)
        self.situation = RequestLimits.clip(situation, RequestLimits.situationChars)
        self.intent = intent
        self.instruction = RequestLimits.clip(instruction, RequestLimits.instructionChars)
        self.draft = RequestLimits.clip(draft, RequestLimits.draftChars)
        self.avoid = avoid.suffix(RequestLimits.avoidReplies).map { String($0.prefix(1000)) }
        self.voice = voice
        self.crush = crush
        self.locale = locale
    }
}

public struct RepliesResult: Codable, Equatable, Sendable {
    /// A short, warm line shown above the options.
    public var note: String
    public var replies: [Suggestion]
    public var headsUp: String?

    public init(note: String, replies: [Suggestion], headsUp: String?) {
        self.note = note
        self.replies = replies
        self.headsUp = headsUp
    }
}

// MARK: - Refine

public struct RefineRequest: Encodable, Sendable {
    public var text: String
    public var action: RefineAction
    public var instruction: String
    /// 1 replaces a single message; 3 offers alternatives.
    public var count: Int
    public var conversation: String
    public var voice: VoicePayload?
    public var crush: CrushPayload?
    public var locale: String

    public init(
        text: String,
        action: RefineAction,
        instruction: String = "",
        count: Int = 1,
        conversation: String = "",
        voice: VoicePayload? = nil,
        crush: CrushPayload? = nil,
        locale: String = AppConfig.appLocale
    ) {
        self.text = RequestLimits.clip(text, RequestLimits.draftChars)
        self.action = action
        self.instruction = RequestLimits.clip(instruction, RequestLimits.instructionChars)
        self.count = count == 3 ? 3 : 1
        self.conversation = ConversationText.clampRecent(conversation, limit: RequestLimits.conversationChars)
        self.voice = voice
        self.crush = crush
        self.locale = locale
    }
}

public struct RefineResult: Codable, Equatable, Sendable {
    public var options: [Suggestion]
    public var note: String?

    public init(options: [Suggestion], note: String?) {
        self.options = options
        self.note = note
    }
}

// MARK: - Coach

public struct CoachTurn: Codable, Equatable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case coach
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// What kind of help the user wants from the coach.
public enum CoachMode: String, Codable, CaseIterable, Sendable {
    /// A question, optionally about a draft or a conversation.
    case ask
    /// Feedback on one message the user wrote or plans to send.
    case review
    /// A rehearsal: the coach plays the other person and gives feedback.
    case practice
}

/// The skill a coaching conversation is about.
public enum CoachTopic: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case flirting
    case conversation
    case askingOut = "asking_out"
    case confidence

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "Anything"
        case .flirting: return "Flirting"
        case .conversation: return "Conversation"
        case .askingOut: return "Asking them out"
        case .confidence: return "Confidence"
        }
    }

    public var blurb: String {
        switch self {
        case .general: return "Ask whatever is on your mind"
        case .flirting: return "Playful, warm, never pushy"
        case .conversation: return "Keep it alive without forcing it"
        case .askingOut: return "Timing, wording, and taking it lightly"
        case .confidence: return "Say what you mean, calmly"
        }
    }

    /// Questions that open a conversation on this topic.
    public var starters: [String] {
        switch self {
        case .general:
            return ["What should I say next?", "Does my reply sound too eager?", "Can you make this less awkward?"]
        case .flirting:
            return ["How do I flirt without it sounding forced?", "How do I tease someone without being mean?", "How can I show I'm interested without overdoing it?"]
        case .conversation:
            return ["How do I keep a conversation going?", "What do I say when they give one-word answers?", "How do I stop interviewing people?"]
        case .askingOut:
            return ["How do I go from chatting to asking them out?", "Is it too soon to suggest meeting?", "How do I ask without making it a big deal?"]
        case .confidence:
            return ["How do I stop over-explaining?", "How do I sound sure of myself without being arrogant?", "How do I stop apologising in every message?"]
        }
    }
}

/// A situation to rehearse with the coach.
public enum PracticeScenario: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case firstMessage = "first_message"
    case keepItGoing = "keep_it_going"
    case flirting
    case askingOut = "asking_out"
    case reconnecting
    case boundary
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .firstMessage: return "A first message"
        case .keepItGoing: return "Reviving a flat chat"
        case .flirting: return "Flirting"
        case .askingOut: return "Asking them out"
        case .reconnecting: return "Reconnecting"
        case .boundary: return "Saying no kindly"
        case .custom: return "My own situation"
        }
    }

    public var blurb: String {
        switch self {
        case .firstMessage: return "You open. See what earns a reply."
        case .keepItGoing: return "They send something dry. You bring it back."
        case .flirting: return "Light, warm, and a little bold."
        case .askingOut: return "Move from chatting to a plan."
        case .reconnecting: return "It's been a few weeks. You start."
        case .boundary: return "Clear and kind, without apologising."
        case .custom: return "Describe it and we'll play it out."
        }
    }
}

/// The scenario being rehearsed, as sent to the server.
public struct PracticeSetup: Codable, Equatable, Hashable, Sendable {
    public static let maxDetailLength = 300

    public var id: PracticeScenario
    public var detail: String

    public init(id: PracticeScenario, detail: String = "") {
        self.id = id
        self.detail = RequestLimits.clip(detail, PracticeSetup.maxDetailLength)
    }
}

public struct CoachRequest: Encodable, Sendable {
    public var mode: CoachMode
    public var topic: CoachTopic
    /// In practice mode these are the rehearsal turns: `.user` is what the user
    /// sent and `.coach` is what the simulated person answered.
    public var messages: [CoachTurn]
    public var conversation: String
    public var draft: String
    /// Review: what the user wants the message to get across.
    public var goal: String
    public var scenario: PracticeSetup?
    public var voice: VoicePayload?
    public var crush: CrushPayload?
    public var locale: String

    public init(
        mode: CoachMode = .ask,
        topic: CoachTopic = .general,
        messages: [CoachTurn] = [],
        conversation: String = "",
        draft: String = "",
        goal: String = "",
        scenario: PracticeSetup? = nil,
        voice: VoicePayload? = nil,
        crush: CrushPayload? = nil,
        locale: String = AppConfig.appLocale
    ) {
        var recent = Array(
            messages
                .map { CoachTurn(role: $0.role, text: RequestLimits.clip($0.text, RequestLimits.coachMessageChars)) }
                .filter { !$0.text.isEmpty }
                .suffix(RequestLimits.coachMessages)
        )
        // A question to the coach should open on the user's turn so the exchange
        // still reads naturally. A rehearsal may open with the other person.
        if mode != .practice {
            while let first = recent.first, first.role != .user, recent.count > 1 {
                recent.removeFirst()
            }
        }
        self.mode = mode
        self.topic = topic
        self.messages = recent
        self.conversation = ConversationText.clampRecent(conversation, limit: RequestLimits.conversationChars)
        self.draft = RequestLimits.clip(draft, RequestLimits.draftChars)
        self.goal = RequestLimits.clip(goal, RequestLimits.instructionChars)
        self.scenario = mode == .practice ? scenario : nil
        self.voice = voice
        self.crush = crush
        self.locale = locale
    }
}

public struct CoachSuggestion: Codable, Equatable, Hashable, Sendable {
    public var label: String
    public var text: String

    public init(label: String, text: String) {
        self.label = label
        self.text = text
    }
}

/// The coach's feedback on one message the user wrote.
///
/// `comesAcross` describes how the words could read. It is never a claim about
/// what the other person will think.
public struct CoachReview: Codable, Equatable, Hashable, Sendable {
    public struct Check: Codable, Equatable, Hashable, Identifiable, Sendable {
        public enum Verdict: String, Sendable {
            /// Leave it.
            case good
            /// A small risk.
            case watch
            /// Works against what the user wants.
            case rework
        }

        /// "natural", "intensity", "formality", "feeling" or "clarity".
        public var aspect: String
        public var verdict: String
        public var note: String

        public var id: String { aspect }

        public init(aspect: String, verdict: String, note: String) {
            self.aspect = aspect
            self.verdict = verdict
            self.note = note
        }

        /// Unknown verdicts from a newer server are treated as "watch".
        public var level: Verdict { Verdict(rawValue: verdict) ?? .watch }

        /// The question this check answers.
        public var question: String {
            switch aspect {
            case "natural": return "Does it sound natural?"
            case "intensity": return "Is it too intense?"
            case "formality": return "Is it too formal?"
            case "feeling": return "Does it carry the feeling you mean?"
            case "clarity": return "Could it be misunderstood?"
            default: return aspect.capitalized
            }
        }

        /// A one or two word answer to `question`.
        public var answer: String {
            switch (aspect, level) {
            case ("natural", .good): return "Yes"
            case ("natural", .watch): return "Mostly"
            case ("natural", .rework): return "Not yet"
            case ("intensity", .good): return "No"
            case ("intensity", .watch): return "A little"
            case ("intensity", .rework): return "Yes"
            case ("formality", .good): return "No"
            case ("formality", .watch): return "A little"
            case ("formality", .rework): return "Yes"
            case ("feeling", .good): return "Yes"
            case ("feeling", .watch): return "Partly"
            case ("feeling", .rework): return "Not yet"
            case ("clarity", .good): return "Unlikely"
            case ("clarity", .watch): return "Possibly"
            case ("clarity", .rework): return "Likely"
            case (_, .good): return "Good"
            case (_, .watch): return "Worth a look"
            case (_, .rework): return "Rework"
            }
        }
    }

    /// What the user is trying to communicate.
    public var intent: String
    /// What the message as written communicates.
    public var comesAcross: String
    public var checks: [Check]
    /// What could be improved. Empty when the message is already good.
    public var improvements: [String]
    /// A suggested alternative, ready to send.
    public var alternative: String
    public var whyItWorks: String
    /// A small lesson to reuse next time.
    public var lesson: String

    public init(
        intent: String,
        comesAcross: String,
        checks: [Check],
        improvements: [String],
        alternative: String,
        whyItWorks: String,
        lesson: String
    ) {
        self.intent = intent
        self.comesAcross = comesAcross
        self.checks = checks
        self.improvements = improvements
        self.alternative = alternative
        self.whyItWorks = whyItWorks
        self.lesson = lesson
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intent = (try? c.decodeIfPresent(String.self, forKey: .intent)) ?? ""
        comesAcross = (try? c.decodeIfPresent(String.self, forKey: .comesAcross)) ?? ""
        checks = (try? c.decodeIfPresent([Check].self, forKey: .checks)) ?? []
        improvements = (try? c.decodeIfPresent([String].self, forKey: .improvements)) ?? []
        alternative = (try? c.decodeIfPresent(String.self, forKey: .alternative)) ?? ""
        whyItWorks = (try? c.decodeIfPresent(String.self, forKey: .whyItWorks)) ?? ""
        lesson = (try? c.decodeIfPresent(String.self, forKey: .lesson)) ?? ""
    }
}

/// One step of a rehearsal.
public struct CoachPractice: Codable, Equatable, Hashable, Sendable {
    /// The simulated person's next message. Nil when the user should go first or the rehearsal is over.
    public var partnerReply: String?
    /// Coaching on the user's latest practice message.
    public var feedback: String?
    public var tryThis: String?
    public var finished: Bool

    public init(partnerReply: String?, feedback: String?, tryThis: String?, finished: Bool) {
        self.partnerReply = partnerReply
        self.feedback = feedback
        self.tryThis = tryThis
        self.finished = finished
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        partnerReply = try? c.decodeIfPresent(String.self, forKey: .partnerReply)
        feedback = try? c.decodeIfPresent(String.self, forKey: .feedback)
        tryThis = try? c.decodeIfPresent(String.self, forKey: .tryThis)
        finished = (try? c.decodeIfPresent(Bool.self, forKey: .finished)) ?? false
    }
}

public struct CoachResult: Codable, Equatable, Sendable {
    public var message: String
    public var suggestions: [CoachSuggestion]
    public var followUps: [String]
    /// One small takeaway worth remembering.
    public var lesson: String?
    public var review: CoachReview?
    public var practice: CoachPractice?
    public var headsUp: String?

    public init(
        message: String,
        suggestions: [CoachSuggestion],
        followUps: [String],
        headsUp: String?,
        lesson: String? = nil,
        review: CoachReview? = nil,
        practice: CoachPractice? = nil
    ) {
        self.message = message
        self.suggestions = suggestions
        self.followUps = followUps
        self.headsUp = headsUp
        self.lesson = lesson
        self.review = review
        self.practice = practice
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message = try c.decode(String.self, forKey: .message)
        suggestions = (try? c.decodeIfPresent([CoachSuggestion].self, forKey: .suggestions)) ?? []
        followUps = (try? c.decodeIfPresent([String].self, forKey: .followUps)) ?? []
        lesson = try? c.decodeIfPresent(String.self, forKey: .lesson)
        review = try? c.decodeIfPresent(CoachReview.self, forKey: .review)
        practice = try? c.decodeIfPresent(CoachPractice.self, forKey: .practice)
        headsUp = try? c.decodeIfPresent(String.self, forKey: .headsUp)
    }
}

// MARK: - Status and plans

/// What a plan allows. Delivered by the server so limits are never hardcoded in the app.
public struct PlanInfo: Codable, Equatable, Sendable {
    public var dailyGenerations: Int
    public var dailyCoachMessages: Int
    public var intents: [String]
    public var voiceSamples: Bool

    public init(dailyGenerations: Int, dailyCoachMessages: Int, intents: [String], voiceSamples: Bool) {
        self.dailyGenerations = dailyGenerations
        self.dailyCoachMessages = dailyCoachMessages
        self.intents = intents
        self.voiceSamples = voiceSamples
    }

    public func includes(_ intent: Intent) -> Bool {
        intents.contains(intent.rawValue)
    }
}

public struct PlanCatalog: Codable, Equatable, Sendable {
    public var free: PlanInfo
    public var pro: PlanInfo

    public init(free: PlanInfo, pro: PlanInfo) {
        self.free = free
        self.pro = pro
    }

    public func plan(for tier: Tier) -> PlanInfo {
        tier == .pro ? pro : free
    }

    /// Used until the first status response arrives. Matches the server defaults.
    public static let fallback = PlanCatalog(
        free: PlanInfo(
            dailyGenerations: 10,
            dailyCoachMessages: 3,
            intents: [Intent.natural, .flirt, .laugh, .interest, .keepGoing, .boundary].map(\.rawValue),
            voiceSamples: false
        ),
        pro: PlanInfo(
            dailyGenerations: 400,
            dailyCoachMessages: 200,
            intents: Intent.allCases.map(\.rawValue),
            voiceSamples: true
        )
    )
}

/// What the server reports about its AI provider. Model names and coarse health only.
public struct AIStatus: Decodable, Equatable, Sendable {
    /// "untested", "ok" or "failing".
    public var state: String
    public var lastFailureReason: String?
    /// The model used for each task, in live mode.
    public var models: [String: String]

    public init(state: String, lastFailureReason: String? = nil, models: [String: String] = [:]) {
        self.state = state
        self.lastFailureReason = lastFailureReason
        self.models = models
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case lastFailureReason
        case models
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? "untested"
        lastFailureReason = try? c.decodeIfPresent(String.self, forKey: .lastFailureReason)
        models = (try? c.decodeIfPresent([String: String].self, forKey: .models)) ?? [:]
    }

    /// The model that writes replies, for display.
    public var primaryModel: String? {
        models["replies"] ?? models.values.sorted().first
    }
}

public struct StatusResponse: Decodable, Sendable {
    public var apiVersion: Int
    public var mode: GenerationMode
    public var provider: String
    public var supportsImages: Bool
    public var plans: PlanCatalog
    public var usage: Usage
    /// "development", "staging" or "production". Absent on older servers.
    public var environment: String?
    public var ai: AIStatus?
}

/// The result of asking the server to make one small, fixed AI call.
public struct ProbeResult: Decodable, Equatable, Sendable {
    public var ok: Bool
    public var mode: GenerationMode
    public var model: String?
    public var latencyMs: Int
    public var reason: String?
}

struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        var code: String
        var message: String
        var usage: Usage?
        /// A coarse cause for an AI failure, for diagnostics.
        var reason: String?
    }

    var error: Detail
}
