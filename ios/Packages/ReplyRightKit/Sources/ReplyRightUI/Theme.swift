#if canImport(UIKit)
import ReplyRightCore
import SwiftUI
import UIKit

// ReplyRight's design system, "After Hours".
//
// The app is set in the evening, when most of this texting happens: deep ink
// and midnight plum, warm ivory type, a quiet lavender and a muted coral used
// sparingly for emphasis. Display type is the system serif (New York) for an
// editorial feel; everything functional is SF Pro.
//
// Colours come from `Palette` in ReplyRightCore, so the UIKit keyboard draws
// from the same tokens.

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

    public static let rrAccent = Color(Palette.accent)
    public static let rrAccentSoft = Color(Palette.accentSoft)
    public static let rrCoral = Color(Palette.coral)
    public static let rrCoralSoft = Color(Palette.coralSoft)

    public static let rrButtonFill = Color(Palette.buttonFill)
    public static let rrButtonText = Color(Palette.buttonText)

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
    /// The fill of a message the user might send.
    public static var rrBubbleMine: LinearGradient {
        LinearGradient(
            colors: [Color(Palette.bubbleMineStart), Color(Palette.bubbleMineEnd)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Spacing scale, in points.
public enum RRSpace {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 24
    public static let xl: CGFloat = 32
    public static let xxl: CGFloat = 48
    /// Standard horizontal margin for screens.
    public static let screen: CGFloat = 20
}

public enum RRRadius {
    public static let small: CGFloat = 12
    public static let control: CGFloat = 18
    public static let bubble: CGFloat = 22
    public static let card: CGFloat = 26
}

/// Motion: quick springs for touch, slower ones for content arriving.
extension Animation {
    public static var rrSnappy: Animation { .spring(response: 0.3, dampingFraction: 0.8) }
    public static var rrGentle: Animation { .spring(response: 0.5, dampingFraction: 0.86) }
}

// MARK: - Typography

public enum RRTextStyle {
    /// The largest serif, for a screen's one big line.
    case hero
    case display
    case title
    case titleSmall
    case headline
    case bodyLarge
    case body
    /// Text inside a message bubble.
    case message
    case callout
    case footnote
    case caption
    /// Small tracked capitals above a section.
    case eyebrow
    /// Serif italic, used for the "why it works" margin notes.
    case note

    var size: CGFloat {
        switch self {
        case .hero: return 40
        case .display: return 32
        case .title: return 26
        case .titleSmall: return 21
        case .headline: return 17
        case .bodyLarge: return 18
        case .body: return 16
        case .message: return 17
        case .callout: return 15
        case .footnote: return 13
        case .caption: return 12
        case .eyebrow: return 11
        case .note: return 15
        }
    }

    var weight: Font.Weight {
        switch self {
        case .headline: return .semibold
        case .eyebrow: return .semibold
        default: return .regular
        }
    }

    var design: Font.Design {
        switch self {
        case .hero, .display, .title, .titleSmall, .note: return .serif
        default: return .default
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .hero, .display: return .largeTitle
        case .title: return .title
        case .titleSmall: return .title3
        case .headline: return .headline
        case .bodyLarge, .body, .message: return .body
        case .callout, .note: return .callout
        case .footnote: return .footnote
        case .caption, .eyebrow: return .caption
        }
    }

    var tracking: CGFloat {
        switch self {
        case .hero: return -0.8
        case .display: return -0.5
        case .title: return -0.3
        case .eyebrow: return 1.6
        default: return 0
        }
    }

    var lineSpacing: CGFloat {
        switch self {
        case .hero, .display, .title, .titleSmall: return 0
        case .eyebrow, .caption: return 1
        default: return 3
        }
    }

    var isItalic: Bool { self == .note }
    var isUppercase: Bool { self == .eyebrow }
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
            .textCase(style.isUppercase ? .uppercase : nil)
            .lineSpacing(style.lineSpacing)
    }

    private var font: Font {
        let base = Font.system(size: size, weight: style.weight, design: style.design)
        return style.isItalic ? base.italic() : base
    }
}

extension View {
    /// Applies a ReplyRight text style. Sizes scale with Dynamic Type.
    public func rrText(_ style: RRTextStyle) -> some View {
        modifier(RRTextModifier(style: style))
    }
}

/// A serif headline with one phrase set in coral italics, the way a magazine
/// would stress a word: "What's happening with *your crush?*"
public struct EditorialTitle: View {
    private let lead: String
    private let emphasis: String
    private let trail: String
    private let style: RRTextStyle

    public init(_ lead: String, emphasis: String, trail: String = "", style: RRTextStyle = .display) {
        self.lead = lead
        self.emphasis = emphasis
        self.trail = trail
        self.style = style
    }

    public var body: some View {
        Text(attributed)
            .rrText(style)
            .foregroundStyle(Color.rrText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var attributed: AttributedString {
        var result = AttributedString(lead)
        var stressed = AttributedString(emphasis)
        stressed.inlinePresentationIntent = .emphasized
        stressed.swiftUI.foregroundColor = Color.rrCoral
        result.append(stressed)
        result.append(AttributedString(trail))
        return result
    }
}

/// Small tracked capitals that label a section, with a short coral rule.
public struct Eyebrow: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        HStack(spacing: RRSpace.xs) {
            Capsule()
                .fill(Color.rrCoral)
                .frame(width: 14, height: 2)
            Text(title)
                .rrText(.eyebrow)
                .foregroundStyle(Color.rrTextSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
#endif
