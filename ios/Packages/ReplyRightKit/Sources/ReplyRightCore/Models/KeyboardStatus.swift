import Foundation

// Whether the ReplyRight keyboard is set up, as far as the app can honestly tell.
//
// iOS gives an app no way to ask whether its keyboard is switched on, or
// whether Full Access is allowed. The app learns it from three things only:
//
//   1. The user saying they switched it on in Settings (self-reported).
//   2. The keyboard's check-in: a small record the keyboard writes to the
//      shared App Group container when it opens. A keyboard can write there
//      only with Full Access, so a check-in proves both.
//   3. The test phrase: the keyboard types a fixed sentence into ReplyRight's
//      own test field (`KeyboardHandshake`). This works without Full Access,
//      so it is the only way to see a keyboard that is on but limited.
//
// None of these is continuous. The status is the most recent evidence, with
// its date, never a live reading.

/// Written by the keyboard extension each time it opens with Full Access.
public struct KeyboardCheckIn: Codable, Equatable, Sendable {
    /// When the keyboard last opened with Full Access.
    public var lastSeen: Date
    public var hasFullAccess: Bool
    /// The keyboard's version, to spot an app and keyboard out of step.
    public var keyboardVersion: String

    public init(lastSeen: Date = Date(), hasFullAccess: Bool, keyboardVersion: String) {
        self.lastSeen = lastSeen
        self.hasFullAccess = hasFullAccess
        self.keyboardVersion = keyboardVersion
    }
}

/// What the app remembers about keyboard setup on its own side.
public struct KeyboardSetupRecord: Codable, Equatable, Sendable {
    /// The user said they switched ReplyRight on in Settings. Not verified.
    public var userConfirmedEnabledAt: Date?
    /// The keyboard typed its test phrase into ReplyRight's test field.
    public var lastTestAt: Date?
    /// Whether the keyboard reported Full Access in that test.
    public var lastTestHadFullAccess: Bool?
    /// The Home card was put away with "Not now". It comes back a week later.
    public var homeCardSnoozedAt: Date?

    public init(
        userConfirmedEnabledAt: Date? = nil,
        lastTestAt: Date? = nil,
        lastTestHadFullAccess: Bool? = nil,
        homeCardSnoozedAt: Date? = nil
    ) {
        self.userConfirmedEnabledAt = userConfirmedEnabledAt
        self.lastTestAt = lastTestAt
        self.lastTestHadFullAccess = lastTestHadFullAccess
        self.homeCardSnoozedAt = homeCardSnoozedAt
    }

    // Tolerant decoding so fields can be added later without losing the record.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userConfirmedEnabledAt = try? c.decodeIfPresent(Date.self, forKey: .userConfirmedEnabledAt)
        lastTestAt = try? c.decodeIfPresent(Date.self, forKey: .lastTestAt)
        lastTestHadFullAccess = try? c.decodeIfPresent(Bool.self, forKey: .lastTestHadFullAccess)
        homeCardSnoozedAt = try? c.decodeIfPresent(Date.self, forKey: .homeCardSnoozedAt)
    }

    /// Whether the Home card is currently put away.
    public func isHomeCardSnoozed(now: Date = Date()) -> Bool {
        guard let snoozed = homeCardSnoozedAt else { return false }
        return now.timeIntervalSince(snoozed) < 7 * 24 * 60 * 60
    }
}

/// The keyboard's setup state, from the most recent evidence.
public enum KeyboardSetupStatus: Equatable, Sendable {
    /// Nothing suggests the keyboard has been switched on.
    case notSetUp
    /// The user said they switched it on, but the keyboard has not shown up yet.
    case enabledNotTested(confirmedAt: Date)
    /// The keyboard typed its test phrase without Full Access: typing works,
    /// suggestions cannot.
    case limitedAccess(testedAt: Date)
    /// The keyboard confirmed itself with Full Access on this date.
    case ready(lastConfirmed: Date)

    /// The most recent evidence wins. A later test without Full Access
    /// overrides an older check-in, so switching Full Access off and testing
    /// again shows up.
    public static func derive(checkIn: KeyboardCheckIn?, record: KeyboardSetupRecord) -> KeyboardSetupStatus {
        var evidence: [(date: Date, fullAccess: Bool)] = []
        if let checkIn, checkIn.hasFullAccess {
            evidence.append((checkIn.lastSeen, true))
        }
        if let tested = record.lastTestAt, let fullAccess = record.lastTestHadFullAccess {
            evidence.append((tested, fullAccess))
        }
        if let latest = evidence.max(by: { $0.date < $1.date }) {
            return latest.fullAccess ? .ready(lastConfirmed: latest.date) : .limitedAccess(testedAt: latest.date)
        }
        if let confirmed = record.userConfirmedEnabledAt {
            return .enabledNotTested(confirmedAt: confirmed)
        }
        return .notSetUp
    }

    /// True when Reply and Rewrite are known to have worked.
    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The date the status rests on, when there is one.
    public var evidenceDate: Date? {
        switch self {
        case .notSetUp: return nil
        case .enabledNotTested(let date), .limitedAccess(let date), .ready(let date): return date
        }
    }

    /// A short label for the status, as the app shows it.
    public var title: String {
        switch self {
        case .notSetUp: return "Not set up"
        case .enabledNotTested: return "Turned on, not tested yet"
        case .limitedAccess: return "Typing only"
        case .ready: return "Ready"
        }
    }

    /// One plain sentence on what the status means and what to do next.
    public var explanation: String {
        switch self {
        case .notSetUp:
            return "Add the ReplyRight keyboard in Settings to get replies inside your chats."
        case .enabledNotTested:
            return "You said it's switched on. Test it once here to finish setup."
        case .limitedAccess:
            return "The keyboard works for typing, but Full Access is off, so it can't write replies yet."
        case .ready:
            return "Reply and Rewrite are ready in your chats."
        }
    }
}
