#if canImport(UIKit)
import ReplyRightCore
import SwiftUI
import UIKit

// The ReplyRight mark: an opening quotation mark followed by a text cursor.
// It is the moment just before you say something.
//
// The geometry here is the same as `brand/build.py`, which produces the logo
// files and the app icon, so the mark drawn in the app is the mark in the icon.

/// Numbers that define the mark, on the 100-unit grid used by the artwork.
public enum BrandGeometry {
    public static let strokeWidth: CGFloat = 14.8
    public static let strokeHeight: CGFloat = 30
    /// The quotation strokes lean this many degrees.
    public static let lean: CGFloat = 12
    public static let strokeOrigins: [CGPoint] = [CGPoint(x: 26, y: 26), CGPoint(x: 48.4, y: 26)]
    public static let cursor = CGRect(x: 67.2, y: 23.6, width: 7.6, height: 50)
    /// The optical centre of the whole mark.
    public static let center = CGPoint(x: 43.4, y: 48.6)
    /// How much of a square box the mark fills.
    static let fit: CGFloat = 0.86 * 100 / 64

    /// One quotation stroke with its origin at the top centre: pressed down
    /// round and heavy at the top, lifting to a soft point.
    public static func stroke(width: CGFloat, height: CGFloat) -> Path {
        let r = width / 2
        var path = Path()
        path.move(to: CGPoint(x: -r, y: r))
        path.addArc(
            center: CGPoint(x: 0, y: r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.addCurve(
            to: CGPoint(x: r * 0.12, y: height),
            control1: CGPoint(x: r, y: r + height * 0.35),
            control2: CGPoint(x: r * 0.55, y: height * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: -r * 0.5, y: height * 0.9),
            control1: CGPoint(x: -r * 0.2, y: height * 1.02),
            control2: CGPoint(x: -r * 0.45, y: height * 0.98)
        )
        path.addCurve(
            to: CGPoint(x: -r, y: r),
            control1: CGPoint(x: -r * 0.9, y: height * 0.6),
            control2: CGPoint(x: -r, y: r + height * 0.3)
        )
        path.closeSubpath()
        return path
    }

    /// Maps a point on the artwork grid into a square of the given side, keeping the mark centred.
    static func place(_ point: CGPoint, side: CGFloat) -> CGPoint {
        let unit = side / 100 * fit
        return CGPoint(
            x: side / 2 + (point.x - center.x) * unit,
            y: side / 2 + (point.y - center.y) * unit
        )
    }

    static func unit(side: CGFloat) -> CGFloat {
        side / 100 * fit
    }
}

/// The two quotation strokes of the mark, sized to a square.
public struct QuoteStrokes: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = BrandGeometry.unit(side: side)
        let stroke = BrandGeometry.stroke(
            width: BrandGeometry.strokeWidth * unit,
            height: BrandGeometry.strokeHeight * unit
        )
        var path = Path()
        for origin in BrandGeometry.strokeOrigins {
            let point = BrandGeometry.place(origin, side: side)
            let transform = CGAffineTransform(translationX: rect.minX + point.x, y: rect.minY + point.y)
                .rotated(by: BrandGeometry.lean * .pi / 180)
            path.addPath(stroke, transform: transform)
        }
        return path
    }
}

/// The cursor of the mark, sized to the same square as `QuoteStrokes`.
public struct CursorStroke: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = BrandGeometry.unit(side: side)
        let origin = BrandGeometry.place(BrandGeometry.cursor.origin, side: side)
        let frame = CGRect(
            x: rect.minX + origin.x,
            y: rect.minY + origin.y,
            width: BrandGeometry.cursor.width * unit,
            height: BrandGeometry.cursor.height * unit
        )
        return Path(roundedRect: frame, cornerRadius: frame.width / 2, style: .continuous)
    }
}

/// The ReplyRight symbol. When `isWriting` is true the cursor blinks, which is
/// how the app shows that it is working on something.
public struct BrandMark: View {
    private let size: CGFloat
    private let isWriting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorVisible = true

    public init(size: CGFloat = 40, isWriting: Bool = false) {
        self.size = size
        self.isWriting = isWriting
    }

    public var body: some View {
        ZStack {
            QuoteStrokes().fill(Color.rrAccent)
            CursorStroke()
                .fill(Color.rrCursor)
                .opacity(cursorVisible ? 1 : 0.12)
        }
        .frame(width: size, height: size)
        .onAppear { startBlinking() }
        .onChange(of: isWriting) { _, _ in startBlinking() }
        .accessibilityHidden(true)
    }

    private func startBlinking() {
        guard isWriting, !reduceMotion else {
            withAnimation(.easeOut(duration: 0.15)) { cursorVisible = true }
            return
        }
        cursorVisible = true
        withAnimation(.easeInOut(duration: 0.52).repeatForever(autoreverses: true)) {
            cursorVisible = false
        }
    }
}

/// The primary logo: the quotation mark, the name, and the cursor.
public struct BrandLogo: View {
    private let height: CGFloat
    private let isWriting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorVisible = true

    /// - Parameter height: The cap height of the lockup, roughly the text size.
    public init(height: CGFloat = 34, isWriting: Bool = false) {
        self.height = height
        self.isWriting = isWriting
    }

    public var body: some View {
        HStack(alignment: .center, spacing: height * 0.16) {
            LogoQuotes()
                .fill(Color.rrAccent)
                .frame(width: height * 0.62, height: height * 0.42)
                .offset(y: -height * 0.2)
            Text("ReplyRight")
                .font(RRFonts.display(size: height))
                .tracking(-height * 0.01)
                .foregroundStyle(Color.rrText)
                .lineLimit(1)
                .fixedSize()
            Capsule()
                .fill(Color.rrCursor)
                .frame(width: max(3, height * 0.1), height: height * 0.92)
                .opacity(cursorVisible ? 1 : 0.12)
        }
        .onAppear {
            guard isWriting, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.52).repeatForever(autoreverses: true)) {
                cursorVisible = false
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ReplyRight")
        .accessibilityAddTraits(.isImage)
    }

    /// Two strokes filling their own small frame, for use beside the wordmark.
    private struct LogoQuotes: Shape {
        func path(in rect: CGRect) -> Path {
            let strokeWidth = rect.width * 0.4
            let stroke = BrandGeometry.stroke(width: strokeWidth, height: rect.height)
            var path = Path()
            for x in [rect.minX + rect.width * 0.3, rect.minX + rect.width * 0.86] {
                let transform = CGAffineTransform(translationX: x, y: rect.minY)
                    .rotated(by: BrandGeometry.lean * .pi / 180)
                path.addPath(stroke, transform: transform)
            }
            return path
        }
    }
}

/// A highlighter stroke under a few words: the pencil pointing at what matters.
/// Used once per screen at most.
public struct Highlighted: View {
    private let text: String
    private let style: RRTextStyle

    public init(_ text: String, style: RRTextStyle = .headline) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .rrText(style)
            .foregroundStyle(Color.rrText)
            .padding(.horizontal, 3)
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.rrHighlight.opacity(0.42))
                    .frame(height: 9)
                    .offset(y: -1)
            }
    }
}
#endif
