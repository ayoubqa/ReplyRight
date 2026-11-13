import Foundation

// Design tokens for ReplyRight's "Low Light" identity.
//
// The app is set where this kind of texting happens: a quiet corner, late.
// The ground is a deep bottle green. Type is a warm bone white. Blush is the
// voice (quotation marks, messages you might send, the one main action on a
// screen). Highlighter yellow is the pencil: the cursor, and the single thing
// on a screen worth noticing. In daylight the ground turns to blush-tinted
// paper, the ink to bottle green, and blush deepens to raspberry.
//
// There are no gradients and no glows. Tokens are plain numbers so SwiftUI
// (the app and share sheet) and UIKit (the keyboard) draw from one palette.

public struct RGBA: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a colour from a hex value such as `0xF6F1E7`.
    public init(_ hex: UInt32, alpha: Double = 1) {
        self.red = Double((hex >> 16) & 0xFF) / 255
        self.green = Double((hex >> 8) & 0xFF) / 255
        self.blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public func opacity(_ value: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha * value)
    }
}

/// One colour in both appearances. "Evening" (dark) is the default look.
public struct ColorPair: Equatable, Hashable, Sendable {
    public let dark: RGBA
    public let light: RGBA

    public init(dark: RGBA, light: RGBA) {
        self.dark = dark
        self.light = light
    }

    public init(dark: UInt32, light: UInt32) {
        self.dark = RGBA(dark)
        self.light = RGBA(light)
    }

    public func opacity(_ value: Double) -> ColorPair {
        ColorPair(dark: dark.opacity(value), light: light.opacity(value))
    }
}

public enum Palette {
    private static let bone: UInt32 = 0xF4EEE6
    private static let bottle: UInt32 = 0x0F231D
    private static let ink: UInt32 = 0x12322A
    private static let blush: UInt32 = 0xFFA79D
    private static let raspberry: UInt32 = 0xC2335A
    private static let highlighter: UInt32 = 0xF3DC5F

    // Grounds and surfaces
    public static let background = ColorPair(dark: bottle, light: 0xFBF1EC)
    public static let backgroundDeep = ColorPair(dark: 0x0A1814, light: 0xF3E4DD)
    /// A writing surface or a sheet. Used sparingly; most content sits straight on the ground.
    public static let surface = ColorPair(dark: 0x152C25, light: 0xFFF9F6)
    public static let surfaceRaised = ColorPair(dark: 0x1C372F, light: 0xF6E7E0)
    public static let surfaceHigh = ColorPair(dark: 0x25443A, light: 0xEDD9D0)
    public static let line = ColorPair(dark: RGBA(bone, alpha: 0.11), light: RGBA(ink, alpha: 0.11))
    public static let lineStrong = ColorPair(dark: RGBA(bone, alpha: 0.24), light: RGBA(ink, alpha: 0.24))

    // Text
    public static let textPrimary = ColorPair(dark: bone, light: ink)
    public static let textSecondary = ColorPair(dark: 0xA9BDB3, light: 0x4F6B62)
    public static let textTertiary = ColorPair(dark: 0x7C958A, light: 0x758C83)

    // The voice: blush after dark, raspberry in daylight
    public static let accent = ColorPair(dark: blush, light: raspberry)
    public static let accentSoft = ColorPair(dark: RGBA(blush, alpha: 0.14), light: RGBA(raspberry, alpha: 0.09))

    // The pencil: highlighter yellow as a mark, and an ink that reads on each ground
    public static let highlight = ColorPair(dark: highlighter, light: 0xF6DE6A)
    public static let highlightInk = ColorPair(dark: highlighter, light: 0x7A5800)
    public static let highlightSoft = ColorPair(dark: RGBA(highlighter, alpha: 0.13), light: RGBA(0xF6DE6A, alpha: 0.45))
    /// The text cursor in the mark: highlighter after dark, ink in daylight (as in the logo).
    public static let cursor = ColorPair(dark: highlighter, light: ink)
    /// Kept for screens written against the first identity. Same as `highlightInk`.
    public static let coral = highlightInk
    public static let coralSoft = highlightSoft

    // Primary button: blush on bottle after dark, bottle on paper in daylight
    public static let buttonFill = ColorPair(dark: blush, light: ink)
    public static let buttonText = ColorPair(dark: bottle, light: 0xFFE7E1)

    // Conversation bubbles. Solid colours: a message is not a gradient.
    public static let bubbleMine = ColorPair(dark: blush, light: ink)
    public static let bubbleMineStart = bubbleMine
    public static let bubbleMineEnd = bubbleMine
    public static let bubbleMineText = ColorPair(dark: bottle, light: 0xFFF3EF)
    public static let bubbleTheirs = ColorPair(dark: 0x21403A, light: 0xF1DDD4)
    public static let bubbleTheirsText = ColorPair(dark: bone, light: ink)

    // Status
    public static let success = ColorPair(dark: 0x8FD9AC, light: 0x1F7A4D)
    public static let warning = ColorPair(dark: 0xF2B866, light: 0x9A5F0B)
    public static let danger = ColorPair(dark: 0xFF7166, light: 0xB3261E)

    // Kept so older code compiles. The identity has no glows; both are the ground colour.
    public static let glowLavender = background
    public static let glowCoral = background

    // Keyboard
    public static let keyboardKey = ColorPair(dark: 0x35504A, light: 0xFFFFFF)
    public static let keyboardKeyPressed = ColorPair(dark: 0x4C6A62, light: 0xEAD6CD)
    public static let keyboardFunctionKey = ColorPair(dark: 0x1D352E, light: 0xE4CEC4)
    public static let keyboardFunctionKeyPressed = ColorPair(dark: 0x35504A, light: 0xFFFFFF)
    public static let keyboardKeyText = ColorPair(dark: bone, light: ink)
    public static let keyboardKeyShadow = ColorPair(dark: RGBA(0x000000, alpha: 0.42), light: RGBA(0x3A1F16, alpha: 0.24))
    public static let keyboardPanel = ColorPair(dark: 0x122720, light: 0xF8ECE6)
}

#if canImport(UIKit)
import UIKit

extension UIColor {
    public convenience init(_ rgba: RGBA) {
        self.init(red: CGFloat(rgba.red), green: CGFloat(rgba.green), blue: CGFloat(rgba.blue), alpha: CGFloat(rgba.alpha))
    }

    /// A colour that follows the current appearance.
    public static func dynamic(_ pair: ColorPair) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(pair.light) : UIColor(pair.dark)
        }
    }
}
#endif
