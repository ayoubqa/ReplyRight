import Foundation

/// A private profile of someone the user is talking to.
///
/// Everything in it was typed by the user. ReplyRight never fills a field in
/// by itself and never infers anything about the person. The profile lives
/// only on this device. A trimmed copy (`CrushPayload`) travels with a request
/// only when the user picked this person for that conversation, and it holds
/// only the parts the user has allowed in `sharing`.
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

        public var shortTitle: String {
            switch self {
            case .newMatch: return "New"
            case .talking: return "Talking"
            case .beenOnDates: return "Dating"
            case .seeingEachOther: return "Together"
            case .reconnecting: return "Reconnecting"
            }
        }
    }

    /// Which parts of the profile may be used as context when the user picks this person.
    ///
    /// The nickname and where things stand always go, because a profile is no
    /// use without them. Everything else is a switch the user controls.
    public struct Sharing: Codable, Equatable, Hashable, Sendable {
        /// Where they met and the language they prefer.
        public var basics: Bool
        public var interests: Bool
        public var background: Bool
        public var preferences: Bool
        public var details: Bool
        /// Summaries of earlier conversations.
        public var history: Bool
        /// Private notes. Off unless the user turns it on.
        public var notes: Bool

        public init(
            basics: Bool = true,
            interests: Bool = true,
            background: Bool = true,
            preferences: Bool = true,
            details: Bool = true,
            history: Bool = true,
            notes: Bool = false
        ) {
            self.basics = basics
            self.interests = interests
            self.background = background
            self.preferences = preferences
            self.details = details
            self.history = history
            self.notes = notes
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            basics = (try? c.decodeIfPresent(Bool.self, forKey: .basics)) ?? true
            interests = (try? c.decodeIfPresent(Bool.self, forKey: .interests)) ?? true
            background = (try? c.decodeIfPresent(Bool.self, forKey: .background)) ?? true
            preferences = (try? c.decodeIfPresent(Bool.self, forKey: .preferences)) ?? true
            details = (try? c.decodeIfPresent(Bool.self, forKey: .details)) ?? true
            history = (try? c.decodeIfPresent(Bool.self, forKey: .history)) ?? true
            notes = (try? c.decodeIfPresent(Bool.self, forKey: .notes)) ?? false
        }

        /// Nothing beyond the nickname and where things stand.
        public static let nothing = Sharing(
            basics: false, interests: false, background: false, preferences: false, details: false, history: false, notes: false
        )
    }

    /// A short summary of an earlier conversation, written or approved by the user.
    public struct Summary: Codable, Identifiable, Equatable, Hashable, Sendable {
        public enum Source: String, Codable, Sendable {
            /// The user typed it.
            case written
            /// The user chose to keep ReplyRight's read of a conversation.
            case conversation
        }

        public var id: UUID
        public var date: Date
        public var text: String
        public var source: Source

        public init(id: UUID = UUID(), date: Date = Date(), text: String, source: Source = .written) {
            self.id = id
            self.date = date
            self.text = String(text.trimmed.prefix(CrushProfile.maxSummaryLength))
            self.source = source
        }
    }

    public static let maxAliasLength = 40
    public static let maxNotesLength = 400
    public static let maxMetAtLength = 80
    public static let maxInterests = 10
    public static let maxInterestLength = 40
    public static let maxBackgroundLength = 400
    public static let maxPreferencesLength = 300
    public static let maxDetailsLength = 400
    public static let maxHistoryLength = 600
    public static let maxSummaryLength = 300
    public static let maxSummaries = 20

    public var id: UUID
    /// The name or nickname the user uses for this person.
    public var alias: String
    public var stage: Stage
    /// Private notes about conversations. Not shared unless `sharing.notes` is on.
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date
    public var metAt: String
    /// A `ReplyLanguage` id such as "es", or empty when not set.
    public var language: String
    public var interests: [String]
    public var background: String
    /// How this person likes to communicate, as far as the user knows.
    public var preferences: String
    /// Things worth remembering: an exam on Friday, a dog called Miso.
    public var details: String
    public var summaries: [Summary]
    /// True when a photo is stored for this profile. The image is a separate file on the device.
    public var hasPhoto: Bool
    public var sharing: Sharing

    public init(
        id: UUID = UUID(),
        alias: String,
        stage: Stage = .talking,
        notes: String = "",
        createdAt: Date = Date(),
        metAt: String = "",
        language: String = "",
        interests: [String] = [],
        background: String = "",
        preferences: String = "",
        details: String = "",
        summaries: [Summary] = [],
        hasPhoto: Bool = false,
        sharing: Sharing = Sharing()
    ) {
        self.id = id
        self.alias = alias
        self.stage = stage
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.metAt = metAt
        self.language = language
        self.interests = interests
        self.background = background
        self.preferences = preferences
        self.details = details
        self.summaries = summaries
        self.hasPhoto = hasPhoto
        self.sharing = sharing
    }

    // Tolerant decoding: profiles saved by an earlier version have only a
    // nickname, a stage and notes. In that version the notes were the context
    // sent with a request, so they stay shared for those profiles.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        alias = (try? c.decodeIfPresent(String.self, forKey: .alias)) ?? ""
        stage = (try? c.decodeIfPresent(Stage.self, forKey: .stage)) ?? .talking
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        let created = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        createdAt = created
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? created
        metAt = (try? c.decodeIfPresent(String.self, forKey: .metAt)) ?? ""
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? ""
        interests = (try? c.decodeIfPresent([String].self, forKey: .interests)) ?? []
        background = (try? c.decodeIfPresent(String.self, forKey: .background)) ?? ""
        preferences = (try? c.decodeIfPresent(String.self, forKey: .preferences)) ?? ""
        details = (try? c.decodeIfPresent(String.self, forKey: .details)) ?? ""
        summaries = (try? c.decodeIfPresent([Summary].self, forKey: .summaries)) ?? []
        hasPhoto = (try? c.decodeIfPresent(Bool.self, forKey: .hasPhoto)) ?? false
        if let stored = try? c.decodeIfPresent(Sharing.self, forKey: .sharing) {
            sharing = stored
        } else {
            sharing = Sharing(notes: true)
        }
    }

    // MARK: What leaves the device

    /// The context sent with a request when the user picked this person: the
    /// nickname, where things stand, and only the parts allowed in `sharing`.
    /// Nil when the nickname is empty, because the server requires one.
    ///
    /// The photo, saved replies and anything switched off never leave the device.
    public var payload: CrushPayload? {
        let name = String(alias.trimmed.prefix(CrushProfile.maxAliasLength))
        guard !name.isEmpty else { return nil }
        func clip(_ text: String, _ limit: Int) -> String { String(text.trimmed.prefix(limit)) }

        return CrushPayload(
            alias: name,
            stage: stage,
            notes: sharing.notes ? clip(notes, CrushProfile.maxNotesLength) : "",
            metAt: sharing.basics ? clip(metAt, CrushProfile.maxMetAtLength) : "",
            language: sharing.basics ? languageName : "",
            interests: sharing.interests ? cleanInterests : [],
            background: sharing.background ? clip(background, CrushProfile.maxBackgroundLength) : "",
            preferences: sharing.preferences ? clip(preferences, CrushProfile.maxPreferencesLength) : "",
            details: sharing.details ? clip(details, CrushProfile.maxDetailsLength) : "",
            history: sharing.history ? historyText : ""
        )
    }

    /// Interests trimmed, de-duplicated and capped, as they are stored and sent.
    public var cleanInterests: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for interest in interests {
            let clean = String(interest.trimmed.prefix(CrushProfile.maxInterestLength))
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { continue }
            result.append(clean)
            if result.count == CrushProfile.maxInterests { break }
        }
        return result
    }

    /// The English name of the preferred language, or empty when not set.
    public var languageName: String {
        ReplyLanguage.all.first { $0.id == language }?.name ?? ""
    }

    /// The most recent summaries joined into one short text, newest first.
    public var historyText: String {
        var text = ""
        for summary in summaries.sorted(by: { $0.date > $1.date }) {
            let line = summary.text.trimmed
            guard !line.isEmpty else { continue }
            let next = text.isEmpty ? line : text + " | " + line
            if next.count > CrushProfile.maxHistoryLength { break }
            text = next
        }
        return text
    }

    /// A plain list of what would be sent for this person right now, for the consent screen.
    public var sharedFieldNames: [String] {
        guard let payload else { return [] }
        var names = ["Name", "Where things stand"]
        if !payload.metAt.isEmpty { names.append("Where you met") }
        if !payload.language.isEmpty { names.append("Preferred language") }
        if !payload.interests.isEmpty { names.append("Interests") }
        if !payload.background.isEmpty { names.append("Background") }
        if !payload.preferences.isEmpty { names.append("Communication preferences") }
        if !payload.details.isEmpty { names.append("Important details") }
        if !payload.history.isEmpty { names.append("Conversation summaries") }
        if !payload.notes.isEmpty { names.append("Private notes") }
        return names
    }

    public mutating func addSummary(_ text: String, source: Summary.Source = .written, date: Date = Date()) {
        let summary = Summary(date: date, text: text, source: source)
        guard !summary.text.isEmpty else { return }
        summaries.insert(summary, at: 0)
        if summaries.count > CrushProfile.maxSummaries {
            summaries.removeLast(summaries.count - CrushProfile.maxSummaries)
        }
        updatedAt = date
    }

    public var initial: String {
        alias.trimmed.first.map { String($0).uppercased() } ?? "?"
    }

    /// One line under the name in a list.
    public var subtitle: String {
        let place = metAt.trimmed
        return place.isEmpty ? stage.title : "\(stage.title) · \(place)"
    }
}

/// Wire format. Mirrors `crushSchema` in the backend.
public struct CrushPayload: Codable, Equatable, Hashable, Sendable {
    public var alias: String
    public var stage: CrushProfile.Stage
    public var notes: String
    public var metAt: String
    public var language: String
    public var interests: [String]
    public var background: String
    public var preferences: String
    public var details: String
    public var history: String

    public init(
        alias: String,
        stage: CrushProfile.Stage,
        notes: String = "",
        metAt: String = "",
        language: String = "",
        interests: [String] = [],
        background: String = "",
        preferences: String = "",
        details: String = "",
        history: String = ""
    ) {
        self.alias = alias
        self.stage = stage
        self.notes = notes
        self.metAt = metAt
        self.language = language
        self.interests = interests
        self.background = background
        self.preferences = preferences
        self.details = details
        self.history = history
    }

    // Context handed to the keyboard by an earlier version has only three fields.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alias = try c.decode(String.self, forKey: .alias)
        stage = (try? c.decodeIfPresent(CrushProfile.Stage.self, forKey: .stage)) ?? .talking
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        metAt = (try? c.decodeIfPresent(String.self, forKey: .metAt)) ?? ""
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? ""
        interests = (try? c.decodeIfPresent([String].self, forKey: .interests)) ?? []
        background = (try? c.decodeIfPresent(String.self, forKey: .background)) ?? ""
        preferences = (try? c.decodeIfPresent(String.self, forKey: .preferences)) ?? ""
        details = (try? c.decodeIfPresent(String.self, forKey: .details)) ?? ""
        history = (try? c.decodeIfPresent(String.self, forKey: .history)) ?? ""
    }
}

/// Everything ReplyRight holds about one person, in a form the user can take away.
public struct ProfileExport: Codable, Sendable {
    public var exportedAt: Date
    public var app: String
    public var profile: CrushProfile
    public var savedReplies: [SavedReply]
    public var conversations: [SavedSession]
    /// The profile photo as base64 JPEG, when there is one.
    public var photoJPEGBase64: String?

    public init(
        exportedAt: Date = Date(),
        profile: CrushProfile,
        savedReplies: [SavedReply],
        conversations: [SavedSession],
        photoJPEGBase64: String?
    ) {
        self.exportedAt = exportedAt
        self.app = "ReplyRight \(AppConfig.appVersion)"
        self.profile = profile
        self.savedReplies = savedReplies
        self.conversations = conversations
        self.photoJPEGBase64 = photoJPEGBase64
    }
}
