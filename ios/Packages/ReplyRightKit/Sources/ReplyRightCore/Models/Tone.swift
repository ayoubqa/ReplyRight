import Foundation

/// The user's default vibe when texting someone they like.
public enum Tone: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case playful
    case flirty
    case confident
    case charming
    case subtle
    case warm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .playful: return "Playful"
        case .flirty: return "Flirty"
        case .confident: return "Confident"
        case .charming: return "Charming"
        case .subtle: return "Low-key"
        case .warm: return "Warm"
        }
    }

    public var blurb: String {
        switch self {
        case .playful: return "Light, teasing, fun"
        case .flirty: return "Openly interested"
        case .confident: return "Direct and relaxed"
        case .charming: return "Thoughtful, attentive"
        case .subtle: return "Understated, no pressure"
        case .warm: return "Kind and sincere"
        }
    }
}

/// A change the user can ask for on a single message.
///
/// Raw values are part of the API contract (`REFINE_ACTIONS` in the backend).
public enum RefineAction: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case shorter
    case funnier
    case moreRomantic = "more_romantic"
    case moreConfident = "more_confident"
    case lessIntense = "less_intense"
    case moreNatural = "more_natural"
    case moreLikeMe = "more_like_me"
    case flirty
    case playful
    case charming
    case subtle
    case warm
    case moreDirect = "more_direct"
    case askQuestion = "ask_question"
    case keepGoing = "keep_going"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .shorter: return "Shorter"
        case .funnier: return "Funnier"
        case .moreRomantic: return "More romantic"
        case .moreConfident: return "More confident"
        case .lessIntense: return "Less intense"
        case .moreNatural: return "More natural"
        case .moreLikeMe: return "More like me"
        case .flirty: return "Flirty"
        case .playful: return "Playful"
        case .charming: return "Charming"
        case .subtle: return "Low-key"
        case .warm: return "Warm"
        case .moreDirect: return "More direct"
        case .askQuestion: return "Ask a question"
        case .keepGoing: return "Keep it going"
        }
    }

    /// The label on a tweak control, phrased as a change to the reply.
    public var tweakTitle: String {
        switch self {
        case .playful: return "More playful"
        case .flirty: return "Flirtier"
        case .charming: return "More charming"
        case .warm: return "Warmer"
        case .subtle: return "More low-key"
        default: return title
        }
    }

    public var symbol: String {
        switch self {
        case .shorter: return "scissors"
        case .funnier: return "face.smiling"
        case .moreRomantic: return "heart"
        case .moreConfident: return "bolt"
        case .lessIntense: return "wind"
        case .moreNatural: return "leaf"
        case .moreLikeMe: return "person.wave.2"
        case .flirty: return "flame"
        case .playful: return "gamecontroller"
        case .charming: return "hand.wave"
        case .subtle: return "moon"
        case .warm: return "sun.max"
        case .moreDirect: return "arrow.right"
        case .askQuestion: return "questionmark"
        case .keepGoing: return "arrow.turn.down.right"
        }
    }

    /// Tweaks offered on a reply, in the order they are shown.
    public static let cardActions: [RefineAction] = [
        .moreNatural, .playful, .moreConfident, .moreRomantic, .lessIntense, .shorter, .moreDirect, .askQuestion, .keepGoing,
        .moreLikeMe,
    ]

    /// The handful of tweaks that fit in the keyboard.
    public static let keyboardActions: [RefineAction] = [
        .moreNatural, .playful, .moreConfident, .lessIntense, .shorter, .moreDirect,
    ]

    /// Tone rewrites offered for a draft (keyboard, draft polish).
    public static let toneActions: [RefineAction] = [
        .moreNatural, .flirty, .playful, .moreConfident, .charming, .subtle, .warm,
    ]

    public init(tone: Tone) {
        switch tone {
        case .playful: self = .playful
        case .flirty: self = .flirty
        case .confident: self = .moreConfident
        case .charming: self = .charming
        case .subtle: self = .subtle
        case .warm: self = .warm
        }
    }
}
