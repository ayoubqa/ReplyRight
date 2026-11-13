import Foundation

public enum Speaker: String, Codable, Hashable, Sendable {
    case them
    case me
    case unknown

    /// Cycles them -> me -> unknown, used when the user corrects who said what.
    public var next: Speaker {
        switch self {
        case .them: return .me
        case .me: return .unknown
        case .unknown: return .them
        }
    }
}

/// One message in a conversation.
public struct TranscriptLine: Codable, Identifiable, Equatable, Hashable, Sendable {
    /// Local identity for lists. Not part of the wire format.
    public var id: UUID = UUID()
    public var speaker: Speaker
    public var text: String

    private enum CodingKeys: String, CodingKey {
        case speaker
        case text
    }

    public init(speaker: Speaker, text: String) {
        self.speaker = speaker
        self.text = text
    }
}

/// What ReplyRight understood from a shared conversation.
///
/// `observations` are things visible in the messages. `assumptions` are things
/// nobody can know from a text, phrased as possibilities. The UI keeps the two
/// apart so the app never presents a guess as a fact.
public struct Analysis: Codable, Equatable, Sendable {
    public var canReply: Bool
    public var transcript: [TranscriptLine]
    public var latestMessage: String?
    public var latestFromMe: Bool
    public var read: String
    public var toneLabel: String
    public var observations: [String]
    public var assumptions: [String]
    public var opportunity: String
    public var suggestedIntents: [Intent]
    public var headsUp: String?

    public init(
        canReply: Bool,
        transcript: [TranscriptLine],
        latestMessage: String?,
        latestFromMe: Bool,
        read: String,
        toneLabel: String,
        observations: [String],
        assumptions: [String],
        opportunity: String,
        suggestedIntents: [Intent],
        headsUp: String?
    ) {
        self.canReply = canReply
        self.transcript = transcript
        self.latestMessage = latestMessage
        self.latestFromMe = latestFromMe
        self.read = read
        self.toneLabel = toneLabel
        self.observations = observations
        self.assumptions = assumptions
        self.opportunity = opportunity
        self.suggestedIntents = suggestedIntents
        self.headsUp = headsUp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canReply = try c.decode(Bool.self, forKey: .canReply)
        transcript = try c.decodeIfPresent([TranscriptLine].self, forKey: .transcript) ?? []
        latestMessage = try c.decodeIfPresent(String.self, forKey: .latestMessage)
        latestFromMe = try c.decodeIfPresent(Bool.self, forKey: .latestFromMe) ?? false
        read = try c.decode(String.self, forKey: .read)
        toneLabel = try c.decodeIfPresent(String.self, forKey: .toneLabel) ?? ""
        observations = try c.decodeIfPresent([String].self, forKey: .observations) ?? []
        assumptions = try c.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        opportunity = try c.decodeIfPresent(String.self, forKey: .opportunity) ?? ""
        // Unknown intent ids from a newer server are skipped rather than failing the decode.
        let rawIntents = try c.decodeIfPresent([String].self, forKey: .suggestedIntents) ?? []
        suggestedIntents = rawIntents.compactMap(Intent.init(rawValue:))
        headsUp = try c.decodeIfPresent(String.self, forKey: .headsUp)
    }
}

/// One suggested message as returned by the server.
public struct Suggestion: Codable, Equatable, Hashable, Sendable {
    public var style: String
    public var text: String
    public var why: String

    public init(style: String, text: String, why: String) {
        self.style = style
        self.text = text
        self.why = why
    }
}

/// A suggestion on screen: the user can edit it, refine it and undo.
public struct ReplyOption: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: UUID
    public var style: String
    public var text: String
    public var why: String
    /// The text as it first arrived, so edits can be detected and undone.
    public var originalText: String
    /// Earlier versions of this option, most recent last (for Undo after a refine).
    public var history: [String]

    public init(id: UUID = UUID(), suggestion: Suggestion) {
        self.id = id
        self.style = suggestion.style
        self.text = suggestion.text
        self.why = suggestion.why
        self.originalText = suggestion.text
        self.history = []
    }

    public var isEdited: Bool { text != originalText }

    /// Replaces the text with a refined version, remembering the previous one.
    public mutating func apply(_ suggestion: Suggestion) {
        history.append(text)
        text = suggestion.text
        originalText = suggestion.text
        style = suggestion.style
        why = suggestion.why
    }

    /// Steps back to the previous version. Returns false when there is nothing to undo.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        text = previous
        originalText = previous
        return true
    }
}

public enum ConversationText {
    /// Renders a transcript as labelled plain text ("Them: ...", "Me: ...").
    public static func render(_ transcript: [TranscriptLine]) -> String {
        transcript
            .map { line -> String in
                switch line.speaker {
                case .them: return "Them: \(line.text)"
                case .me: return "Me: \(line.text)"
                case .unknown: return line.text
                }
            }
            .joined(separator: "\n")
    }

    /// Keeps the most recent part of a long conversation, cutting at a line break when possible.
    public static func clampRecent(_ text: String, limit: Int) -> String {
        let clean = text.trimmed
        guard clean.count > limit else { return clean }
        let tail = String(clean.suffix(limit))
        if let newline = tail.firstIndex(of: "\n"), tail.distance(from: tail.startIndex, to: newline) < limit / 4 {
            return String(tail[tail.index(after: newline)...]).trimmed
        }
        return tail.trimmed
    }

    /// A short title for a saved session, taken from the latest message.
    public static func title(latestMessage: String?, fallback: String) -> String {
        let base = (latestMessage ?? "").trimmed
        let source = base.isEmpty ? fallback.trimmed : base
        let firstLine = source.split(separator: "\n").first.map(String.init) ?? source
        return firstLine.count > 60 ? String(firstLine.prefix(57)) + "..." : firstLine
    }
}
