import Foundation

/// What the user wants their message to achieve.
///
/// Raw values are part of the API contract (`backend/src/lib/domain/intents.ts`).
public enum Intent: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case natural
    case flirt
    case laugh
    case interest
    case confident
    case keepGoing = "keep_going"
    case mysterious
    case charming
    case askOut = "ask_out"
    case dryReply = "dry_reply"
    case feelings
    case boundary

    public var id: String { rawValue }

    /// Full label, phrased as the user's goal.
    public var title: String {
        switch self {
        case .natural: return "Just help me reply"
        case .flirt: return "Flirt naturally"
        case .laugh: return "Make them laugh"
        case .interest: return "Show interest"
        case .confident: return "Sound confident"
        case .keepGoing: return "Keep it going"
        case .mysterious: return "Be a little mysterious"
        case .charming: return "Be charming"
        case .askOut: return "Move towards a date"
        case .dryReply: return "Answer a dry message"
        case .feelings: return "Say how I feel"
        case .boundary: return "Set a boundary"
        }
    }

    /// One or two words, for tight spaces such as the keyboard.
    public var shortTitle: String {
        switch self {
        case .natural: return "Natural"
        case .flirt: return "Flirty"
        case .laugh: return "Funny"
        case .interest: return "Interested"
        case .confident: return "Confident"
        case .keepGoing: return "Keep going"
        case .mysterious: return "Mysterious"
        case .charming: return "Charming"
        case .askOut: return "Ask out"
        case .dryReply: return "Dry reply"
        case .feelings: return "Feelings"
        case .boundary: return "Boundary"
        }
    }

    /// A short line shown under the title.
    public var blurb: String {
        switch self {
        case .natural: return "No agenda. Just sound like you."
        case .flirt: return "Warm, a little bold, never a line."
        case .laugh: return "A real smile, not a forced joke."
        case .interest: return "Curious about them, not interrogating."
        case .confident: return "Calm and direct. No over-explaining."
        case .keepGoing: return "Give them something easy to answer."
        case .mysterious: return "Leave a little unsaid."
        case .charming: return "Attentive, with a light touch."
        case .askOut: return "From chatting to actually meeting."
        case .dryReply: return "Bring the energy back without chasing."
        case .feelings: return "Honest and simple. No pressure."
        case .boundary: return "Clear, kind and firm."
        }
    }

    /// SF Symbol name.
    public var symbol: String {
        switch self {
        case .natural: return "text.bubble"
        case .flirt: return "sparkles"
        case .laugh: return "face.smiling"
        case .interest: return "eyes"
        case .confident: return "bolt"
        case .keepGoing: return "ellipsis.bubble"
        case .mysterious: return "moon.stars"
        case .charming: return "wand.and.stars"
        case .askOut: return "calendar.badge.plus"
        case .dryReply: return "flame"
        case .feelings: return "heart.text.square"
        case .boundary: return "hand.raised"
        }
    }

    /// The order intents appear in the selector.
    public static let selectorOrder: [Intent] = [
        .natural, .flirt, .laugh, .interest, .keepGoing, .confident,
        .charming, .mysterious, .dryReply, .askOut, .feelings, .boundary,
    ]

    /// Quick choices offered in the keyboard and the share sheet.
    public static let quickChoices: [Intent] = [.natural, .flirt, .laugh, .confident, .charming, .keepGoing]
}
