import Foundation

/// The typing behaviour of the ReplyRight keyboard as a pure state machine:
/// shift and caps lock, automatic capitalisation, the double-space full stop,
/// and returning to letters after punctuation.
///
/// The keyboard extension feeds it key taps plus the text before the cursor and
/// applies the edits it returns. It never stores what is typed.
public struct TypingEngine: Equatable, Sendable {
    public enum Shift: Equatable, Sendable {
        case off
        /// Capitalises the next letter only.
        case once
        /// Caps lock.
        case locked
    }

    public enum Capitalization: Equatable, Sendable {
        case none
        case words
        case sentences
        case allCharacters
    }

    /// A change to apply to the text field.
    public enum Edit: Equatable, Sendable {
        case insert(String)
        case deleteBackward(Int)
    }

    public static let doubleTapInterval: TimeInterval = 0.35
    public static let doubleSpaceInterval: TimeInterval = 0.7

    public private(set) var shift: Shift = .off
    public private(set) var page: KeyboardPage = .letters
    public var capitalization: Capitalization
    /// Turned off for email and URL fields, where ". " would be wrong.
    public var doubleSpaceInsertsPeriod: Bool

    private var lastShiftTap: TimeInterval = -100
    private var lastSpaceTap: TimeInterval = -100

    public init(capitalization: Capitalization = .sentences, doubleSpaceInsertsPeriod: Bool = true) {
        self.capitalization = capitalization
        self.doubleSpaceInsertsPeriod = doubleSpaceInsertsPeriod
    }

    public var isUppercase: Bool { shift != .off }

    /// How a letter key should be shown and typed right now.
    public func rendered(_ character: String) -> String {
        guard page == .letters, isUppercase else { return character }
        // Single letters only: "ß" would otherwise become "SS".
        let upper = character.uppercased()
        return upper.count == character.count ? upper : character
    }

    /// Handles a key tap. `before` is the text before the cursor, `now` a monotonic timestamp.
    public mutating func tap(_ action: KeyAction, before: String?, now: TimeInterval) -> [Edit] {
        let context = before ?? ""
        var edits: [Edit] = []

        switch action {
        case .character(let value):
            guard !value.isEmpty else { return [] }
            let text = rendered(value)
            edits = [.insert(text)]
            if shift == .once { shift = .off }
            // Like the system keyboard, an apostrophe typed from the numbers page returns to letters.
            if page != .letters, value == "'" { page = .letters }
            lastSpaceTap = -100

        case .space:
            let isDouble = now - lastSpaceTap < TypingEngine.doubleSpaceInterval
            if doubleSpaceInsertsPeriod, isDouble, TypingEngine.endsWithWordThenSpace(context) {
                edits = [.deleteBackward(1), .insert(". ")]
                lastSpaceTap = -100
            } else {
                edits = [.insert(" ")]
                lastSpaceTap = now
            }
            if page != .letters { page = .letters }

        case .backspace:
            edits = [.deleteBackward(1)]
            lastSpaceTap = -100

        case .returnKey:
            edits = [.insert("\n")]
            lastSpaceTap = -100
            if page != .letters { page = .letters }

        case .shift:
            if shift == .locked {
                shift = .off
            } else if now - lastShiftTap < TypingEngine.doubleTapInterval {
                shift = .locked
            } else {
                shift = shift == .off ? .once : .off
            }
            lastShiftTap = now
            return []

        case .page(let target):
            page = target
            return []

        case .globe:
            return []
        }

        refreshShift(before: TypingEngine.apply(edits, to: context))
        return edits
    }

    /// Re-evaluates automatic capitalisation, for example after the cursor moves or text is inserted from a suggestion.
    public mutating func refreshShift(before: String?) {
        guard shift != .locked else { return }
        shift = TypingEngine.shouldCapitalize(before: before ?? "", mode: capitalization) ? .once : .off
    }

    /// Returns the keyboard to its resting state for a new field.
    public mutating func reset(before: String?) {
        page = .letters
        shift = .off
        lastShiftTap = -100
        lastSpaceTap = -100
        refreshShift(before: before)
    }

    // MARK: Rules

    public static func shouldCapitalize(before: String, mode: Capitalization) -> Bool {
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            guard let last = before.last else { return true }
            return last.isWhitespace
        case .sentences:
            guard let last = before.last else { return true }
            if last.isNewline { return true }
            guard last.isWhitespace else { return false }
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            guard let end = trimmed.last else { return true }
            return end.isNewline || ".!?…".contains(end)
        }
    }

    /// True when the text ends with a letter or digit followed by exactly one space.
    static func endsWithWordThenSpace(_ text: String) -> Bool {
        guard text.hasSuffix(" ") else { return false }
        let withoutSpace = text.dropLast()
        guard let previous = withoutSpace.last else { return false }
        return previous.isLetter || previous.isNumber || previous == ")" || previous == "\"" || previous == "'"
    }

    /// What the text before the cursor looks like after the edits.
    public static func apply(_ edits: [Edit], to text: String) -> String {
        var result = text
        for edit in edits {
            switch edit {
            case .insert(let value):
                result += value
            case .deleteBackward(let count):
                result = String(result.dropLast(count))
            }
        }
        return result
    }
}

/// The message being composed, as far as a keyboard can see it.
///
/// iOS only gives a keyboard the text near the cursor in the active field. It
/// cannot see the rest of the conversation, and ReplyRight does not pretend to.
public struct DraftContext: Equatable, Sendable {
    public let before: String
    public let after: String

    public init(before: String?, after: String?) {
        self.before = before ?? ""
        self.after = after ?? ""
    }

    public var text: String { before + after }

    public var isEmpty: Bool { text.trimmed.isEmpty }

    /// How far to move the cursor (in UTF-16 units, as `adjustTextPosition` expects) to reach the end of the draft.
    public var cursorOffsetToEnd: Int { after.utf16.count }

    /// How many backward deletions remove the whole draft once the cursor is at its end.
    public var deletionCount: Int { text.count }
}

/// Decides when the keyboard's AI features must stay off.
public enum FieldSensitivity {
    /// - Parameters:
    ///   - isSecure: The field is a secure text entry (passwords).
    ///   - contentType: The raw value of the field's `UITextContentType`, if any.
    ///   - kind: The keyboard kind requested by the field.
    public static func isSensitive(isSecure: Bool, contentType: String?, kind: KeyboardKind) -> Bool {
        if isSecure || kind.isPad { return true }
        guard let type = contentType?.lowercased(), !type.isEmpty else { return false }
        let markers = ["password", "one-time-code", "cc-", "credit-card", "creditcard", "username", "birthdate"]
        return markers.contains { type.contains($0) }
    }
}
