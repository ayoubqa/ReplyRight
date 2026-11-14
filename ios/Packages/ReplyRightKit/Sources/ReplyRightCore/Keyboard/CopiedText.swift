import Foundation

/// Decides whether copied text can be offered as "what they said" when the
/// user taps Reply in the keyboard.
///
/// The keyboard reads the clipboard only after that tap, shows the text back
/// before anything is sent, and keeps it in memory only. This check stops it
/// from offering things that are clearly not a chat message, such as a copied
/// password, a one-time code, a card number or a link. The explicit "Use copied
/// message" button still works for anything, because then the user chose it.
public enum CopiedText {
    public static func looksLikeMessage(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard text.contains(where: { $0.isLetter || $0.isEmoji }) else { return false }

        let lower = text.lowercased()
        if lower.contains("://") || lower.hasPrefix("www.") { return false }

        // One unbroken token with a digit or symbol in it reads like a password
        // or a code, not like something someone texted.
        if !text.contains(where: \.isWhitespace) {
            let looksLikeCode = text.contains { character in
                character.isNumber || !(character.isLetter || character.isEmoji || character.isMessagePunctuation)
            }
            if looksLikeCode { return false }
        }

        // Long runs of digits, even with spaces or dashes between them: card
        // numbers, phone numbers, codes.
        var run = 0
        for character in text {
            if character.isNumber {
                run += 1
                if run >= 6 { return false }
            } else if character != " " && character != "-" {
                run = 0
            }
        }
        return true
    }
}

private extension Character {
    /// Punctuation that ordinary one-word messages use ("ok!", "really?", "don't").
    var isMessagePunctuation: Bool {
        ".,!?'\u{2019}\u{2026}".contains(self)
    }

    /// A picture emoji such as 😂, not a digit or "#" that can also be drawn as one.
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (unicodeScalars.count > 1 && first.properties.isEmoji)
    }
}
