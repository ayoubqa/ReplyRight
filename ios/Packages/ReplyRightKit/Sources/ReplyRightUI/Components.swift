#if canImport(UIKit)
import ReplyRightCore
import SwiftUI
import UIKit

// MARK: - Bubbles

/// A message bubble: fully rounded except for the corner nearest its sender.
public struct BubbleShape: Shape {
    public enum Side: Sendable {
        /// A message the user sends (or might send). Sits on the right.
        case mine
        /// A message from the other person. Sits on the left.
        case theirs
    }

    private let side: Side
    private let radius: CGFloat

    public init(side: Side, radius: CGFloat = RRRadius.bubble) {
        self.side = side
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 6
        let radii = RectangleCornerRadii(
            topLeading: radius,
            bottomLeading: side == .theirs ? tail : radius,
            bottomTrailing: side == .mine ? tail : radius,
            topTrailing: radius
        )
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    }
}

/// One message in a conversation.
public struct MessageBubble: View {
    private let text: String
    private let side: BubbleShape.Side
    private let compact: Bool

    public init(_ text: String, side: BubbleShape.Side, compact: Bool = false) {
        self.text = text
        self.side = side
        self.compact = compact
    }

    public var body: some View {
        Text(text)
            .rrText(compact ? .callout : .message)
            .foregroundStyle(side == .mine ? Color.rrBubbleMineText : Color.rrBubbleTheirsText)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 11)
            .background {
                if side == .mine {
                    BubbleShape(side: .mine).fill(LinearGradient.rrBubbleMine)
                } else {
                    BubbleShape(side: .theirs).fill(Color.rrBubbleTheirs)
                }
            }
            .frame(maxWidth: .infinity, alignment: side == .mine ? .trailing : .leading)
            .padding(side == .mine ? .leading : .trailing, compact ? 28 : 44)
            .accessibilityLabel(side == .mine ? "You: \(text)" : "Them: \(text)")
    }
}

/// Three dots, like someone is typing.
public struct TypingDots: View {
    @State private var isAnimating = false

    public init() {}

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(isAnimating ? 1 : 0.3)
                    .offset(y: isAnimating ? -2.5 : 2)
                    .animation(
                        .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.16),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
        .accessibilityHidden(true)
    }
}

/// The loading state: a typing bubble and a line that changes while you wait.
/// Loading should feel like someone is working on it for you, not like a spinner.
public struct ThinkingView: View {
    private let lines: [String]
    @State private var index = 0

    public init(lines: [String]) {
        self.lines = lines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            TypingDots()
                .foregroundStyle(Color.rrTextSecondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background {
                    BubbleShape(side: .theirs).fill(Color.rrBubbleTheirs)
                }
            Text(currentLine)
                .rrText(.note)
                .foregroundStyle(Color.rrTextSecondary)
                .id(index)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.35)) {
                    index += 1
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.first ?? "Working on it")
    }

    private var currentLine: String {
        lines.isEmpty ? "" : lines[index % lines.count]
    }
}

// MARK: - Surfaces

/// The ambient background: ink fading to deeper ink, with a slow lavender and coral glow.
public struct AuroraBackground: View {
    private let intensity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    public init(intensity: Double = 1) {
        self.intensity = intensity
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color.rrBackground, Color.rrBackgroundDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
                glow(Color.rrGlowLavender.opacity(0.42 * intensity), diameter: width * 1.5)
                    .offset(x: isDrifting ? -width * 0.30 : -width * 0.16, y: -width * 0.78)
                glow(Color.rrGlowCoral.opacity(0.20 * intensity), diameter: width * 1.2)
                    .offset(x: isDrifting ? width * 0.40 : width * 0.52, y: -width * 0.66)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                isDrifting = true
            }
        }
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
    }
}

extension View {
    /// Puts the ambient ReplyRight background behind a screen.
    public func rrScreenBackground(intensity: Double = 1) -> some View {
        background {
            AuroraBackground(intensity: intensity).ignoresSafeArea()
        }
    }

    /// A soft raised surface with a hairline border.
    public func rrCard(padding: CGFloat = 18, radius: CGFloat = RRRadius.card) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.rrSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.rrLine, lineWidth: 1)
            }
    }
}

/// The reason behind a suggestion, set like an editor's note in the margin.
public struct MarginNote: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.rrAccent.opacity(0.55))
                .frame(width: 2)
            Text(text)
                .rrText(.note)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A gentle note when something deserves care: a boundary, mixed signals, safety.
public struct HeadsUpNote: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: RRSpace.s) {
            Image(systemName: "hand.raised")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.rrAccent)
                .padding(.top, 2)
            Text(text)
                .rrText(.callout)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(RRSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrAccentSoft)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heads up. \(text)")
    }
}

/// Marks content that is a pre-written sample rather than AI output.
public struct DemoBadge: View {
    private let detailed: Bool

    public init(detailed: Bool = false) {
        self.detailed = detailed
    }

    public var body: some View {
        HStack(alignment: .top, spacing: RRSpace.xs) {
            Image(systemName: "theatermasks")
                .font(.system(size: 13, weight: .medium))
            Text(detailed
                ? "Demo mode. These are pre-written samples, not replies to your conversation. Connect an AI provider on the server for the real thing."
                : "Sample")
                .rrText(detailed ? .footnote : .caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.rrWarning)
        .padding(.horizontal, detailed ? RRSpace.m : RRSpace.xs)
        .padding(.vertical, detailed ? RRSpace.s : RRSpace.xxs)
        .frame(maxWidth: detailed ? .infinity : nil, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: detailed ? RRRadius.control : 8, style: .continuous)
                .fill(Color.rrWarning.opacity(0.12))
        }
    }
}

/// A friendly failure state with one way forward.
public struct ErrorNote: View {
    private let message: String
    private let actionTitle: String
    private let action: () -> Void

    public init(_ message: String, actionTitle: String = "Try again", action: @escaping () -> Void) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Text("That didn't go through")
                .rrText(.headline)
                .foregroundStyle(Color.rrText)
            Text(message)
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.rrSecondaryCompact)
                .padding(.top, RRSpace.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard()
    }
}

// MARK: - Toast

struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .rrText(.callout)
                        .foregroundStyle(Color.rrButtonText)
                        .padding(.horizontal, RRSpace.m)
                        .padding(.vertical, RRSpace.s)
                        .background {
                            Capsule().fill(Color.rrButtonFill)
                        }
                        .shadow(color: Color.black.opacity(0.25), radius: 16, y: 8)
                        .padding(.top, RRSpace.xs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: message) {
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            if !Task.isCancelled {
                                self.message = nil
                            }
                        }
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(.rrSnappy, value: message)
    }
}

extension View {
    /// Shows a brief confirmation at the top of the screen, then clears the binding.
    public func rrToast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

// MARK: - Inputs

/// A multi-line text area with a placeholder.
public struct RRTextArea: View {
    @Binding private var text: String
    private let placeholder: String
    private let minHeight: CGFloat

    public init(text: Binding<String>, placeholder: String, minHeight: CGFloat = 120) {
        _text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .rrText(.body)
                .foregroundStyle(Color.rrText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .accessibilityLabel(placeholder)
        }
        .padding(RRSpace.s)
        .background {
            RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).strokeBorder(Color.rrLineStrong, lineWidth: 1)
        }
    }
}

/// A single-line (or gently growing) field in the ReplyRight style.
public struct RRField: View {
    @Binding private var text: String
    private let placeholder: String
    private let lineLimit: Int

    public init(_ placeholder: String, text: Binding<String>, lineLimit: Int = 1) {
        _text = text
        self.placeholder = placeholder
        self.lineLimit = lineLimit
    }

    public var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .lineLimit(1...max(1, lineLimit))
            .rrText(.body)
            .foregroundStyle(Color.rrText)
            .padding(.horizontal, RRSpace.m)
            .frame(minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).strokeBorder(Color.rrLineStrong, lineWidth: 1)
            }
    }
}

// MARK: - Screenshots

/// Prepares screenshots for upload on the device: downsizes them and re-encodes
/// as JPEG, which also removes metadata such as location.
public enum ScreenshotPreparer {
    public static let maxEdge: CGFloat = 2000

    public static func prepare(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return prepare(image)
    }

    public static func prepare(_ image: UIImage) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth >= 1, pixelHeight >= 1 else { return nil }

        let ratio = min(1, maxEdge / max(pixelWidth, pixelHeight))
        let target = CGSize(width: floor(pixelWidth * ratio), height: floor(pixelHeight * ratio))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let redrawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }

        var quality: CGFloat = 0.85
        var encoded = redrawn.jpegData(compressionQuality: quality)
        while let current = encoded, current.count > RequestLimits.maxImageBytes, quality > 0.4 {
            quality -= 0.15
            encoded = redrawn.jpegData(compressionQuality: quality)
        }
        guard let result = encoded, result.count <= RequestLimits.maxImageBytes else { return nil }
        return result
    }
}
#endif
