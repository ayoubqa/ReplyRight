#if canImport(UIKit)
import ReplyRightCore
import SwiftUI
import UIKit

// MARK: - Haptics

/// Light, purposeful haptics. Every call respects the user's setting.
@MainActor
public enum Haptics {
    public static var isEnabled = true

    /// A key press or a small confirmation.
    public static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Something was chosen from a set.
    public static func select() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Something finished well: copied, saved, purchased.
    public static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

// MARK: - Button styles

/// Shrinks slightly while pressed. The base interaction for anything tappable.
public struct RRPressStyle: ButtonStyle {
    private let scale: CGFloat

    public init(scale: CGFloat = 0.97) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.rrSnappy, value: configuration.isPressed)
    }
}

/// The one confident action on a screen: ivory on ink in the evening, ink on ivory in daylight.
public struct RRPrimaryButtonStyle: ButtonStyle {
    private let fullWidth: Bool

    public init(fullWidth: Bool = true) {
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, fullWidth: fullWidth)
    }

    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .rrText(.headline)
                .foregroundStyle(Color.rrButtonText)
                .padding(.horizontal, RRSpace.l)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 54)
                .background {
                    Capsule().fill(Color.rrButtonFill)
                }
                .opacity(isEnabled ? 1 : 0.35)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.rrSnappy, value: configuration.isPressed)
                .contentShape(Capsule())
        }
    }
}

/// A quieter action: outlined on the surface colour.
public struct RRSecondaryButtonStyle: ButtonStyle {
    private let fullWidth: Bool
    private let compact: Bool

    public init(fullWidth: Bool = false, compact: Bool = false) {
        self.fullWidth = fullWidth
        self.compact = compact
    }

    public func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration, fullWidth: fullWidth, compact: compact)
    }

    private struct SecondaryBody: View {
        let configuration: ButtonStyleConfiguration
        let fullWidth: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .rrText(compact ? .callout : .headline)
                .foregroundStyle(Color.rrText)
                .padding(.horizontal, compact ? RRSpace.m : RRSpace.l)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: compact ? 40 : 54)
                .background {
                    Capsule().fill(Color.rrSurfaceRaised)
                }
                .overlay {
                    Capsule().strokeBorder(Color.rrLineStrong, lineWidth: 1)
                }
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.rrSnappy, value: configuration.isPressed)
                .contentShape(Capsule())
        }
    }
}

/// Text-only, for the least important action nearby.
public struct RRQuietButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .rrText(.callout)
            .foregroundStyle(Color.rrTextSecondary)
            .padding(.horizontal, RRSpace.s)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == RRPrimaryButtonStyle {
    public static var rrPrimary: RRPrimaryButtonStyle { RRPrimaryButtonStyle() }
}

extension ButtonStyle where Self == RRSecondaryButtonStyle {
    public static var rrSecondary: RRSecondaryButtonStyle { RRSecondaryButtonStyle() }
    public static var rrSecondaryCompact: RRSecondaryButtonStyle { RRSecondaryButtonStyle(compact: true) }
    public static var rrSecondaryWide: RRSecondaryButtonStyle { RRSecondaryButtonStyle(fullWidth: true) }
}

extension ButtonStyle where Self == RRQuietButtonStyle {
    public static var rrQuiet: RRQuietButtonStyle { RRQuietButtonStyle() }
}

extension ButtonStyle where Self == RRPressStyle {
    public static var rrPress: RRPressStyle { RRPressStyle() }
}

// MARK: - Chips

/// A selectable capsule: intents, tones, shortcuts, follow-up questions.
public struct RRChip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let isLocked: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        isLocked: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? Color.rrAccent : Color.rrTextTertiary)
                }
                Text(title)
                    .rrText(.callout)
                    .lineLimit(1)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.rrTextTertiary)
                }
            }
            .foregroundStyle(isSelected ? Color.rrText : Color.rrTextSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background {
                Capsule().fill(isSelected ? Color.rrAccentSoft : Color.rrSurfaceRaised)
            }
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.rrAccent.opacity(0.7) : Color.rrLine, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.rrPress)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isLocked ? "Part of ReplyRight Pro" : "")
    }
}

/// Lays children out left to right, wrapping onto new lines. Used for chip clouds.
public struct FlowLayout: Layout {
    private let spacing: CGFloat
    private let lineSpacing: CGFloat

    public init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arrangement = arrange(subviews: subviews, maxWidth: maxWidth)
        let width = maxWidth.isFinite ? maxWidth : arrangement.width
        return CGSize(width: width, height: arrangement.height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, origin) in arrangement.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: arrangement.sizes[index].width, height: arrangement.sizes[index].height)
            )
        }
    }

    private struct Arrangement {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> Arrangement {
        var result = Arrangement()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if maxWidth.isFinite, size.width > maxWidth {
                // A single item wider than the line is squeezed to fit rather than clipped.
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            result.origins.append(CGPoint(x: x, y: y))
            result.sizes.append(size)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            result.width = max(result.width, x - spacing)
        }
        result.height = y + lineHeight
        return result
    }
}
#endif
