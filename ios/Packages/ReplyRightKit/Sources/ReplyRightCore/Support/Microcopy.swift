import Foundation

/// The small things ReplyRight says while it works. Written to sound like a
/// friend who is good at this, not like software.
public enum Microcopy {
    public static let reading = [
        "Reading between the lines…",
        "Taking it all in…",
        "Seeing what they said, and how they said it…",
        "One sec. Reading the room…",
    ]

    public static let writing = [
        "Finding words that sound like you…",
        "Okay, this is a good one…",
        "Let's not overthink it…",
        "Trying a few different angles…",
        "Adding a little personality…",
    ]

    public static let refining = [
        "Tightening it up…",
        "One more pass…",
        "Keeping what's you, fixing the rest…",
    ]

    public static let coaching = [
        "Thinking it through…",
        "Good question…",
        "Looking at this properly…",
    ]

    public static let copied = [
        "Copied. It's yours now.",
        "Copied. Send it when it feels right.",
        "Copied. You've got this.",
        "Copied. Tweak anything that isn't you.",
    ]

    /// Rotating placeholders for the custom instruction field.
    public static let instructionExamples = [
        "Confident, but not arrogant",
        "Flirty without being too obvious",
        "I want them to laugh",
        "Like something I'd actually send",
        "Don't make me sound desperate",
    ]

    public static let coachStarters = [
        "What should I say next?",
        "How can I keep this conversation going?",
        "How do I go from chatting to asking them out?",
        "Does my reply sound too eager?",
        "Can you make this less awkward?",
        "How can I show interest naturally?",
    ]

    /// Picks a line in a stable way for a given seed, so a screen does not flicker between phrases.
    public static func pick(_ lines: [String], seed: Int) -> String {
        guard !lines.isEmpty else { return "" }
        let index = ((seed % lines.count) + lines.count) % lines.count
        return lines[index]
    }

    /// A short greeting for the time of day (0 to 23).
    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Up late?"
        }
    }

    /// Describes what is left today in plain words.
    public static func allowance(remaining: Int, isPro: Bool) -> String {
        if isPro { return "Pro" }
        switch remaining {
        case ..<1: return "Back tomorrow"
        case 1: return "1 reply left today"
        default: return "\(remaining) replies left today"
        }
    }
}

/// Decides when a reply the user reworked is worth keeping as a voice example.
///
/// This only runs when the user has turned on "Learn from my edits", and the
/// result is added to My Voice where they can see and delete it.
public enum VoiceLearning {
    /// Returns the edited text when it is worth keeping, otherwise nil.
    /// Any real change counts, including casing or punctuation: those are exactly how people differ.
    public static func candidate(original: String, edited: String) -> String? {
        let text = edited.trimmed
        guard text.count >= 12, text.count <= VoiceProfile.maxSampleLength else { return nil }
        guard text != original.trimmed else { return nil }
        return text
    }
}
