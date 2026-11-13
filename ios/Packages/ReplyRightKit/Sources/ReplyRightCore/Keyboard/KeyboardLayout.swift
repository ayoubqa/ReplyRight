import Foundation

// Keyboard layouts as plain data. The keyboard extension renders these with
// UIKit; keeping them here means they can be unit-tested without a device.

public enum KeyboardPage: Equatable, Hashable, Sendable {
    case letters
    case numbers
    case symbols
}

/// The kind of field being typed into, reduced to what changes the layout.
public enum KeyboardKind: Equatable, Hashable, Sendable {
    case standard
    case email
    case url
    case webSearch
    case twitter
    case numberPad
    case decimalPad
    case phonePad

    public var isPad: Bool {
        switch self {
        case .numberPad, .decimalPad, .phonePad: return true
        default: return false
        }
    }
}

public enum KeyboardLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        }
    }

    public var spaceLabel: String {
        switch self {
        case .english: return "space"
        case .spanish: return "espacio"
        }
    }

    /// Two letters for the language switch on the keyboard's toolbar.
    public var shortCode: String { rawValue.uppercased() }

    /// The language after this one, so a single switch can cycle through all of them.
    /// Adding a language is a new case here plus its layout in `KeyboardLayout`.
    public var next: KeyboardLanguage {
        let all = KeyboardLanguage.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    /// Picks the keyboard language from the user's reply languages.
    public static func preferred(for voice: VoiceProfile) -> KeyboardLanguage {
        if voice.replyLanguage == "es" { return .spanish }
        if voice.replyLanguage == "match", voice.languages.first == "es" { return .spanish }
        return .english
    }
}

public enum KeyAction: Equatable, Hashable, Sendable {
    case character(String)
    case shift
    case backspace
    case space
    case returnKey
    case globe
    case page(KeyboardPage)
}

public struct KeyboardKey: Equatable, Hashable, Sendable {
    public let action: KeyAction
    public let label: String
    /// Width in units, where a letter key is 1. Ignored for flexible keys.
    public let width: Double
    /// Takes whatever width is left in its row (the space bar).
    public let isFlexible: Bool
    /// Characters offered on a long press, such as accented letters.
    public let alternates: [String]

    public init(action: KeyAction, label: String, width: Double = 1, isFlexible: Bool = false, alternates: [String] = []) {
        self.action = action
        self.label = label
        self.width = width
        self.isFlexible = isFlexible
        self.alternates = alternates
    }

    /// Keys that act rather than type. Drawn in the secondary key style.
    public var isFunction: Bool {
        switch action {
        case .character, .space: return false
        default: return true
        }
    }

    static func character(_ value: String, width: Double = 1) -> KeyboardKey {
        KeyboardKey(action: .character(value), label: value, width: width, alternates: KeyboardLayout.alternates[value] ?? [])
    }
}

public struct KeyboardLayout: Equatable, Sendable {
    public let rows: [[KeyboardKey]]
    /// How many units wide the widest row is. KeyboardKey size is derived from this.
    public let unitsPerRow: Double

    public init(rows: [[KeyboardKey]], unitsPerRow: Double) {
        self.rows = rows
        self.unitsPerRow = unitsPerRow
    }

    /// Long-press alternatives, keyed by the lowercase base character.
    public static let alternates: [String: [String]] = [
        "a": ["á", "à", "â", "ä", "ã", "å", "æ"],
        "e": ["é", "è", "ê", "ë"],
        "i": ["í", "ì", "î", "ï"],
        "o": ["ó", "ò", "ô", "ö", "õ", "ø", "œ"],
        "u": ["ú", "ü", "ù", "û"],
        "n": ["ñ"],
        "c": ["ç"],
        "s": ["ß"],
        "y": ["ÿ"],
        "?": ["¿"],
        "!": ["¡"],
        "$": ["€", "£", "¥"],
        "'": ["’", "‘"],
        "\"": ["”", "“", "«", "»"],
        "-": ["–", "—"],
        ".": ["…"],
        "0": ["°"],
    ]

    // MARK: Building layouts

    public static func make(
        page: KeyboardPage,
        kind: KeyboardKind,
        language: KeyboardLanguage,
        showsGlobe: Bool
    ) -> KeyboardLayout {
        if kind.isPad {
            return pad(kind: kind)
        }
        var rows: [[KeyboardKey]]
        switch page {
        case .letters:
            rows = letterRows(language: language)
        case .numbers:
            rows = numberRows()
        case .symbols:
            rows = symbolRows()
        }
        rows.append(bottomRow(page: page, kind: kind, language: language, showsGlobe: showsGlobe))
        return KeyboardLayout(rows: rows, unitsPerRow: 10)
    }

    private static func characters(_ string: String) -> [KeyboardKey] {
        string.map { KeyboardKey.character(String($0)) }
    }

    private static func letterRows(language: KeyboardLanguage) -> [[KeyboardKey]] {
        let top = characters("qwertyuiop")
        let middle = characters(language == .spanish ? "asdfghjklñ" : "asdfghjkl")
        let bottom = [KeyboardKey(action: .shift, label: "shift", width: 1.5)]
            + characters("zxcvbnm")
            + [KeyboardKey(action: .backspace, label: "delete", width: 1.5)]
        return [top, middle, bottom]
    }

    private static func numberRows() -> [[KeyboardKey]] {
        let top = characters("1234567890")
        let middle = characters("-/:;()$&@\"")
        let bottom = [KeyboardKey(action: .page(.symbols), label: "#+=", width: 1.5)]
            + [".", ",", "?", "!", "'"].map { KeyboardKey.character($0, width: 1.4) }
            + [KeyboardKey(action: .backspace, label: "delete", width: 1.5)]
        return [top, middle, bottom]
    }

    private static func symbolRows() -> [[KeyboardKey]] {
        let top = characters("[]{}#%^*+=")
        let middle = characters("_\\|~<>€£¥•")
        let bottom = [KeyboardKey(action: .page(.numbers), label: "123", width: 1.5)]
            + [".", ",", "?", "!", "'"].map { KeyboardKey.character($0, width: 1.4) }
            + [KeyboardKey(action: .backspace, label: "delete", width: 1.5)]
        return [top, middle, bottom]
    }

    private static func bottomRow(
        page: KeyboardPage,
        kind: KeyboardKind,
        language: KeyboardLanguage,
        showsGlobe: Bool
    ) -> [KeyboardKey] {
        var row: [KeyboardKey] = []
        let pageKey = page == .letters
            ? KeyboardKey(action: .page(.numbers), label: "123", width: showsGlobe ? 1.25 : 2.5)
            : KeyboardKey(action: .page(.letters), label: "ABC", width: showsGlobe ? 1.25 : 2.5)
        row.append(pageKey)
        if showsGlobe {
            row.append(KeyboardKey(action: .globe, label: "globe", width: 1.25))
        }

        // Extra keys that the field type makes useful, as the system keyboard does.
        var extras: [KeyboardKey] = []
        if page == .letters {
            switch kind {
            case .email:
                extras = [KeyboardKey.character("@"), KeyboardKey.character(".")]
            case .url:
                extras = [KeyboardKey.character("."), KeyboardKey.character("/")]
            case .twitter:
                extras = [KeyboardKey.character("@"), KeyboardKey.character("#")]
            default:
                extras = []
            }
        }

        if kind == .url, page == .letters {
            // URLs have no spaces, so the space bar gives way to the extras.
            row.append(contentsOf: extras)
            row.append(KeyboardKey(action: .character(".com"), label: ".com", width: 2, isFlexible: true))
        } else {
            if let first = extras.first { row.append(first) }
            row.append(KeyboardKey(action: .space, label: language.spaceLabel, width: 5, isFlexible: true))
            if extras.count > 1 { row.append(extras[1]) }
        }
        row.append(KeyboardKey(action: .returnKey, label: "return", width: 2.5))
        return row
    }

    private static func pad(kind: KeyboardKind) -> KeyboardLayout {
        func digit(_ value: String) -> KeyboardKey { KeyboardKey(action: .character(value), label: value, width: 1) }
        let corner: KeyboardKey
        switch kind {
        case .decimalPad:
            corner = digit(".")
        case .phonePad:
            corner = KeyboardKey(action: .character("+"), label: "+", width: 1, alternates: ["*", "#"])
        default:
            // An inert spacer keeps the grid aligned on a plain number pad.
            corner = KeyboardKey(action: .character(""), label: "", width: 1)
        }
        let rows: [[KeyboardKey]] = [
            [digit("1"), digit("2"), digit("3")],
            [digit("4"), digit("5"), digit("6")],
            [digit("7"), digit("8"), digit("9")],
            [corner, digit("0"), KeyboardKey(action: .backspace, label: "delete", width: 1)],
        ]
        return KeyboardLayout(rows: rows, unitsPerRow: 3)
    }
}
