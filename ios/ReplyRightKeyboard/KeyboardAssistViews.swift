import ReplyRightCore
import UIKit

// The ReplyRight bar above the keys, and the panel that replaces the keys
// while the user is choosing or reading suggestions.

/// A capsule button. The prominent one is filled in the voice colour; the
/// others are outlines, so there is only ever one obvious thing to tap.
private func pillConfiguration(title: String?, symbol: String?, prominent: Bool) -> UIButton.Configuration {
    var configuration = UIButton.Configuration.filled()
    configuration.title = title
    if let symbol {
        configuration.image = KeyboardTheme.symbol(symbol, size: 13, weight: .semibold)
        configuration.imagePadding = 5
    }
    configuration.cornerStyle = .capsule
    // About 34 points tall to look at. The touch area is 44 by 44 (`HitAreaButton`).
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    if prominent {
        configuration.baseBackgroundColor = KeyboardTheme.accent
        configuration.baseForegroundColor = KeyboardTheme.onAccent
    } else {
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = KeyboardTheme.text
        configuration.background.strokeColor = KeyboardTheme.line
        configuration.background.strokeWidth = 1
    }
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
        var outgoing = incoming
        outgoing.font = KeyboardTheme.font(14, weight: .semibold)
        return outgoing
    }
    return configuration
}

/// A button whose touch area is at least 44 by 44 points, centred on what is
/// drawn, so a pill can look compact and still be easy to hit. The parent view
/// must leave room around it: touches outside the parent never reach it.
final class HitAreaButton: UIButton {
    static let minimumSide: CGFloat = 44

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden, isUserInteractionEnabled, alpha > 0.01 else { return false }
        let dx = max(0, (HitAreaButton.minimumSide - bounds.width) / 2)
        let dy = max(0, (HitAreaButton.minimumSide - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }
}

/// The bar above the keys. It is the only place AI features start from.
///
/// Every control has a touch area of at least 44 by 44 points: the bar is 46
/// tall, pills are about 34 tall with their touch area extended vertically,
/// icon-only and short buttons are at least 44 wide, and the mark sits in a
/// 44 by 44 control.
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
    var onLanguage: (() -> Void)?
    var onBackToKeys: (() -> Void)?
    /// The mark was tapped: show what the keyboard knows about its setup.
    var onStatus: (() -> Void)?

    private let stack = UIStackView()
    private let brand = KeyboardBrandMark(side: 26)
    /// A larger touch area around the mark.
    private let brandControl = UIControl()
    private let replyButton = HitAreaButton(type: .system)
    private let rewriteButton = HitAreaButton(type: .system)
    private let savedButton = HitAreaButton(type: .system)
    private let languageButton = HitAreaButton(type: .system)
    private let backButton = HitAreaButton(type: .system)
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

        replyButton.configuration = pillConfiguration(title: "Reply", symbol: "quote.opening", prominent: true)
        replyButton.addTarget(self, action: #selector(tapReply), for: .touchUpInside)
        replyButton.accessibilityHint = "Suggests replies to a message you copied or shared"

        rewriteButton.configuration = pillConfiguration(title: "Rewrite", symbol: "pencil", prominent: false)
        rewriteButton.addTarget(self, action: #selector(tapRewrite), for: .touchUpInside)
        rewriteButton.accessibilityHint = "Rewrites what you have typed"

        savedButton.configuration = pillConfiguration(title: nil, symbol: "bookmark", prominent: false)
        savedButton.addTarget(self, action: #selector(tapSaved), for: .touchUpInside)
        savedButton.accessibilityLabel = "Saved replies"

        languageButton.configuration = pillConfiguration(title: "EN", symbol: nil, prominent: false)
        languageButton.addTarget(self, action: #selector(tapLanguage), for: .touchUpInside)
        languageButton.accessibilityHint = "Switches the keyboard language"

        backButton.configuration = pillConfiguration(title: "Keys", symbol: "keyboard", prominent: false)
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)
        backButton.accessibilityLabel = "Back to the keyboard"

        titleLabel.font = KeyboardTheme.font(14, weight: .semibold)
        titleLabel.textColor = KeyboardTheme.textSecondary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        brand.translatesAutoresizingMaskIntoConstraints = false
        brandControl.addSubview(brand)
        brandControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            brandControl.widthAnchor.constraint(equalToConstant: HitAreaButton.minimumSide),
            brandControl.heightAnchor.constraint(equalToConstant: HitAreaButton.minimumSide),
            // Short buttons are drawn at least as wide as their touch area, so
            // the touch area never has to reach past the edge of the bar.
            savedButton.widthAnchor.constraint(greaterThanOrEqualToConstant: HitAreaButton.minimumSide),
            languageButton.widthAnchor.constraint(greaterThanOrEqualToConstant: HitAreaButton.minimumSide),
            brand.centerXAnchor.constraint(equalTo: brandControl.centerXAnchor),
            brand.centerYAnchor.constraint(equalTo: brandControl.centerYAnchor),
        ])
        brandControl.addTarget(self, action: #selector(tapStatus), for: .touchUpInside)
        brandControl.isAccessibilityElement = true
        brandControl.accessibilityTraits = .button
        brandControl.accessibilityLabel = "ReplyRight Keyboard"
        brandControl.accessibilityHint = "Shows whether Full Access is on and lets you test setup"

        for view in [brandControl, backButton, replyButton, rewriteButton, titleLabel, spacer, languageButton, savedButton] as [UIView] {
            stack.addArrangedSubview(view)
        }
        setMode(.typing)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows which language the keys are in, for example "EN" or "ES".
    func setLanguage(code: String, name: String) {
        var configuration = languageButton.configuration
        configuration?.title = code
        languageButton.configuration = configuration
        languageButton.accessibilityLabel = "Keyboard language: \(name)"
    }

    func setMode(_ mode: Mode) {
        switch mode {
        case .typing:
            brandControl.isHidden = false
            backButton.isHidden = true
            replyButton.isHidden = false
            rewriteButton.isHidden = false
            savedButton.isHidden = false
            languageButton.isHidden = false
            titleLabel.isHidden = true
        case .paused:
            brandControl.isHidden = false
            backButton.isHidden = true
            replyButton.isHidden = true
            rewriteButton.isHidden = true
            savedButton.isHidden = true
            languageButton.isHidden = false
            titleLabel.isHidden = false
            titleLabel.text = "ReplyRight is paused in this field"
        case .panel(let title):
            brandControl.isHidden = true
            backButton.isHidden = false
            replyButton.isHidden = true
            rewriteButton.isHidden = true
            savedButton.isHidden = true
            languageButton.isHidden = true
            titleLabel.isHidden = false
            titleLabel.text = title
        }
    }

    @objc private func tapReply() { onReply?() }
    @objc private func tapRewrite() { onRewrite?() }
    @objc private func tapSaved() { onSaved?() }
    @objc private func tapLanguage() { onLanguage?() }
    @objc private func tapBack() { onBackToKeys?() }
    @objc private func tapStatus() { onStatus?() }
}

/// A tappable suggestion: the approach it takes, and the message.
private final class SuggestionRow: UIControl {
    private let badge = UILabel()
    private let message = UILabel()

    init(badgeText: String, text: String, isSample: Bool) {
        super.init(frame: .zero)
        backgroundColor = KeyboardTheme.surfaceRaised
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        badge.text = badgeText
        badge.font = KeyboardTheme.font(12, weight: .semibold)
        badge.textColor = isSample ? KeyboardTheme.highlight : KeyboardTheme.accent
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
        var isSample = false
    }

    /// A chip in the main row: what the reply should do, how to rewrite, how to adjust.
    var onChip: ((String) -> Void)?
    /// A chip in the "With" row: whose profile to use as context.
    var onPersonChip: ((String) -> Void)?
    var onPrimary: (() -> Void)?
    var onSecondary: (() -> Void)?
    var onRow: ((Int) -> Void)?

    private let scroll = UIScrollView()
    private let content = UIStackView()
    private var chipIDs: [String] = []
    private var personChipIDs: [String] = []

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
        people: [Chip] = [],
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
            chipIDs = chips.map(\.id)
            content.addArrangedSubview(makeChips(chips, label: nil, action: #selector(tapChip(_:))))
        }
        if !people.isEmpty {
            personChipIDs = people.map(\.id)
            content.addArrangedSubview(makeChips(people, label: "With", action: #selector(tapPersonChip(_:))))
        }
        if let footnote {
            content.addArrangedSubview(makeBody(footnote, small: true))
        }
        addButtons(primaryTitle: primaryTitle, secondaryTitle: secondaryTitle)
        fadeIn()
    }

    /// The mark with its cursor blinking, and a line about what is happening.
    func showLoading(_ line: String) {
        reset()
        let mark = KeyboardBrandMark(side: 38)
        mark.isWriting = true
        let label = UILabel()
        label.text = line
        label.font = KeyboardTheme.font(16)
        label.textColor = KeyboardTheme.textSecondary
        label.numberOfLines = 2
        let holder = UIStackView(arrangedSubviews: [mark, label])
        holder.axis = .horizontal
        holder.alignment = .center
        holder.spacing = 10
        content.addArrangedSubview(UIView.spacer(height: 22))
        content.addArrangedSubview(holder)
        UIAccessibility.post(notification: .announcement, argument: line)
        fadeIn()
    }

    func showResults(header: String?, rows: [Row], chips: [Chip] = [], secondaryTitle: String?, footnote: String?) {
        reset()
        if let header, !header.isEmpty {
            content.addArrangedSubview(makeBody(header, small: true))
        }
        for (index, row) in rows.enumerated() {
            let control = SuggestionRow(badgeText: row.badge, text: row.text, isSample: row.isSample)
            control.tag = index
            control.addTarget(self, action: #selector(tapRow(_:)), for: .touchUpInside)
            content.addArrangedSubview(control)
        }
        if !chips.isEmpty {
            chipIDs = chips.map(\.id)
            content.addArrangedSubview(makeChips(chips, label: "Adjust", action: #selector(tapChip(_:))))
        }
        if let footnote {
            content.addArrangedSubview(makeBody(footnote, small: true))
        }
        addButtons(primaryTitle: nil, secondaryTitle: secondaryTitle)
        fadeIn()
    }

    func showMessage(title: String, detail: String, primaryTitle: String?, secondaryTitle: String?) {
        reset()
        content.addArrangedSubview(UIView.spacer(height: 6))
        content.addArrangedSubview(makeTitle(title))
        content.addArrangedSubview(makeBody(detail, small: false))
        addButtons(primaryTitle: primaryTitle, secondaryTitle: secondaryTitle)
        fadeIn()
    }

    // MARK: Building blocks

    private func reset() {
        for view in content.arrangedSubviews {
            content.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        chipIDs = []
        personChipIDs = []
        scroll.setContentOffset(.zero, animated: false)
    }

    /// New content arrives with a short fade, so the panel never jumps.
    private func fadeIn() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            content.alpha = 1
            return
        }
        content.alpha = 0
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.content.alpha = 1
        }
    }

    private func makeTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = KeyboardTheme.serif(18)
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
        box.layer.cornerRadius = 14
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

    /// A row of chips that scrolls sideways, with an optional quiet label in front.
    private func makeChips(_ chips: [Chip], label: String?, action: Selector) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        if let label {
            let caption = UILabel()
            caption.text = label
            caption.font = KeyboardTheme.font(12, weight: .medium)
            caption.textColor = KeyboardTheme.textTertiary
            caption.isAccessibilityElement = false
            row.addArrangedSubview(caption)
        }

        for (index, chip) in chips.enumerated() {
            let button = HitAreaButton(type: .system)
            var configuration = pillConfiguration(
                title: chip.title,
                symbol: chip.isLocked ? "lock.fill" : nil,
                prominent: chip.isSelected
            )
            configuration.imagePlacement = .trailing
            button.configuration = configuration
            button.tag = index
            button.accessibilityTraits = chip.isSelected ? [.button, .selected] : .button
            if let label {
                button.accessibilityLabel = "\(label) \(chip.title)"
            }
            if chip.isLocked {
                button.accessibilityHint = "Part of ReplyRight Pro"
            }
            button.addTarget(self, action: action, for: .touchUpInside)
            row.addArrangedSubview(button)
        }

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
            // Tall enough for each chip's 44-point touch area.
            scroller.heightAnchor.constraint(equalToConstant: HitAreaButton.minimumSide),
        ])
        return scroller
    }

    private func addButtons(primaryTitle: String?, secondaryTitle: String?) {
        guard primaryTitle != nil || secondaryTitle != nil else { return }
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        // Tall enough for each button's 44-point touch area.
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: HitAreaButton.minimumSide).isActive = true
        if let primaryTitle {
            let button = HitAreaButton(type: .system)
            button.configuration = pillConfiguration(title: primaryTitle, symbol: nil, prominent: true)
            button.addTarget(self, action: #selector(tapPrimary), for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        if let secondaryTitle {
            let button = HitAreaButton(type: .system)
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

    @objc private func tapPersonChip(_ sender: UIButton) {
        guard personChipIDs.indices.contains(sender.tag) else { return }
        onPersonChip?(personChipIDs[sender.tag])
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
