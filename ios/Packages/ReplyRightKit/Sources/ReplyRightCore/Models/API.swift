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

public struct CoachRequest: Encodable, Sendable {
    public var messages: [CoachTurn]
    public var conversation: String
    public var draft: String
    public var voice: VoicePayload?
    public var crush: CrushPayload?
    public var locale: String

    public init(
        messages: [CoachTurn],
        conversation: String = "",
        draft: String = "",
        voice: VoicePayload? = nil,
        crush: CrushPayload? = nil,
        locale: String = AppConfig.appLocale
    ) {
        // Keep the most recent turns, starting from a user turn so the exchange still reads naturally.
        var recent = Array(
            messages
                .map { CoachTurn(role: $0.role, text: RequestLimits.clip($0.text, RequestLimits.coachMessageChars)) }
                .filter { !$0.text.isEmpty }
                .suffix(RequestLimits.coachMessages)
        )
        while let first = recent.first, first.role != .user, recent.count > 1 {
            recent.removeFirst()
        }
        self.messages = recent
        self.conversation = ConversationText.clampRecent(conversation, limit: RequestLimits.conversationChars)
        self.draft = RequestLimits.clip(draft, RequestLimits.draftChars)
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

public struct CoachResult: Codable, Equatable, Sendable {
    public var message: String
    public var suggestions: [CoachSuggestion]
    public var followUps: [String]
    public var headsUp: String?

    public init(message: String, suggestions: [CoachSuggestion], followUps: [String], headsUp: String?) {
        self.message = message
        self.suggestions = suggestions
        self.followUps = followUps
        self.headsUp = headsUp
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

public struct StatusResponse: Decodable, Sendable {
    public var apiVersion: Int
    public var mode: GenerationMode
    public var provider: String
    public var supportsImages: Bool
    public var plans: PlanCatalog
    public var usage: Usage
}

struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        var code: String
        var message: String
        var usage: Usage?
    }

    var error: Detail
}
