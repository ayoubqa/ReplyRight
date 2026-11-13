#if canImport(UIKit)
import CoreText
import ReplyRightCore
import SwiftUI
import UIKit

// ReplyRight's design system, "Low Light".
//
// A quiet corner, late in the evening, with a friend who is good with words.
//
//   Ground     deep bottle green; blush-tinted paper in daylight
//   Voice      blush: quotation marks, messages you might send, the main action
//   Pencil     highlighter yellow: the cursor, and the one thing worth noticing
//   Type       Young Serif for the few lines that set the tone, SF for everything you use
//   Layout     one left-aligned column on the ground. Rules and space separate
//              things; only messages get bubbles and only the main action gets a fill
//
// There are no cards, gradients or glows. Colours come from `Palette` in
// ReplyRightCore, so the UIKit keyboard draws from the same tokens.

extension Color {
    /// A colour that follows the current appearance.
    public init(_ pair: ColorPair) {
        self.init(uiColor: UIColor.dynamic(pair))
    }

    public static let rrBackground = Color(Palette.background)
    public static let rrBackgroundDeep = Color(Palette.backgroundDeep)
    public static let rrSurface = Color(Palette.surface)
    public static let rrSurfaceRaised = Color(Palette.surfaceRaised)
    public static let rrSurfaceHigh = Color(Palette.surfaceHigh)
    public static let rrLine = Color(Palette.line)
    public static let rrLineStrong = Color(Palette.lineStrong)

    public static let rrText = Color(Palette.textPrimary)
    public static let rrTextSecondary = Color(Palette.textSecondary)
    public static let rrTextTertiary = Color(Palette.textTertiary)

    /// The voice: blush after dark, raspberry in daylight.
    public static let rrAccent = Color(Palette.accent)
    public static let rrAccentSoft = Color(Palette.accentSoft)
    /// The pencil, as a fill: a highlighter mark behind or beside something.
    public static let rrHighlight = Color(Palette.highlight)
    /// The pencil, as ink: readable on the ground in both appearances.
    public static let rrHighlightInk = Color(Palette.highlightInk)
    public static let rrHighlightSoft = Color(Palette.highlightSoft)
    /// The text cursor of the mark.
    public static let rrCursor = Color(Palette.cursor)
    /// Older name for `rrHighlightInk`.
    public static let rrCoral = Color(Palette.coral)
    public static let rrCoralSoft = Color(Palette.coralSoft)

    public static let rrButtonFill = Color(Palette.buttonFill)
    public static let rrButtonText = Color(Palette.buttonText)

    public static let rrBubbleMine = Color(Palette.bubbleMine)
    public static let rrBubbleMineText = Color(Palette.bubbleMineText)
    public static let rrBubbleTheirs = Color(Palette.bubbleTheirs)
    public static let rrBubbleTheirsText = Color(Palette.bubbleTheirsText)

    public static let rrSuccess = Color(Palette.success)
    public static let rrWarning = Color(Palette.warning)
    public static let rrDanger = Color(Palette.danger)

    public static let rrGlowLavender = Color(Palette.glowLavender)
    public static let rrGlowCoral = Color(Palette.glowCoral)
}

extension LinearGradient {
    /// The fill of a message the user might send. A single solid colour; kept
    /// as a gradient type so existing call sites keep working.
    public static var rrBubbleMine: LinearGradient {
        LinearGradient(colors: [Color.rrBubbleMine, Color.rrBubbleMine], startPoint: .top, endPoint: .bottom)
    }
}

/// Spacing scale, in points.
public enum RRSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 36
    public static let xxl: CGFloat = 56
    /// Standard horizontal margin for screens.
    public static let screen: CGFloat = 22
}

/// Corner radii. Shape follows meaning: bubbles are for messages, pills for
/// actions, and the soft rectangle for the few surfaces you write on.
public enum RRRadius {
    public static let small: CGFloat = 10
    public static let control: CGFloat = 16
    public static let bubble: CGFloat = 22
    public static let card: CGFloat = 20
}

/// Motion: quick springs for touch, slower ones for content arriving.
extension Animation {
    public static var rrSnappy: Animation { .spring(response: 0.28, dampingFraction: 0.82) }
    public static var rrGentle: Animation { .spring(response: 0.5, dampingFraction: 0.88) }
}

// MARK: - Typefaces

/// The display typeface, Young Serif, ships inside this package and is
/// registered the first time it is needed. If registration ever fails the
/// system serif is used instead, so nothing depends on it being there.
public enum RRFonts {
    public static let displayFontName = "YoungSerif-Regular"

    /// True once the display face is available to SwiftUI and UIKit.
    public static let hasDisplayFace: Bool = {
        if UIFont(name: displayFontName, size: 12) != nil {
            return true
        }
        guard let url = Bundle.module.url(forResource: displayFontName, withExtension: "ttf") else {
            return false
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return UIFont(name: displayFontName, size: 12) != nil
    }()

    /// The display face at an exact size. Callers scale the size for Dynamic Type.
    public static func display(size: CGFloat) -> Font {
        hasDisplayFace
            ? Font.custom(displayFontName, fixedSize: size)
            : Font.system(size: size, weight: .semibold, design: .serif)
    }

    /// The display face for UIKit views such as the keyboard.
    public static func displayUIFont(size: CGFloat) -> UIFont {
        if hasDisplayFace, let font = UIFont(name: displayFontName, size: size) {
            return font
        }
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        if let descriptor = base.fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}

// MARK: - Typography

public enum RRTextStyle {
    /// The largest display line, for a screen's one big sentence.
    case hero
    case display
    case title
    case titleSmall
    /// A row in a list of things you can do, set in the display face like a line on a menu.
    case menu
    case headline
    case bodyLarge
    case body
    /// Text inside a message bubble.
    case message
    case callout
    case footnote
    case caption
    /// A quiet label above a group. Sentence case, never capitals.
    case eyebrow
    /// The reason behind a suggestion.
    case note

    var size: CGFloat {
        switch self {
        case .hero: return 37
        case .display: return 30
        case .title: return 25
        case .titleSmall: return 20
        case .menu: return 21
        case .headline: return 17
        case .bodyLarge: return 18
        case .body: return 16
        case .message: return 17
        case .callout: return 15
        case .footnote: return 13
        case .caption: return 12
        case .eyebrow: return 13
        case .note: return 15
        }
    }

    var weight: Font.Weight {
        switch self {
        case .headline: return .semibold
        case .eyebrow: return .medium
        default: return .regular
        }
    }

    /// True for the styles set in the display face.
    var isDisplay: Bool {
        switch self {
        case .hero, .display, .title, .titleSmall, .menu: return true
        default: return false
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .hero, .display: return .largeTitle
        case .title: return .title
        case .titleSmall, .menu: return .title3
        case .headline: return .headline
        case .bodyLarge, .body, .message: return .body
        case .callout, .note: return .callout
        case .footnote, .eyebrow: return .footnote
        case .caption: return .caption
        }
    }

    var tracking: CGFloat {
        switch self {
        case .hero: return -0.6
        case .display: return -0.4
        case .title: return -0.2
        default: return 0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .hero, .display, .title, .titleSmall, .menu: return 1
        case .eyebrow, .caption: return 1
        default: return 3.5
        }
    }
}

struct RRTextModifier: ViewModifier {
    private let style: RRTextStyle
    @ScaledMetric private var size: CGFloat

    init(style: RRTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }

    private var font: Font {
        style.isDisplay
            ? RRFonts.display(size: size)
            : Font.system(size: size, weight: style.weight, design: .default)
    }
}

extension View {
    /// Applies a ReplyRight text style. Sizes scale with Dynamic Type.
    public func rrText(_ style: RRTextStyle) -> some View {
        modifier(RRTextModifier(style: style))
    }
}

/// A screen's headline in the display face.
///
/// The three parts are joined and set as one even line. Nothing is picked out
/// in another colour: the typeface carries the emphasis.
public struct EditorialTitle: View {
    private let text: String
    private let style: RRTextStyle

    public init(_ lead: String, emphasis: String, trail: String = "", style: RRTextStyle = .display) {
        self.text = lead + emphasis + trail
        self.style = style
    }

    public init(_ text: String, style: RRTextStyle = .display) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .rrText(style)
            .foregroundStyle(Color.rrText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A quiet label above a group of related things.
public struct Eyebrow: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .rrText(.eyebrow)
            .foregroundStyle(Color.rrTextSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A hairline that separates one thing from the next.
public struct Rule: View {
    private let strong: Bool

    public init(strong: Bool = false) {
        self.strong = strong
    }

    public var body: some View {
        Rectangle()
            .fill(strong ? Color.rrLineStrong : Color.rrLine)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
#endif
