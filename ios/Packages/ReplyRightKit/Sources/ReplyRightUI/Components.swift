#if canImport(UIKit)
import ImageIO
import ReplyRightCore
import SwiftUI
import UIKit

// MARK: - Bubbles

/// A message bubble: fully rounded except for the corner nearest its sender.
/// Bubbles are the one rounded container in ReplyRight, and they are only ever
/// used for messages.
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
                BubbleShape(side: side).fill(side == .mine ? Color.rrBubbleMine : Color.rrBubbleTheirs)
            }
            .frame(maxWidth: .infinity, alignment: side == .mine ? .trailing : .leading)
            .padding(side == .mine ? .leading : .trailing, compact ? 28 : 44)
            .accessibilityLabel(side == .mine ? "You: \(text)" : "Them: \(text)")
    }
}

/// Three dots, like someone is typing. Used inside a practice conversation,
/// where the other side really is "typing".
public struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .onAppear { isAnimating = !reduceMotion }
        .accessibilityHidden(true)
    }
}

/// The loading state: the mark with its cursor blinking, and a line that
/// changes while you wait. ReplyRight shows it is working the way a writer
/// does, with a cursor, not with a spinner.
public struct ThinkingView: View {
    private let lines: [String]
    @State private var index = 0

    public init(lines: [String]) {
        self.lines = lines
    }

    public var body: some View {
        HStack(alignment: .center, spacing: RRSpace.s) {
            BrandMark(size: 44, isWriting: true)
            Text(currentLine)
                .rrText(.bodyLarge)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .id(index)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, RRSpace.s)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.35)) {
                    index += 1
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lines.first ?? "Working on it")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var currentLine: String {
        lines.isEmpty ? "" : lines[index % lines.count]
    }
}

// MARK: - Ground and sections

/// The ground every screen sits on: one flat colour. Kept under its first
/// name so existing screens keep working; there is no longer any glow.
public struct AuroraBackground: View {
    public init(intensity: Double = 1) {}

    public var body: some View {
        Color.rrBackground
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the ReplyRight ground behind a screen.
    public func rrScreenBackground(intensity: Double = 1) -> some View {
        background {
            Color.rrBackground.ignoresSafeArea()
        }
    }

    /// A section on the ground: a hairline above and room to breathe. No box.
    ///
    /// This replaces the bordered card of the first design. The name is kept
    /// so every screen picks up the change at once.
    public func rrCard(padding: CGFloat = 18, radius: CGFloat = RRRadius.card) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, padding)
            .overlay(alignment: .top) {
                Rule()
            }
    }

    /// A surface you write on or that floats above the ground (a sheet, the
    /// compose area). The only filled rectangle in the system; use it rarely.
    public func rrPanel(padding: CGFloat = RRSpace.m, radius: CGFloat = RRRadius.card) -> some View {
        self
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.rrSurface)
            }
    }
}

/// The reason behind a suggestion, set beside a pencil line like a note in the margin.
public struct MarginNote: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.rrHighlight)
                .frame(width: 3)
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

// MARK: - Where an answer came from

/// Marks content that is a pre-written sample rather than AI output.
public struct DemoBadge: View {
    private let detailed: Bool

    public init(detailed: Bool = false) {
        self.detailed = detailed
    }

    public var body: some View {
        if detailed {
            HStack(alignment: .top, spacing: RRSpace.s) {
                Image(systemName: "theatermasks")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.rrHighlightInk)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Demo mode")
                        .rrText(.headline)
                        .foregroundStyle(Color.rrText)
                    Text("These are pre-written samples, not replies to your conversation. The server has no AI key yet.")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(RRSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrHighlightSoft)
            }
            .accessibilityElement(children: .combine)
        } else {
            ProvenanceLabel(.demo)
        }
    }
}

/// Says plainly whether what follows was written by live AI or is a demo sample.
public struct ProvenanceLabel: View {
    private let mode: GenerationMode

    public init(_ mode: GenerationMode) {
        self.mode = mode
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(mode == .live ? Color.rrSuccess : Color.rrHighlightInk)
                .frame(width: 7, height: 7)
            Text(mode == .live ? "Written by live AI" : "Demo sample, not written for you")
                .rrText(.footnote)
                .foregroundStyle(mode == .live ? Color.rrTextSecondary : Color.rrHighlightInk)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small, tappable summary of the connection: live AI, demo mode, or not connected.
public struct ConnectionPill: View {
    private let state: ConnectionState

    public init(_ state: ConnectionState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 7) {
            Group {
                if state == .checking {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Color.rrTextSecondary)
                } else {
                    Circle().fill(tint).frame(width: 8, height: 8)
                }
            }
            .frame(width: 12, height: 12)
            Text(state.title)
                .rrText(.footnote)
                .foregroundStyle(state.isProblem ? Color.rrText : Color.rrTextSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 32)
        .overlay {
            Capsule().strokeBorder(state.isProblem ? tint.opacity(0.7) : Color.rrLineStrong, lineWidth: 1)
        }
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection: \(state.title)")
        .accessibilityHint("Shows connection details")
    }

    private var tint: Color {
        switch state {
        case .live: return Color.rrSuccess
        case .demo: return Color.rrHighlightInk
        case .liveFailing, .unreachable: return Color.rrDanger
        case .unknown, .checking: return Color.rrTextTertiary
        }
    }
}

// MARK: - Failure

/// A failure, said plainly, with a way forward.
///
/// It names what went wrong, offers to try again when that can help, and can
/// carry a second action such as opening the connection screen.
public struct ErrorNote: View {
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: () -> Void
    private let secondaryTitle: String?
    private let secondaryAction: (() -> Void)?

    public init(_ message: String, actionTitle: String = "Try again", action: @escaping () -> Void) {
        self.title = "That didn't go through"
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryTitle = nil
        self.secondaryAction = nil
    }

    /// Builds the note from an API error: the right heading, a retry only
    /// when retrying can help, and an optional second action.
    public init(
        error: APIError,
        retry: @escaping () -> Void,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.title = error.title
        self.message = error.userMessage
        self.actionTitle = error.isRetryable ? "Try again" : nil
        self.action = retry
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            HStack(alignment: .firstTextBaseline, spacing: RRSpace.xs) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.rrDanger)
                Text(title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
            }
            Text(message)
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if actionTitle != nil || secondaryTitle != nil {
                HStack(spacing: RRSpace.s) {
                    if let actionTitle {
                        Button(actionTitle, action: action)
                            .buttonStyle(.rrSecondaryCompact)
                    }
                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                            .buttonStyle(.rrQuiet)
                    }
                }
                .padding(.top, RRSpace.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, RRSpace.m)
        .overlay(alignment: .top) { Rule() }
        .accessibilityElement(children: .contain)
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
                        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
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

/// A multi-line writing surface with a placeholder.
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
                .tint(Color.rrCursor)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
                .accessibilityLabel(placeholder)
        }
        .padding(RRSpace.s)
        .background {
            RoundedRectangle(cornerRadius: RRRadius.card, style: .continuous).fill(Color.rrSurface)
        }
    }
}

/// A single-line (or gently growing) field: words on a line, like filling in a form by hand.
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
            .tint(Color.rrCursor)
            .padding(.vertical, RRSpace.s)
            .frame(minHeight: 48)
            .overlay(alignment: .bottom) {
                Rule(strong: true)
            }
    }
}

// MARK: - Rows

/// A line on the menu: what you can do, in the display face, with a short
/// description underneath. Used for the main choices on a screen.
public struct MenuRow: View {
    private let title: String
    private let detail: String?
    private let trailing: String?
    private let showsChevron: Bool

    public init(_ title: String, detail: String? = nil, trailing: String? = nil, showsChevron: Bool = true) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(alignment: .center, spacing: RRSpace.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .rrText(.menu)
                    .foregroundStyle(Color.rrText)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .rrText(.callout)
                        .foregroundStyle(Color.rrTextSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: RRSpace.xs)
            if let trailing {
                Text(trailing)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.rrTextTertiary)
            }
        }
        .padding(.vertical, RRSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule() }
        .contentShape(Rectangle())
    }
}

/// An invitation to act where there is nothing yet.
public struct EmptyNote: View {
    private let title: String
    private let message: String

    public init(_ title: String, message: String) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            BrandMark(size: 40)
                .opacity(0.9)
                .padding(.leading, -6)
            Text(title)
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
            Text(message)
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, RRSpace.l)
    }
}

// MARK: - Screenshots

/// Prepares screenshots for upload on the device: downsizes them and re-encodes
/// as JPEG, which also removes metadata such as location.
public enum ScreenshotPreparer {
    public static let maxEdge: CGFloat = 2000

    /// Downsamples straight from the encoded data, so a large photo is never decoded at full size.
    /// That matters in the share extension, which runs under a tight memory limit.
    public static func prepare(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxEdge),
        ]
        guard let downsampled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return prepare(UIImage(cgImage: downsampled))
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
