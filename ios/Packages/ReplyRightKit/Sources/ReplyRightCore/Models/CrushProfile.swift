import Foundation

/// Optional context about someone the user is talking to.
///
/// Stored only on the device, under a nickname the user chooses. A trimmed
/// copy (`CrushPayload`) is sent with a request only when the user has picked
/// this person for that conversation.
public struct CrushProfile: Codable, Identifiable, Equatable, Hashable, Sendable {
    public enum Stage: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
        case newMatch = "new_match"
        case talking
        case beenOnDates = "been_on_dates"
        case seeingEachOther = "seeing_each_other"
        case reconnecting

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .newMatch: return "Just matched or met"
            case .talking: return "Talking for a while"
            case .beenOnDates: return "Been on a date or two"
            case .seeingEachOther: return "Seeing each other"
            case .reconnecting: return "Reconnecting"
            }
        }
    }

    public static let maxAliasLength = 40
    public static let maxNotesLength = 400

    public var id: UUID
    public var alias: String
    public var stage: Stage
    public var notes: String
    public var createdAt: Date

    public init(id: UUID = UUID(), alias: String, stage: Stage = .talking, notes: String = "", createdAt: Date = Date()) {
        self.id = id
        self.alias = alias
        self.stage = stage
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Nil when the nickname is empty, because the server requires one.
    public var payload: CrushPayload? {
        let name = String(alias.trimmed.prefix(CrushProfile.maxAliasLength))
        guard !name.isEmpty else { return nil }
        return CrushPayload(alias: name, stage: stage, notes: String(notes.trimmed.prefix(CrushProfile.maxNotesLength)))
    }

    public var initial: String {
        alias.trimmed.first.map { String($0).uppercased() } ?? "?"
    }
}

/// Wire format. Mirrors `crushSchema` in the backend.
public struct CrushPayload: Codable, Equatable, Hashable, Sendable {
    public var alias: String
    public var stage: CrushProfile.Stage
    public var notes: String

    public init(alias: String, stage: CrushProfile.Stage, notes: String) {
        self.alias = alias
        self.stage = stage
        self.notes = notes
    }
}
