import ReplyRightCore
import UIKit

// The typing surface: keys, their layout, long-press alternates and repeat-delete.
// All behaviour (what a tap means) lives in TypingEngine; this file only draws and reports touches.

/// Colours and fonts for the keyboard, taken from the same palette as the app.
enum KeyboardTheme {
    static let key = UIColor.dynamic(Palette.keyboardKey)
    static let keyPressed = UIColor.dynamic(Palette.keyboardKeyPressed)
    static let functionKey = UIColor.dynamic(Palette.keyboardFunctionKey)
    static let functionKeyPressed = UIColor.dynamic(Palette.keyboardFunctionKeyPressed)
    static let keyText = UIColor.dynamic(Palette.keyboardKeyText)
    static let keyShadow = UIColor.dynamic(Palette.keyboardKeyShadow)
    static let accent = UIColor.dynamic(Palette.accent)
    static let accentSoft = UIColor.dynamic(Palette.accentSoft)
    static let onAccent = UIColor.dynamic(Palette.bubbleMineText)
    static let text = UIColor.dynamic(Palette.textPrimary)
    static let textSecondary = UIColor.dynamic(Palette.textSecondary)
    static let textTertiary = UIColor.dynamic(Palette.textTertiary)
    static let surface = UIColor.dynamic(Palette.keyboardPanel)
    static let surfaceRaised = UIColor.dynamic(Palette.surfaceRaised)
    static let line = UIColor.dynamic(Palette.lineStrong)
    static let coral = UIColor.dynamic(Palette.coral)
    static let warning = UIColor.dynamic(Palette.warning)

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    /// The system serif, matching the app's display type.
    static func serif(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: .regular)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func symbol(_ name: String, size: CGFloat, weight: UIImage.SymbolWeight = .regular) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight))
    }
}

/// One key. The control is larger than the visible key so taps between keys still land.
final class KeyButton: UIControl {
    enum Style {
        case character
        case function
        /// The return key when the field offers an action such as Send.
        case accent
        /// Invisible and inactive. Keeps a number pad's grid aligned.
        case inert
    }

    let key: KeyboardKey
    private let shadowView = UIView()
    private let face = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    var style: Style = .character {
        didSet { updateColors() }
    }

    /// Where the visible key sits inside the control's touch area.
    var faceFrame: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    init(key: KeyboardKey) {
        self.key = key
        super.init(frame: .zero)

        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = 5.5
        shadowView.layer.cornerCurve = .continuous
        addSubview(shadowView)

        face.isUserInteractionEnabled = false
        face.layer.cornerRadius = 5.5
        face.layer.cornerCurve = .continuous
        addSubview(face)

        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.isUserInteractionEnabled = false
        face.addSubview(titleLabel)

        iconView.contentMode = .center
        iconView.isUserInteractionEnabled = false
        face.addSubview(iconView)

        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(title: String?, image: UIImage?, font: UIFont, accessibilityLabel label: String) {
        titleLabel.text = title
        titleLabel.font = font
        titleLabel.isHidden = title == nil
        iconView.image = image
        iconView.isHidden = image == nil
        accessibilityLabel = label
    }

    override var isHighlighted: Bool {
        didSet { updateColors() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        face.frame = faceFrame
        shadowView.frame = faceFrame.offsetBy(dx: 0, dy: 1)
        titleLabel.frame = face.bounds.insetBy(dx: 2, dy: 0)
        iconView.frame = face.bounds
    }

    private func updateColors() {
        let fill: UIColor
        let content: UIColor
        switch style {
        case .character:
            fill = isHighlighted ? KeyboardTheme.keyPressed : KeyboardTheme.key
            content = KeyboardTheme.keyText
        case .function:
            fill = isHighlighted ? KeyboardTheme.functionKeyPressed : KeyboardTheme.functionKey
            content = KeyboardTheme.keyText
        case .accent:
            fill = isHighlighted ? KeyboardTheme.accent.withAlphaComponent(0.75) : KeyboardTheme.accent
            content = KeyboardTheme.onAccent
        case .inert:
            fill = .clear
            content = .clear
        }
        face.backgroundColor = fill
        shadowView.backgroundColor = style == .inert ? .clear : KeyboardTheme.keyShadow
        titleLabel.textColor = content
        iconView.tintColor = content
        isUserInteractionEnabled = style != .inert
        isAccessibilityElement = style != .inert
    }
}

/// The row of choices shown above a key that is held down (accented letters and so on).
final class AlternatesCallout: UIView {
    static let cell = CGSize(width: 38, height: 46)

    let options: [String]
    private var labels: [UILabel] = []
    private(set) var selectedIndex = 0

    init(options: [String]) {
        self.options = options
        let size = AlternatesCallout.size(for: options.count)
        super.init(frame: CGRect(origin: .zero, size: size))

        backgroundColor = KeyboardTheme.key
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = KeyboardTheme.line.resolvedColor(with: traitCollection).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 4)
        isUserInteractionEnabled = false

        for (index, option) in options.enumerated() {
            let label = UILabel(frame: CGRect(
                x: 4 + CGFloat(index) * AlternatesCallout.cell.width,
                y: 4,
                width: AlternatesCallout.cell.width,
                height: AlternatesCallout.cell.height
            ))
            label.text = option
            label.textAlignment = .center
            label.font = KeyboardTheme.font(22)
            label.layer.cornerRadius = 7
            label.layer.masksToBounds = true
            addSubview(label)
            labels.append(label)
        }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func size(for count: Int) -> CGSize {
        CGSize(width: CGFloat(max(count, 1)) * cell.width + 8, height: cell.height + 8)
    }

    var selectedText: String? {
        options.indices.contains(selectedIndex) ? options[selectedIndex] : nil
    }

    /// Moves the selection to the option under the finger. `x` is in the callout's coordinates.
    func select(atX x: CGFloat) {
        let raw = Int(floor((x - 4) / AlternatesCallout.cell.width))
        let index = min(max(raw, 0), options.count - 1)
        guard index != selectedIndex else { return }
        selectedIndex = index
        refresh()
    }

    private func refresh() {
        for (index, label) in labels.enumerated() {
            let isSelected = index == selectedIndex
            label.backgroundColor = isSelected ? KeyboardTheme.accent : .clear
            label.textColor = isSelected ? KeyboardTheme.onAccent : KeyboardTheme.keyText
        }
    }
}

protocol KeyboardKeysViewDelegate: AnyObject {
    /// A key was pressed (finger down). Used for the click sound.
    func keysViewDidPress(_ view: KeyboardKeysView)
    func keysView(_ view: KeyboardKeysView, didTap action: KeyAction)
    /// The user chose a character from a long-press callout.
    func keysView(_ view: KeyboardKeysView, didChoose text: String)
    /// The globe key was created. The controller wires it to the system's keyboard switcher.
    func keysView(_ view: KeyboardKeysView, didCreateGlobe control: UIControl)
}

/// Draws a `KeyboardLayout` and turns touches into `KeyAction`s.
final class KeyboardKeysView: UIView {
    struct Appearance {
        var shift: TypingEngine.Shift
        var returnTitle: String?
        var returnIsAction: Bool
    }

    weak var delegate: KeyboardKeysViewDelegate?
    /// Callouts are added here so they can extend above the keys (over the toolbar).
    weak var calloutHost: UIView?

    private var layout: KeyboardLayout?
    private var rows: [[KeyButton]] = []
    private var appearance = Appearance(shift: .off, returnTitle: nil, returnIsAction: false)
    private var render: (String) -> String = { $0 }

    private var repeatTimer: Timer?
    private var callout: AlternatesCallout?

    // MARK: Building

    /// Shows a layout. Keys are rebuilt only when the layout actually changes.
    func setLayout(_ newLayout: KeyboardLayout) {
        guard newLayout != layout else { return }
        layout = newLayout
        stopRepeating()
        hideCallout()
        rows.flatMap { $0 }.forEach { $0.removeFromSuperview() }

        rows = newLayout.rows.map { row in
            row.map { key in
                let button = KeyButton(key: key)
                configureTargets(for: button)
                addSubview(button)
                return button
            }
        }
        setNeedsLayout()
    }

    private func configureTargets(for button: KeyButton) {
        if case .character(let value) = button.key.action, value.isEmpty {
            button.style = .inert
            return
        }
        if button.key.action == .globe {
            // The system handles both a tap (next keyboard) and a long press (keyboard list).
            delegate?.keysView(self, didCreateGlobe: button)
            return
        }
        button.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpInside)
        button.addTarget(self, action: #selector(keyCancelled(_:)), for: [.touchUpOutside, .touchCancel, .touchDragExit])

        if !button.key.alternates.isEmpty {
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
            hold.minimumPressDuration = 0.4
            button.addGestureRecognizer(hold)
        }
    }

    /// Updates what the keys show: letter case, the shift symbol, the return key's title.
    func update(_ newAppearance: Appearance, render newRender: @escaping (String) -> String) {
        appearance = newAppearance
        render = newRender
        for button in rows.flatMap({ $0 }) {
            decorate(button)
        }
    }

    private func decorate(_ button: KeyButton) {
        let letterFont = KeyboardTheme.font(23)
        let wordFont = KeyboardTheme.font(16)

        switch button.key.action {
        case .character(let value):
            guard !value.isEmpty else { return }
            let shown = render(value)
            button.style = .character
            button.show(title: shown, image: nil, font: value.count > 1 ? wordFont : letterFont, accessibilityLabel: shown)

        case .space:
            button.style = .character
            button.show(title: button.key.label, image: nil, font: wordFont, accessibilityLabel: "space")

        case .shift:
            let name: String
            switch appearance.shift {
            case .off: name = "shift"
            case .once: name = "shift.fill"
            case .locked: name = "capslock.fill"
            }
            button.style = appearance.shift == .off ? .function : .character
            button.show(
                title: nil,
                image: KeyboardTheme.symbol(name, size: 18, weight: .medium),
                font: wordFont,
                accessibilityLabel: appearance.shift == .locked ? "caps lock" : "shift"
            )

        case .backspace:
            button.style = .function
            button.show(title: nil, image: KeyboardTheme.symbol("delete.left", size: 19, weight: .medium), font: wordFont, accessibilityLabel: "delete")

        case .returnKey:
            button.style = appearance.returnIsAction ? .accent : .function
            if let title = appearance.returnTitle {
                button.show(title: title, image: nil, font: KeyboardTheme.font(16, weight: appearance.returnIsAction ? .semibold : .regular), accessibilityLabel: title)
            } else {
                button.show(title: nil, image: KeyboardTheme.symbol("return", size: 18, weight: .medium), font: wordFont, accessibilityLabel: "return")
            }

        case .globe:
            button.style = .function
            button.show(title: nil, image: KeyboardTheme.symbol("globe", size: 18, weight: .regular), font: wordFont, accessibilityLabel: "Next keyboard")

        case .page:
            button.style = .function
            button.show(title: button.key.label, image: nil, font: wordFont, accessibilityLabel: button.key.label)
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let layout, !rows.isEmpty, bounds.width > 0, bounds.height > 0 else { return }

        let sideInset: CGFloat = 3
        let horizontalGap: CGFloat = 6
        let rowHeight = bounds.height / CGFloat(rows.count)
        let verticalGap: CGFloat = rowHeight > 46 ? 11 : 7
        let unit = (bounds.width - sideInset * 2) / CGFloat(layout.unitsPerRow)

        for (rowIndex, row) in rows.enumerated() {
            let fixedUnits = row.filter { !$0.key.isFlexible }.reduce(0) { $0 + $1.key.width }
            let flexibleCount = row.filter { $0.key.isFlexible }.count
            let flexibleUnits = flexibleCount > 0 ? max(layout.unitsPerRow - fixedUnits, 1) / Double(flexibleCount) : 0
            let usedUnits = flexibleCount > 0 ? layout.unitsPerRow : fixedUnits
            // Rows narrower than the keyboard (the middle letter row) are centred.
            var x = sideInset + CGFloat(layout.unitsPerRow - usedUnits) * unit / 2
            let y = CGFloat(rowIndex) * rowHeight

            for (index, button) in row.enumerated() {
                let width = CGFloat(button.key.isFlexible ? flexibleUnits : button.key.width) * unit
                let face = CGRect(
                    x: x + horizontalGap / 2,
                    y: y + verticalGap / 2,
                    width: width - horizontalGap,
                    height: rowHeight - verticalGap
                )
                // The touch area reaches the screen edges for the first and last key in a row.
                let minX = index == 0 ? 0 : x
                let maxX = index == row.count - 1 ? bounds.width : x + width
                button.frame = CGRect(x: minX, y: y, width: maxX - minX, height: rowHeight)
                button.faceFrame = face.offsetBy(dx: -minX, dy: -y)
                x += width
            }
        }
    }

    // MARK: Touches

    @objc private func keyDown(_ button: KeyButton) {
        delegate?.keysViewDidPress(self)
        if button.key.action == .backspace {
            // Delete acts on touch-down and repeats while held.
            delegate?.keysView(self, didTap: .backspace)
            startRepeating()
        }
    }

    @objc private func keyUp(_ button: KeyButton) {
        if button.key.action == .backspace {
            stopRepeating()
            return
        }
        delegate?.keysView(self, didTap: button.key.action)
    }

    @objc private func keyCancelled(_ button: KeyButton) {
        if button.key.action == .backspace {
            stopRepeating()
        }
    }

    private func startRepeating() {
        stopRepeating()
        let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.delegate?.keysView(self, didTap: .backspace)
        }
        timer.fireDate = Date().addingTimeInterval(0.42)
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    // MARK: Long-press alternates

    @objc private func handleHold(_ gesture: UILongPressGestureRecognizer) {
        guard let button = gesture.view as? KeyButton else { return }
        switch gesture.state {
        case .began:
            showCallout(for: button)
        case .changed:
            if let callout {
                callout.select(atX: gesture.location(in: callout).x)
            }
        case .ended:
            if let text = callout?.selectedText {
                delegate?.keysView(self, didChoose: text)
            }
            hideCallout()
        default:
            hideCallout()
        }
    }

    private func showCallout(for button: KeyButton) {
        hideCallout()
        guard case .character(let base) = button.key.action, let host = calloutHost ?? superview else { return }
        let options = ([base] + button.key.alternates).map(render)
        let view = AlternatesCallout(options: options)

        let keyFrame = button.convert(button.faceFrame, to: host)
        var origin = CGPoint(x: keyFrame.midX - AlternatesCallout.cell.width / 2 - 4, y: keyFrame.minY - view.bounds.height - 6)
        origin.x = min(max(origin.x, 4), host.bounds.width - view.bounds.width - 4)
        origin.y = max(origin.y, 2)
        view.frame.origin = origin
        host.addSubview(view)
        callout = view
        delegate?.keysViewDidPress(self)
    }

    func hideCallout() {
        callout?.removeFromSuperview()
        callout = nil
    }
}
