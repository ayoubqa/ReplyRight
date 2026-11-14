import Foundation

/// The test sentence the ReplyRight keyboard types into ReplyRight's own test
/// field, so the app can see that the keyboard really works.
///
/// It is the only public way for the app to hear from a keyboard that has no
/// Full Access: such a keyboard cannot write to the shared container, but it
/// can always type. The keyboard types the sentence only when the user taps
/// "Type a test message" in its status panel, and it says whether Full Access
/// is on. Nothing else is sent anywhere.
public enum KeyboardHandshake {
    /// The fixed part of the sentence. Brand words, so it is not translated.
    public static let marker = "ReplyRight Keyboard \u{2713}"

    /// What the keyboard types.
    public static func phrase(hasFullAccess: Bool) -> String {
        hasFullAccess ? "\(marker) Full Access on" : "\(marker) Full Access off"
    }

    public struct Result: Equatable, Sendable {
        public let hasFullAccess: Bool

        public init(hasFullAccess: Bool) {
            self.hasFullAccess = hasFullAccess
        }
    }

    /// Finds the most recent test sentence in a field's text, if there is one.
    public static func detect(in text: String) -> Result? {
        guard let range = text.range(of: marker, options: .backwards) else { return nil }
        let rest = text[range.upperBound...].lowercased()
        if rest.hasPrefix(" full access on") { return Result(hasFullAccess: true) }
        if rest.hasPrefix(" full access off") { return Result(hasFullAccess: false) }
        return nil
    }
}
