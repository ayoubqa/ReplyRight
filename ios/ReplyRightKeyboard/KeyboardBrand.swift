import ReplyRightCore
import UIKit

/// The ReplyRight mark drawn for the keyboard: two quotation strokes and a cursor.
///
/// The numbers are the same as `BrandGeometry` in ReplyRightUI and
/// `brand/build.py`. They are repeated here because the keyboard does not link
/// the SwiftUI package, to keep its memory use low.
final class KeyboardBrandMark: UIView {
    private let quotes = CAShapeLayer()
    private let cursorLayer = CAShapeLayer()
    private let side: CGFloat

    /// When true the cursor blinks, which is how the keyboard shows it is working.
    var isWriting = false {
        didSet { updateAnimation() }
    }

    init(side: CGFloat = 26) {
        self.side = side
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        layer.addSublayer(quotes)
        layer.addSublayer(cursorLayer)
        isAccessibilityElement = false
        isUserInteractionEnabled = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: side, height: side)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let box = min(bounds.width, bounds.height)
        guard box > 0 else { return }
        let unit = box / 64 * 0.86
        let centerX: CGFloat = 43.4
        let centerY: CGFloat = 48.6
        let midX = bounds.midX
        let midY = bounds.midY

        let path = UIBezierPath()
        let origins: [CGFloat] = [26, 48.4]
        for originX in origins {
            let stroke = KeyboardBrandMark.stroke(width: 14.8 * unit, height: 30 * unit)
            let x = midX + (originX - centerX) * unit
            let y = midY + (26 - centerY) * unit
            stroke.apply(CGAffineTransform(translationX: x, y: y).rotated(by: 12 * CGFloat.pi / 180))
            path.append(stroke)
        }
        quotes.path = path.cgPath

        let cursorFrame = CGRect(
            x: midX + (67.2 - centerX) * unit,
            y: midY + (23.6 - centerY) * unit,
            width: 7.6 * unit,
            height: 50 * unit
        )
        cursorLayer.path = UIBezierPath(roundedRect: cursorFrame, cornerRadius: cursorFrame.width / 2).cgPath

        quotes.fillColor = KeyboardTheme.accent.resolvedColor(with: traitCollection).cgColor
        cursorLayer.fillColor = KeyboardTheme.cursor.resolvedColor(with: traitCollection).cgColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        cursorLayer.removeAnimation(forKey: "blink")
        guard isWriting, window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.12
        blink.duration = 0.52
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        blink.isRemovedOnCompletion = false
        cursorLayer.add(blink, forKey: "blink")
    }

    /// One quotation stroke with its origin at the top centre.
    private static func stroke(width: CGFloat, height: CGFloat) -> UIBezierPath {
        let r = width / 2
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -r, y: r))
        path.addArc(withCenter: CGPoint(x: 0, y: r), radius: r, startAngle: CGFloat.pi, endAngle: 2 * CGFloat.pi, clockwise: true)
        path.addCurve(
            to: CGPoint(x: r * 0.12, y: height),
            controlPoint1: CGPoint(x: r, y: r + height * 0.35),
            controlPoint2: CGPoint(x: r * 0.55, y: height * 0.82)
        )
        path.addCurve(
            to: CGPoint(x: -r * 0.5, y: height * 0.9),
            controlPoint1: CGPoint(x: -r * 0.2, y: height * 1.02),
            controlPoint2: CGPoint(x: -r * 0.45, y: height * 0.98)
        )
        path.addCurve(
            to: CGPoint(x: -r, y: r),
            controlPoint1: CGPoint(x: -r * 0.9, y: height * 0.6),
            controlPoint2: CGPoint(x: -r, y: r + height * 0.3)
        )
        path.close()
        return path
    }
}
