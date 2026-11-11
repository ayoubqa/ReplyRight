import ReplyRightCore
import UIKit

// The ReplyRight bar above the keys, and the panel that replaces the keys
// while the user is choosing or reading suggestions.

private func pillConfiguration(title: String?, symbol: String?, prominent: Bool) -> UIButton.Configuration {
    var configuration = UIButton.Configuration.filled()
    configuration.title = title
    if let symbol {
        configuration.image = KeyboardTheme.symbol(symbol, size: 13, weight: .semibold)
        configuration.imagePadding = 5
    }
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    configuration.baseBackgroundColor = prominent ? KeyboardTheme.accent : KeyboardTheme.surfaceRaised
    configuration.baseForegroundColor = prominent ? KeyboardTheme.onAccent : KeyboardTheme.text
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = KeyboardTheme.font(14, weight: .semibold)
        return outgoing
    }
    return configuration
}

/// The bar above the keys. It is the only place AI features start from.
final class KeyboardToolbar: UIView {
    enum Mode: Equatable {
        /// Normal typing: Reply, Rewrite and Saved are available.
        case typing
        /// A sensitive field: AI features are switched off.
        case paused
        /// A panel is open. Shows its title and a way back to the keys.
        case panel(title: String)
    }

    var onReply: (() -> Void)?
    var onRewrite: (() -> Void)?
    var onSaved: (() -> Void)?
    var onBackToKeys: (() -> Void)?

    private let stack = UIStackView()
    private let brand = UIImageView()
    private let replyButton = UIButton(type: .system)
    private let rewriteButton = UIButton(type: .system)
    private let savedButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let spacer = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        brand.image = KeyboardTheme.symbol("sparkle", size: 15, weight: .semibold)
        brand.tintColor = KeyboardTheme.coral
        brand.contentMode = .center
        brand.setContentHuggingPriority(.required, for: .horizontal)
        brand.isAccessibilityElement = false

        replyButton.configuration = pillConfiguration(title: "Reply", symbol: "text.bubble", prominent: true)
        replyButton.addTarget(self, action: #selector(tapReply), for: .touchUpInside)
        replyButton.accessibilityHint = "Suggests replies to a conversation you shared"

        rewriteButton.configuration = pillConfiguration(title: "Rewrite", symbol: "wand.and.stars", prominent: false)
        rewriteButton.addTarget(self, action: #selector(tapRewrite), for: .touchUpInside)
        rewriteButton.accessibilityHint = "Rewrites what you have typed"

        savedButton.configuration = pillConfiguration(title: nil, symbol: "bookmark", prominent: false)
        savedButton.addTarget(self, action: #selector(tapSaved), for: .touchUpInside)
        savedButton.accessibilityLabel = "Saved replies"

        backButton.configuration = pillConfiguration(title: "Keys", symbol: "keyboard", prominent: false)
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)
        backButton.accessibilityLabel = "Back to the keyboard"

        titleLabel.font = KeyboardTheme.font(14, weight: .semibold)
        titleLabel.textColor = KeyboardTheme.textSecondary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        for view in [brand, backButton, replyButton, rewriteButton, titleLabel, spacer, savedButton] {
            stack.addArrangedSubview(view)
        }
        setMode(.typing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setMode(_ mode: Mode) {
        switch mode {
        case .typing:
            brand.isHidden = false
            backButton.isHidden = true
            replyButton.isHidden = false
            rewriteButton.isHidden = false
            savedButton.isHidden = false
            titleLabel.isHidden = true
        case .paused:
            brand.isHidden = false
            backButton.isHidden = true
            replyButton.isHidden = true
            rewriteButton.isHidden = true
            savedButton.isHidden = true
            titleLabel.isHidden = false
            titleLabel.text = "ReplyRight is paused in this field"
        case .panel(let title):
            brand.isHidden = true
            backButton.isHidden = false
            replyButton.isHidden = true
            rewriteButton.isHidden = true
            savedButton.isHidden = true
            titleLabel.isHidden = false
            titleLabel.text = title
        }
    }

    @objc private func tapReply() { onReply?() }
    @objc private func tapRewrite() { onRewrite?() }
    @objc private func tapSaved() { onSaved?() }
    @objc private func tapBack() { onBackToKeys?() }
}

/// Three dots that pulse, like someone typing.
final class TypingDotsView: UIView {
    private let dots: [CALayer] = (0..<3).map { _ in CALayer() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for dot in dots {
            dot.cornerRadius = 3.5
            layer.addSublayer(dot)
        }
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 34, height: 12)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let colour = KeyboardTheme.textSecondary.resolvedColor(with: traitCollection).cgColor
        for (index, dot) in dots.enumerated() {
            dot.backgroundColor = colour
            dot.frame = CGRect(x: CGFloat(index) * 12, y: bounds.midY - 3.5, width: 7, height: 7)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        for (index, dot) in dots.enumerated() {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.25
            pulse.toValue = 1
            pulse.duration = 0.55
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.16
            pulse.isRemovedOnCompletion = false
            dot.add(pulse, forKey: "pulse")
        }
    }
}

/// A tappable suggestion: a small style label and the message.
private final class SuggestionRow: UIControl {
    private let badge = UILabel()
    private let message = UILabel()

    init(badgeText: String, text: String) {
        super.init(frame: .zero)
        backgroundColor = KeyboardTheme.surfaceRaised
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous

        badge.text = badgeText.uppercased()
        badge.font = KeyboardTheme.font(10, weight: .semibold)
        badge.textColor = KeyboardTheme.accent
        badge.isHidden = badgeText.isEmpty

        message.text = text
        message.font = KeyboardTheme.font(15)
        message.textColor = KeyboardTheme.text
        message.numberOfLines = 3

        let stack = UIStackView(arrangedSubviews: [badge, message])
        stack.axis = .vertical
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = badgeText.isEmpty ? text : "\(badgeText). \(text)"
        accessibilityHint = "Inserts this message"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

/// The area that replaces the keys while ReplyRight is helping.
/// It only renders what the controller tells it to; all decisions live in the controller.
final class AssistPanelView: UIView {
    struct Chip {
        let id: String
        let title: String
        var isSelected = false
        var isLocked = false
    }

    struct Row {
        let badge: String
        let text: String
    }

    var onChip: ((String) -> Void)?
    var onPrimary: (() -> Void)?
    var onSecondary: (() -> Void)?
    var onRow: ((Int) -> Void)?

    private let scroll = UIScrollView()
    private let content = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 4),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Screens

    /// A choice to make before asking: what the reply should do, or how to rewrite.
    func showSetup(
        title: String,
        quote: String?,
        chips: [Chip],
        primaryTitle: String?,
        secondaryTitle: String?,
        footnote: String?
    ) {
        reset()
        content.addArrangedSubview(makeTitle(title))
        if let quote, !quote.isEmpty {
            content.addArrangedSubview(makeQuote(quote))
        }
        if !chips.isEmpty {
            content.addArrangedSubview(makeChips(chips))
        }
        if let footnote {
            content.addArrangedSubview(makeBody(footnote, small: true))
        }
        addButtons(primaryTitle: primaryTitle, secondaryTitle: secondaryTitle)
    }

    func showLoading(_ line: String) {
        reset()
        let dots = TypingDotsView()
        let holder = UIStackView(arrangedSubviews: [dots, UIView()])
        holder.axis = .horizontal
        content.addArrangedSubview(UIView.spacer(height: 18))
        content.addArrangedSubview(holder)
        let label = UILabel()
        label.text = line
        label.font = KeyboardTheme.serif(16)
        label.textColor = KeyboardTheme.textSecondary
        label.numberOfLines = 2
        content.addArrangedSubview(label)
        UIAccessibility.post(notification: .announcement, argument: line)
    }

    func showResults(header: String?, rows: [Row], secondaryTitle: String?, footnote: String?) {
        reset()
        if let header, !header.isEmpty {
            content.addArrangedSubview(makeBody(header, small: true))
        }
        for (index, row) in rows.enumerated() {
            let control = SuggestionRow(badgeText: row.badge, text: row.text)
            control.tag = index
            control.addTarget(self, action: #selector(tapRow(_:)), for: .touchUpInside)
            content.addArrangedSubview(control)
        }
        if let footnote {
            content.addArrangedSubview(makeBody(footnote, small: true))
        }
        addButtons(primaryTitle: nil, secondaryTitle: secondaryTitle)
    }

    func showMessage(title: String, detail: String, primaryTitle: String?, secondaryTitle: String?) {
        reset()
        content.addArrangedSubview(UIView.spacer(height: 6))
        content.addArrangedSubview(makeTitle(title))
        content.addArrangedSubview(makeBody(detail, small: false))
        addButtons(primaryTitle: primaryTitle, secondaryTitle: secondaryTitle)
    }

    // MARK: Building blocks

    private func reset() {
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        scroll.setContentOffset(.zero, animated: false)
    }

    private func makeTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = KeyboardTheme.serif(19)
        label.textColor = KeyboardTheme.text
        label.numberOfLines = 2
        label.accessibilityTraits = .header
        return label
    }

    private func makeBody(_ text: String, small: Bool) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = KeyboardTheme.font(small ? 12 : 14)
        label.textColor = small ? KeyboardTheme.textTertiary : KeyboardTheme.textSecondary
        label.numberOfLines = 0
        return label
    }

    private func makeQuote(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = KeyboardTheme.font(14)
        label.textColor = KeyboardTheme.text
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        let box = UIView()
        box.backgroundColor = KeyboardTheme.surfaceRaised
        box.layer.cornerRadius = 12
        box.layer.cornerCurve = .continuous
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
        ])
        return box
    }

    private func makeChips(_ chips: [Chip]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        for (index, chip) in chips.enumerated() {
            let button = UIButton(type: .system)
            var configuration = pillConfiguration(
                title: chip.title,
                symbol: chip.isLocked ? "lock.fill" : nil,
                prominent: chip.isSelected
            )
            configuration.imagePlacement = .trailing
            button.configuration = configuration
            button.tag = index
            button.accessibilityTraits = chip.isSelected ? [.button, .selected] : .button
            if chip.isLocked {
                button.accessibilityHint = "Part of ReplyRight Pro"
            }
            button.addTarget(self, action: #selector(tapChip(_:)), for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        chipIDs = chips.map(\.id)

        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
            scroller.heightAnchor.constraint(equalToConstant: 36),
        ])
        return scroller
    }

    private var chipIDs: [String] = []

    private func addButtons(primaryTitle: String?, secondaryTitle: String?) {
        guard primaryTitle != nil || secondaryTitle != nil else { return }
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        if let primaryTitle {
            let button = UIButton(type: .system)
            button.configuration = pillConfiguration(title: primaryTitle, symbol: nil, prominent: true)
            button.addTarget(self, action: #selector(tapPrimary), for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        if let secondaryTitle {
            let button = UIButton(type: .system)
            button.configuration = pillConfiguration(title: secondaryTitle, symbol: nil, prominent: false)
            button.addTarget(self, action: #selector(tapSecondary), for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        row.addArrangedSubview(UIView())
        content.addArrangedSubview(row)
    }

    @objc private func tapChip(_ sender: UIButton) {
        guard chipIDs.indices.contains(sender.tag) else { return }
        onChip?(chipIDs[sender.tag])
    }

    @objc private func tapRow(_ sender: UIControl) {
        onRow?(sender.tag)
    }

    @objc private func tapPrimary() { onPrimary?() }
    @objc private func tapSecondary() { onSecondary?() }
}

private extension UIView {
    static func spacer(height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
