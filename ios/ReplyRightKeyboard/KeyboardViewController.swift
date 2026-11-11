import ReplyRightCore
import UIKit

/// The keyboard's input view. Adopting `UIInputViewAudioFeedback` lets key presses play the system click.
final class KeyboardRootView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// The ReplyRight keyboard.
///
/// What it can see: only the text field being typed in, through `textDocumentProxy`.
/// It cannot read the conversation above the field in any app, and it does not try to.
///
/// What it sends: nothing while typing. Text leaves the device only when the user
/// taps a ReplyRight action (Reply or Rewrite), and then only the draft and any
/// conversation the user explicitly handed over. Nothing typed is stored.
///
/// Typing works without Full Access. AI features need it, because iOS requires
/// Full Access for any keyboard that uses the network.
final class KeyboardViewController: UIInputViewController {
    private enum Panel: Equatable {
        case reply
        case rewrite
        case saved
        case fullAccess
    }

    private enum PendingAction {
        case replies(regenerate: Bool)
        case rewrite(RefineAction)
    }

    /// What the panel is currently showing, so its buttons always mean one thing.
    private enum Screen: Equatable {
        case none
        case note
        case replyNeedsContext
        case replySetup
        case rewriteSetup
        case loading
        case results
        case failure
        case locked
    }

    private let store = SharedStore.shared
    private lazy var api = APIClient.standard(component: "keyboard", store: store)

    private var engine = TypingEngine()
    private var kind: KeyboardKind = .standard
    private var language: KeyboardLanguage = .english
    private var isSensitive = false
    private var lastTraitsSignature = ""

    private let toolbar = KeyboardToolbar()
    private let keysView = KeyboardKeysView()
    private let panelView = AssistPanelView()
    private var heightConstraint: NSLayoutConstraint?

    private var panel: Panel?
    private var screen: Screen = .none
    /// When the keyboard last changed the text itself, so its own edits are not mistaken for outside changes.
    private var lastOwnEdit: CFTimeInterval = 0
    private var selectedIntent: Intent = .natural
    private var seenReplies: [String] = []
    private var shownOptions: [Suggestion] = []
    private var resultsReplaceDraft = false
    private var lastAction: PendingAction?
    private var work: Task<Void, Never>?

    private static let toolbarHeight: CGFloat = 46

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let root = KeyboardRootView(frame: .zero, inputViewStyle: .keyboard)
        root.allowsSelfSizing = true
        inputView = root

        for subview in [toolbar, keysView, panelView] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: KeyboardViewController.toolbarHeight),

            keysView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            keysView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            keysView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            keysView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -3),

            panelView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            panelView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            panelView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        let height = root.heightAnchor.constraint(equalToConstant: preferredHeight(forWidth: UIScreen.main.bounds.width))
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        keysView.delegate = self
        keysView.calloutHost = root
        panelView.isHidden = true

        toolbar.onReply = { [weak self] in self?.openReply() }
        toolbar.onRewrite = { [weak self] in self?.openRewrite() }
        toolbar.onSaved = { [weak self] in self?.openSaved() }
        toolbar.onBackToKeys = { [weak self] in self?.closePanel() }

        panelView.onChip = { [weak self] id in self?.handleChip(id) }
        panelView.onPrimary = { [weak self] in self?.handlePrimary() }
        panelView.onSecondary = { [weak self] in self?.handleSecondary() }
        panelView.onRow = { [weak self] index in self?.handleRow(index) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        language = KeyboardLanguage.preferred(for: store.loadVoice())
        configureForField(force: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        work?.cancel()
        work = nil
        keysView.stopRepeating()
        keysView.hideCallout()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let width = view.bounds.width
        guard width > 0 else { return }
        let target = preferredHeight(forWidth: width)
        if heightConstraint?.constant != target {
            heightConstraint?.constant = target
        }
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        configureForField(force: false)
        // After the keyboard's own edits the engine already knows the right state, and the
        // host's reported context can lag a keystroke behind. Only outside changes re-evaluate shift.
        if CACurrentMediaTime() - lastOwnEdit > 0.3 {
            engine.refreshShift(before: textDocumentProxy.documentContextBeforeInput)
            refreshKeys()
        }
    }

    /// Rows are shorter in landscape, as on the system keyboard.
    private func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        let isLandscape = width > 480
        let rowHeight: CGFloat = isLandscape ? 38 : 54
        return KeyboardViewController.toolbarHeight + rowHeight * 4 + 3
    }

    // MARK: Field configuration

    /// Adapts to the field being edited: keyboard kind, capitalisation, appearance, and whether AI must stay off.
    private func configureForField(force: Bool) {
        let proxy = textDocumentProxy
        let keyboardType = proxy.keyboardType ?? .default
        let capitalization = proxy.autocapitalizationType ?? .sentences
        let returnType = proxy.returnKeyType ?? .default
        let secure = proxy.isSecureTextEntry ?? false
        let contentType = (proxy.textContentType ?? nil)?.rawValue
        let appearance = proxy.keyboardAppearance ?? .default

        // Rebuild only when the field's traits change, not on every keystroke.
        let signature = "\(keyboardType.rawValue)|\(capitalization.rawValue)|\(returnType.rawValue)|\(secure)|\(contentType ?? "")|\(appearance.rawValue)|\(needsInputModeSwitchKey)"
        guard force || signature != lastTraitsSignature else { return }
        lastTraitsSignature = signature

        var startsOnNumbers = false
        switch keyboardType {
        case .emailAddress: kind = .email
        case .URL: kind = .url
        case .webSearch: kind = .webSearch
        case .twitter: kind = .twitter
        case .numberPad, .asciiCapableNumberPad: kind = .numberPad
        case .decimalPad: kind = .decimalPad
        case .phonePad: kind = .phonePad
        case .numbersAndPunctuation:
            kind = .standard
            startsOnNumbers = true
        default: kind = .standard
        }

        switch capitalization {
        case .none: engine.capitalization = .none
        case .words: engine.capitalization = .words
        case .allCharacters: engine.capitalization = .allCharacters
        default: engine.capitalization = .sentences
        }
        if kind == .email || kind == .url {
            engine.capitalization = .none
        }
        engine.doubleSpaceInsertsPeriod = kind == .standard || kind == .twitter

        engine.reset(before: proxy.documentContextBeforeInput)
        if startsOnNumbers {
            _ = engine.tap(.page(.numbers), before: proxy.documentContextBeforeInput, now: CACurrentMediaTime())
        }

        view.overrideUserInterfaceStyle = appearance == .dark ? .dark : (appearance == .light ? .light : .unspecified)

        isSensitive = FieldSensitivity.isSensitive(isSecure: secure, contentType: contentType, kind: kind)
        if isSensitive, panel != nil {
            closePanel()
        }
        if panel == nil {
            toolbar.setMode(isSensitive ? .paused : .typing)
        }
        refreshKeys()
    }

    private func returnKeyTitle() -> (title: String?, isAction: Bool) {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .go: return ("go", true)
        case .google, .search, .yahoo: return ("search", true)
        case .join: return ("join", true)
        case .next: return ("next", true)
        case .route: return ("route", true)
        case .send: return ("send", true)
        case .done: return ("done", true)
        case .continue: return ("continue", true)
        case .emergencyCall: return ("call", true)
        default: return (nil, false)
        }
    }

    private func refreshKeys() {
        let layout = KeyboardLayout.make(
            page: engine.page,
            kind: kind,
            language: language,
            showsGlobe: needsInputModeSwitchKey
        )
        keysView.setLayout(layout)
        let returnKey = returnKeyTitle()
        let snapshot = engine
        keysView.update(
            KeyboardKeysView.Appearance(shift: engine.shift, returnTitle: returnKey.title, returnIsAction: returnKey.isAction),
            render: { snapshot.rendered($0) }
        )
    }

    // MARK: Typing

    private func apply(_ edits: [TypingEngine.Edit]) {
        let proxy = textDocumentProxy
        if !edits.isEmpty {
            lastOwnEdit = CACurrentMediaTime()
        }
        for edit in edits {
            switch edit {
            case .insert(let text):
                proxy.insertText(text)
            case .deleteBackward(let count):
                for _ in 0..<count {
                    proxy.deleteBackward()
                }
            }
        }
    }

    // MARK: Panels

    private func show(_ newPanel: Panel, title: String) {
        panel = newPanel
        keysView.stopRepeating()
        keysView.hideCallout()
        keysView.isHidden = true
        panelView.isHidden = false
        toolbar.setMode(.panel(title: title))
    }

    private func closePanel() {
        work?.cancel()
        work = nil
        panel = nil
        screen = .none
        shownOptions = []
        panelView.isHidden = true
        keysView.isHidden = false
        toolbar.setMode(isSensitive ? .paused : .typing)
        engine.refreshShift(before: textDocumentProxy.documentContextBeforeInput)
        refreshKeys()
    }

    private func currentDraft() -> DraftContext {
        DraftContext(
            before: textDocumentProxy.documentContextBeforeInput,
            after: textDocumentProxy.documentContextAfterInput
        )
    }

    /// A note with a single way back to the keys.
    private func showNote(title: String, detail: String) {
        screen = .note
        panelView.showMessage(title: title, detail: detail, primaryTitle: nil, secondaryTitle: "Back to keys")
    }

    /// AI features need the network, which iOS only allows a keyboard with Full Access.
    private func requireFullAccess() -> Bool {
        if hasFullAccess { return true }
        show(.fullAccess, title: "Full Access")
        showNote(
            title: "Suggestions need Full Access",
            detail: "iOS only lets a keyboard use the internet with Full Access. ReplyRight sends text only when you tap Reply or Rewrite, never your keystrokes, and typing works without it.\n\nTo turn it on: Settings, General, Keyboard, Keyboards, ReplyRight, Allow Full Access."
        )
        return false
    }

    // MARK: Reply

    private func openReply() {
        guard !isSensitive, requireFullAccess() else { return }
        seenReplies = []
        show(.reply, title: "Reply")
        renderReplySetup()
    }

    private func renderReplySetup() {
        guard let context = store.loadKeyboardContext() else {
            screen = .replyNeedsContext
            panelView.showMessage(
                title: "What are you replying to?",
                detail: "I can only see the box you're typing in, not the chat above it. Copy their message, then tap below. You can also share a screenshot or text to ReplyRight and choose \u{201C}Send to my keyboard\u{201D}.",
                primaryTitle: "Use copied message",
                secondaryTitle: "Back to keys"
            )
            return
        }

        let plan = store.loadService().plans.plan(for: store.lastKnownTier())
        let chips = Intent.quickChoices.map { intent in
            AssistPanelView.Chip(
                id: intent.rawValue,
                title: intent.shortTitle,
                isSelected: intent == selectedIntent,
                isLocked: !plan.includes(intent)
            )
        }
        screen = .replySetup
        panelView.showSetup(
            title: "Reply to this",
            quote: context.preview,
            chips: chips,
            primaryTitle: "Write replies",
            secondaryTitle: "Clear",
            footnote: currentDraft().isEmpty ? nil : "I'll use what you've typed as a starting point."
        )
    }

    /// Reads the clipboard only because the user tapped the button.
    private func useCopiedMessage() {
        guard let copied = UIPasteboard.general.string?.trimmed, !copied.isEmpty else {
            screen = .replyNeedsContext
            panelView.showMessage(
                title: "Nothing copied yet",
                detail: "Touch and hold their message, tap Copy, then come back and tap below.",
                primaryTitle: "Use copied message",
                secondaryTitle: "Back to keys"
            )
            return
        }
        store.saveKeyboardContext(KeyboardContext(text: copied, source: .clipboard))
        renderReplySetup()
    }

    private func writeReplies(regenerate: Bool) {
        guard let context = store.loadKeyboardContext() else {
            renderReplySetup()
            return
        }
        let draft = currentDraft()
        if !regenerate {
            seenReplies = []
        }
        let request = RepliesRequest(
            kind: .reply,
            conversation: context.text,
            intent: selectedIntent,
            draft: draft.text,
            avoid: regenerate ? seenReplies : [],
            voice: store.loadVoice().payload,
            crush: context.crush
        )
        lastAction = .replies(regenerate: regenerate)
        resultsReplaceDraft = !draft.isEmpty
        screen = .loading
        panelView.showLoading(Microcopy.pick(Microcopy.writing, seed: seenReplies.count))

        work?.cancel()
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let envelope = try await self.api.replies(request)
                guard !Task.isCancelled else { return }
                self.store.record(usage: envelope.usage, mode: envelope.mode)
                self.seenReplies = Array(
                    (self.seenReplies + envelope.result.replies.map(\.text)).suffix(RequestLimits.avoidReplies)
                )
                self.presentResults(
                    envelope.result.replies,
                    note: envelope.result.headsUp ?? envelope.result.note,
                    isDemo: envelope.mode == .demo,
                    moreTitle: "Three more"
                )
            } catch let error as APIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                self.presentFailure(error)
            } catch {
                self.presentFailure(.unexpectedResponse)
            }
        }
    }

    // MARK: Rewrite

    private func openRewrite() {
        guard !isSensitive, requireFullAccess() else { return }
        show(.rewrite, title: "Rewrite")
        let draft = currentDraft()
        guard !draft.isEmpty else {
            showNote(
                title: "Type something first",
                detail: "Write a rough version of what you want to say, then tap Rewrite. Rough is fine. That's the point."
            )
            return
        }
        let chips = RefineAction.toneActions.map { AssistPanelView.Chip(id: $0.rawValue, title: $0.title) }
        screen = .rewriteSetup
        panelView.showSetup(
            title: "Make it sound\u{2026}",
            quote: draft.text,
            chips: chips,
            primaryTitle: nil,
            secondaryTitle: nil,
            footnote: "Pick one and I'll offer three ways to say it."
        )
    }

    private func rewrite(_ action: RefineAction) {
        let draft = currentDraft()
        guard !draft.isEmpty else {
            openRewrite()
            return
        }
        let context = store.loadKeyboardContext()
        let request = RefineRequest(
            text: draft.text,
            action: action,
            count: 3,
            conversation: context?.text ?? "",
            voice: store.loadVoice().payload,
            crush: context?.crush
        )
        lastAction = .rewrite(action)
        resultsReplaceDraft = true
        screen = .loading
        panelView.showLoading(Microcopy.pick(Microcopy.refining, seed: draft.text.count))

        work?.cancel()
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let envelope = try await self.api.refine(request)
                guard !Task.isCancelled else { return }
                self.store.record(usage: envelope.usage, mode: envelope.mode)
                self.presentResults(
                    envelope.result.options,
                    note: envelope.result.note ?? "",
                    isDemo: envelope.mode == .demo,
                    moreTitle: "Another tone"
                )
            } catch let error as APIError {
                guard !Task.isCancelled, error != .cancelled else { return }
                self.presentFailure(error)
            } catch {
                self.presentFailure(.unexpectedResponse)
            }
        }
    }

    // MARK: Saved

    private func openSaved() {
        guard !isSensitive else { return }
        show(.saved, title: "Saved")
        let saved = store.loadSavedReplies()
        guard !saved.isEmpty else {
            showNote(
                title: "Nothing saved yet",
                detail: "Bookmark a reply in the ReplyRight app and it will be waiting here, ready to drop into any chat."
            )
            return
        }
        resultsReplaceDraft = false
        lastAction = nil
        shownOptions = saved.map { Suggestion(style: $0.style, text: $0.text, why: "") }
        screen = .results
        panelView.showResults(
            header: "Tap one to insert it.",
            rows: shownOptions.map { AssistPanelView.Row(badge: $0.style, text: $0.text) },
            secondaryTitle: nil,
            footnote: nil
        )
    }

    // MARK: Results and failures

    private func presentResults(_ options: [Suggestion], note: String, isDemo: Bool, moreTitle: String) {
        shownOptions = options
        guard !options.isEmpty else {
            showNote(
                title: "No suggestions this time",
                detail: note.isEmpty ? "Try a different tone, or share a little more of the conversation." : note
            )
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let header = isDemo
            ? "Demo mode: pre-written samples, not replies to your conversation."
            : (note.isEmpty ? "Tap one to use it. You can still edit before sending." : note)
        screen = .results
        panelView.showResults(
            header: header,
            rows: options.map { AssistPanelView.Row(badge: isDemo ? "Sample" : $0.style, text: $0.text) },
            secondaryTitle: moreTitle,
            footnote: nil
        )
    }

    private func presentFailure(_ error: APIError) {
        if let usage = error.usage {
            store.record(usage: usage, mode: nil)
        }
        if error.suggestsUpgrade {
            showNote(
                title: "That's as far as the free plan goes today",
                detail: "\(error.userMessage) Open ReplyRight to see plans."
            )
        } else {
            screen = .failure
            panelView.showMessage(
                title: "That didn't go through",
                detail: error.userMessage,
                primaryTitle: "Try again",
                secondaryTitle: "Back to keys"
            )
        }
    }

    // MARK: Panel actions

    private func handleChip(_ id: String) {
        switch screen {
        case .replySetup:
            guard let intent = Intent(rawValue: id) else { return }
            let plan = store.loadService().plans.plan(for: store.lastKnownTier())
            guard plan.includes(intent) else {
                screen = .locked
                panelView.showMessage(
                    title: "\u{201C}\(intent.title)\u{201D} is part of Pro",
                    detail: "Open ReplyRight to see plans. The other options here are yours to use.",
                    primaryTitle: nil,
                    secondaryTitle: "Back"
                )
                return
            }
            selectedIntent = intent
            renderReplySetup()
        case .rewriteSetup:
            guard let action = RefineAction(rawValue: id) else { return }
            rewrite(action)
        default:
            break
        }
    }

    private func handlePrimary() {
        switch screen {
        case .replyNeedsContext:
            useCopiedMessage()
        case .replySetup:
            writeReplies(regenerate: false)
        case .failure:
            retryLastAction()
        default:
            break
        }
    }

    private func handleSecondary() {
        switch screen {
        case .replySetup:
            // "Clear": forget the conversation that was shared with the keyboard.
            store.clearKeyboardContext()
            renderReplySetup()
        case .results:
            switch lastAction {
            case .replies:
                writeReplies(regenerate: true)
            case .rewrite:
                openRewrite()
            case .none:
                closePanel()
            }
        case .locked:
            renderReplySetup()
        default:
            closePanel()
        }
    }

    private func retryLastAction() {
        switch lastAction {
        case .replies(let regenerate):
            writeReplies(regenerate: regenerate)
        case .rewrite(let action):
            rewrite(action)
        case .none:
            closePanel()
        }
    }

    private func handleRow(_ index: Int) {
        guard screen == .results, shownOptions.indices.contains(index) else { return }
        let text = shownOptions[index].text
        let replace = resultsReplaceDraft
        closePanel()
        insert(text, replacingDraft: replace)
    }

    /// Puts a suggestion into the field. The user still has to send it themselves.
    private func insert(_ text: String, replacingDraft: Bool) {
        let proxy = textDocumentProxy
        lastOwnEdit = CACurrentMediaTime()
        guard replacingDraft else {
            proxy.insertText(text)
            finishInsert()
            return
        }
        let draft = currentDraft()
        if draft.cursorOffsetToEnd > 0 {
            proxy.adjustTextPosition(byCharacterOffset: draft.cursorOffsetToEnd)
        }
        // The host app applies the cursor move on its next turn of the run loop.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            let proxy = self.textDocumentProxy
            var remaining = draft.deletionCount
            while remaining > 0, let before = proxy.documentContextBeforeInput, !before.isEmpty {
                proxy.deleteBackward()
                remaining -= 1
            }
            proxy.insertText(text)
            self.finishInsert()
        }
    }

    private func finishInsert() {
        lastOwnEdit = CACurrentMediaTime()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        engine.refreshShift(before: textDocumentProxy.documentContextBeforeInput)
        refreshKeys()
    }
}

// MARK: - Keys

extension KeyboardViewController: KeyboardKeysViewDelegate {
    func keysViewDidPress(_ view: KeyboardKeysView) {
        UIDevice.current.playInputClick()
    }

    func keysView(_ view: KeyboardKeysView, didTap action: KeyAction) {
        let edits = engine.tap(action, before: textDocumentProxy.documentContextBeforeInput, now: CACurrentMediaTime())
        apply(edits)
        refreshKeys()
    }

    func keysView(_ view: KeyboardKeysView, didChoose text: String) {
        // The callout already shows the right case, so the text is inserted as chosen.
        // It goes through the engine as a character so shift and capitalisation stay consistent.
        lastOwnEdit = CACurrentMediaTime()
        let before = textDocumentProxy.documentContextBeforeInput
        textDocumentProxy.insertText(text)
        engine.refreshShift(before: (before ?? "") + text)
        refreshKeys()
    }

    func keysView(_ view: KeyboardKeysView, didCreateGlobe control: UIControl) {
        control.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
    }
}
