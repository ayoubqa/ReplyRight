import Foundation

// Design tokens for ReplyRight's "After Hours" identity: deep ink and midnight
// plum, warm ivory, a quiet lavender and a muted coral used sparingly.
//
// Tokens are plain numbers so SwiftUI (the app and share sheet) and UIKit (the
// keyboard) draw from exactly the same palette.

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
    private static let ivory: UInt32 = 0xF6F1E7
    private static let ink: UInt32 = 0x1B1422

    // Backgrounds and surfaces
    public static let background = ColorPair(dark: 0x0F0B15, light: 0xF7F2E9)
    public static let backgroundDeep = ColorPair(dark: 0x09070D, light: 0xEFE8DA)
    public static let surface = ColorPair(dark: 0x19131F, light: 0xFFFCF6)
    public static let surfaceRaised = ColorPair(dark: 0x231B2C, light: 0xF1EADD)
    public static let surfaceHigh = ColorPair(dark: 0x2E2439, light: 0xE7DECE)
    public static let line = ColorPair(dark: RGBA(ivory, alpha: 0.09), light: RGBA(ink, alpha: 0.09))
    public static let lineStrong = ColorPair(dark: RGBA(ivory, alpha: 0.17), light: RGBA(ink, alpha: 0.17))

    // Text
    public static let textPrimary = ColorPair(dark: ivory, light: ink)
    public static let textSecondary = ColorPair(dark: 0xB8AFC2, light: 0x5F5669)
    public static let textTertiary = ColorPair(dark: 0x81788C, light: 0x8D8496)

    // Accents
    public static let accent = ColorPair(dark: 0xBBA9F5, light: 0x5B43A6)
    public static let accentSoft = ColorPair(dark: RGBA(0xBBA9F5, alpha: 0.14), light: RGBA(0x5B43A6, alpha: 0.10))
    public static let coral = ColorPair(dark: 0xF28C72, light: 0xD2553A)
    public static let coralSoft = ColorPair(dark: RGBA(0xF28C72, alpha: 0.14), light: RGBA(0xD2553A, alpha: 0.10))

    // Primary button: ivory on ink in the evening, ink on ivory in daylight
    public static let buttonFill = ColorPair(dark: ivory, light: ink)
    public static let buttonText = ColorPair(dark: 0x150E21, light: ivory)

    // Conversation bubbles
    public static let bubbleMineStart = ColorPair(dark: 0xCDBEFA, light: 0x4A357F)
    public static let bubbleMineEnd = ColorPair(dark: 0xA892EE, light: 0x2F2152)
    public static let bubbleMineText = ColorPair(dark: 0x150E21, light: ivory)
    public static let bubbleTheirs = ColorPair(dark: 0x2A2134, light: 0xE9E1D2)
    public static let bubbleTheirsText = ColorPair(dark: ivory, light: ink)

    // Status
    public static let success = ColorPair(dark: 0x8FCBA5, light: 0x2F8F5B)
    public static let warning = ColorPair(dark: 0xF2C077, light: 0xA8701A)
    public static let danger = ColorPair(dark: 0xF08A8A, light: 0xC24545)

    // Ambient glow behind hero areas
    public static let glowLavender = ColorPair(dark: 0x7B5CE0, light: 0xB9A6F2)
    public static let glowCoral = ColorPair(dark: 0xE2735A, light: 0xF2B09E)

    // Keyboard
    public static let keyboardKey = ColorPair(dark: 0x4A4056, light: 0xFFFFFF)
    public static let keyboardKeyPressed = ColorPair(dark: 0x645875, light: 0xDCD4C6)
    public static let keyboardFunctionKey = ColorPair(dark: 0x2C2437, light: 0xCFC7B9)
    public static let keyboardFunctionKeyPressed = ColorPair(dark: 0x4A4056, light: 0xFFFFFF)
    public static let keyboardKeyText = ColorPair(dark: ivory, light: ink)
    public static let keyboardKeyShadow = ColorPair(dark: RGBA(0x000000, alpha: 0.45), light: RGBA(0x000000, alpha: 0.28))
    public static let keyboardPanel = ColorPair(dark: 0x19131F, light: 0xFFFCF6)
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
