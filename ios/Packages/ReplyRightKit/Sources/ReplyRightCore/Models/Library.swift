import Foundation

// Things the user has chosen to keep. All of it lives on the device.

/// A reply the user saved to reuse. Also offered in the ReplyRight keyboard.
public struct SavedReply: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var style: String
    public var intent: Intent?
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, style: String, intent: Intent? = nil, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.style = style
        self.intent = intent
        self.createdAt = createdAt
    }
}

/// A conversation the user explicitly saved. Holds text only, never screenshots.
public struct SavedSession: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var conversation: String
    public var read: String
    public var intent: Intent
    public var instruction: String
    public var options: [ReplyOption]
    public var crushID: UUID?

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        conversation: String,
        read: String,
        intent: Intent,
        instruction: String,
        options: [ReplyOption],
        crushID: UUID?
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.conversation = conversation
        self.read = read
        self.intent = intent
        self.instruction = instruction
        self.options = options
        self.crushID = crushID
    }
}

/// A custom instruction the user wants to reuse, such as "confident but not arrogant".
public struct FavouriteStyle: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var instruction: String

    public init(id: UUID = UUID(), name: String, instruction: String) {
        self.id = id
        self.name = name
        self.instruction = instruction
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Dark. The default: most texting happens after hours.
        case evening
        /// Light.
        case daylight
        /// Follow the system setting.
        case system

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .evening: return "Evening"
            case .daylight: return "Daylight"
            case .system: return "Match iPhone"
            }
        }
    }

    public var hasOnboarded: Bool
    public var confirmedAdult: Bool
    public var appearance: Appearance
    /// When on, a reply the user edits and then copies can be kept as a voice example. Off by default.
    public var learnFromEdits: Bool
    public var hapticsEnabled: Bool
    public var keyboardNudgeDismissed: Bool
    /// The one-time offer to learn from edited replies has been shown.
    public var learnPromptSeen: Bool
    public var lastCrushID: UUID?
    /// Development builds only: points the app at a different backend.
    public var apiBaseURLOverride: String?

    public init(
        hasOnboarded: Bool = false,
        confirmedAdult: Bool = false,
        appearance: Appearance = .evening,
        learnFromEdits: Bool = false,
        hapticsEnabled: Bool = true,
        keyboardNudgeDismissed: Bool = false,
        learnPromptSeen: Bool = false,
        lastCrushID: UUID? = nil,
        apiBaseURLOverride: String? = nil
    ) {
        self.hasOnboarded = hasOnboarded
        self.confirmedAdult = confirmedAdult
        self.appearance = appearance
        self.learnFromEdits = learnFromEdits
        self.hapticsEnabled = hapticsEnabled
        self.keyboardNudgeDismissed = keyboardNudgeDismissed
        self.learnPromptSeen = learnPromptSeen
        self.lastCrushID = lastCrushID
        self.apiBaseURLOverride = apiBaseURLOverride
    }

    // Tolerant decoding so new settings can be added without losing old ones.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasOnboarded = (try? c.decodeIfPresent(Bool.self, forKey: .hasOnboarded)) ?? false
        confirmedAdult = (try? c.decodeIfPresent(Bool.self, forKey: .confirmedAdult)) ?? false
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .evening
        learnFromEdits = (try? c.decodeIfPresent(Bool.self, forKey: .learnFromEdits)) ?? false
        hapticsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? true
        keyboardNudgeDismissed = (try? c.decodeIfPresent(Bool.self, forKey: .keyboardNudgeDismissed)) ?? false
        learnPromptSeen = (try? c.decodeIfPresent(Bool.self, forKey: .learnPromptSeen)) ?? false
        lastCrushID = try? c.decodeIfPresent(UUID.self, forKey: .lastCrushID)
        apiBaseURLOverride = try? c.decodeIfPresent(String.self, forKey: .apiBaseURLOverride)
    }
}

/// Conversation text the user explicitly handed to the keyboard (pasted in the
/// app, sent from the share sheet, or copied and confirmed in the keyboard).
/// It expires on its own and can be cleared at any time.
public struct KeyboardContext: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case app
        case shareSheet
        case clipboard
    }

    public static let lifetime: TimeInterval = 24 * 60 * 60

    public var text: String
    public var source: Source
    public var createdAt: Date
    public var crush: CrushPayload?

    public init(text: String, source: Source, createdAt: Date = Date(), crush: CrushPayload? = nil) {
        self.text = ConversationText.clampRecent(text, limit: RequestLimits.conversationChars)
        self.source = source
        self.createdAt = createdAt
        self.crush = crush
    }

    public func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) > KeyboardContext.lifetime
    }

    /// The last line, for a one-line preview.
    public var preview: String {
        let last = text.split(separator: "\n").last.map(String.init) ?? text
        return last.count > 80 ? String(last.prefix(77)) + "..." : last
    }
}

/// Something shared to ReplyRight from another app, waiting to be opened.
/// Screenshots in the inbox are temporary files that are deleted when the item
/// is opened, dismissed, or after `lifetime`.
public struct SharedInboxItem: Codable, Identifiable, Equatable, Sendable {
    public static let lifetime: TimeInterval = 2 * 60 * 60

    public var id: UUID
    public var createdAt: Date
    public var text: String
    public var imageFiles: [String]

    public init(id: UUID = UUID(), createdAt: Date = Date(), text: String, imageFiles: [String]) {
        self.id = id
        self.createdAt = createdAt
        self.text = text
        self.imageFiles = imageFiles
    }

    public func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(createdAt) > SharedInboxItem.lifetime
    }
}

/// The latest verified subscription transaction, kept so the keyboard and
/// share sheet can present it to the server. The server verifies it; the app
/// never asserts "I am Pro" on its own.
public struct EntitlementSnapshot: Codable, Equatable, Sendable {
    public var jws: String
    public var productID: String
    public var expiresAt: Date?
    public var updatedAt: Date

    public init(jws: String, productID: String, expiresAt: Date?, updatedAt: Date = Date()) {
        self.jws = jws
        self.productID = productID
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
    }

    public func isActive(now: Date = Date()) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > now
    }
}

/// The last usage and plan information the server reported, cached for display.
public struct ServiceSnapshot: Codable, Equatable, Sendable {
    public var usage: Usage?
    public var plans: PlanCatalog
    public var mode: GenerationMode?
    public var updatedAt: Date

    public init(usage: Usage? = nil, plans: PlanCatalog = .fallback, mode: GenerationMode? = nil, updatedAt: Date = Date()) {
        self.usage = usage
        self.plans = plans
        self.mode = mode
        self.updatedAt = updatedAt
    }
}
