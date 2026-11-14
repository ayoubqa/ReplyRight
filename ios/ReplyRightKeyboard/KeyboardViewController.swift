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
///
/// Whose profile is used as context is always the user's choice, made in the
/// Reply panel or in the app. Only the parts of a profile the user allowed are sent.
///
/// What it tells the app: with Full Access, a check-in (when it last opened, its
/// version) and daily counts of suggestions shown and inserted. Numbers and
/// dates only, never text. Without Full Access it cannot write anything the app
/// reads; the only signal then is the test sentence it types when asked.
final class KeyboardViewController: UIInputViewController {
    private enum Panel: Equatable {
        case reply
        case rewrite
        case saved
        case fullAccess
        case status
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
        case status
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
    /// The profile chosen as context for replies, if any. Nil means "no one in particular".
    private var selectedPersonID: UUID?
    /// True once the user picked a person (or no one) in this session, so the app's default no longer applies.
    private var personWasChosen = false
    /// A tone adjustment applied to the next set of replies.
    private var adjustment: RefineAction?
    private var seenReplies: [String] = []
    private var shownOptions: [Suggestion] = []
    private var resultsReplaceDraft = false
    private var lastAction: PendingAction?
    private var work: Task<Void, Never>?
    /// True when the suggestions on screen came from live AI, so inserting one
    /// counts as using a suggestion. Demo samples and saved lines do not count.
    private var shownAreLive = false
    /// Copied text offered as "what they said" after the user tapped Reply.
    /// Held in memory only; it is saved for later only if the user taps "Use copied message".
    private var clipboardCandidate: KeyboardContext?
    /// The clipboard's change count when the user said "Not this", so the same
    /// copied text is not offered again.
    private var declinedClipboardChange: Int?

    private static let toolbarHeight: CGFloat = 46
    /// Where the keyboard remembers its own language choice. This is the
    /// extension's private storage, so it works without Full Access.
    private static let languageKey = "rr.keyboard.language"

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
        toolbar.onLanguage = { [weak self] in self?.cycleLanguage() }
        toolbar.onBackToKeys = { [weak self] in self?.closePanel() }
        toolbar.onStatus = { [weak self] in self?.openStatus() }

        panelView.onChip = { [weak self] id in self?.handleChip(id) }
        panelView.onPersonChip = { [weak self] id in self?.handlePersonChip(id) }
        panelView.onPrimary = { [weak self] in self?.handlePrimary() }
        panelView.onSecondary = { [weak self] in self?.handleSecondary() }
        panelView.onRow = { [weak self] index in self?.handleRow(index) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let saved = UserDefaults.standard.string(forKey: KeyboardViewController.languageKey),
           let chosen = KeyboardLanguage(rawValue: saved) {
            language = chosen
        } else {
            language = KeyboardLanguage.preferred(for: store.loadVoice())
        }
        toolbar.setLanguage(code: language.shortCode, name: language.title)
        configureForField(force: true)
        checkIn()
    }

    /// Tells the app the keyboard opened with Full Access. Without it the shared
    /// container is closed to writes, so nothing is written and the app keeps
    /// showing what it last knew. At most one write every ten minutes.
    private func checkIn() {
        guard hasFullAccess else { return }
        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            let now = Date()
            if let last = store.loadKeyboardCheckIn(), last.hasFullAccess, now.timeIntervalSince(last.lastSeen) < 600 {
                return
            }
            store.saveKeyboardCheckIn(KeyboardCheckIn(lastSeen: now, hasFullAccess: true, keyboardVersion: AppConfig.appVersion))
        }
    }

    /// Adds to the on-device activity counts. Needs Full Access, which every
    /// counted action already requires; without it the write quietly fails.
    private func recordActivity(_ event: ProductActivity.Event) {
        guard hasFullAccess else { return }
        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            _ = store.recordActivity(event)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        work?.cancel()
        work = nil
        clipboardCandidate = nil
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

    /// Switches the keys to the next language and remembers the choice.
    private func cycleLanguage() {
        language = language.next
        UserDefaults.standard.set(language.rawValue, forKey: KeyboardViewController.languageKey)
        toolbar.setLanguage(code: language.shortCode, name: language.title)
        UISelectionFeedbackGenerator().selectionChanged()
        refreshKeys()
        UIAccessibility.post(notification: .announcement, argument: language.title)
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
        let wasShowingKeys = panel == nil
        panel = newPanel
        keysView.stopRepeating()
        keysView.hideCallout()
        toolbar.setMode(.panel(title: title))
        if wasShowingKeys {
            crossfade(from: keysView, to: panelView)
        }
    }

    private func closePanel() {
        work?.cancel()
        work = nil
        let wasShowingPanel = panel != nil
        panel = nil
        screen = .none
        shownOptions = []
        shownAreLive = false
        adjustment = nil
        clipboardCandidate = nil
        toolbar.setMode(isSensitive ? .paused : .typing)
        if wasShowingPanel {
            crossfade(from: panelView, to: keysView)
        } else {
            panelView.isHidden = true
            keysView.isHidden = false
        }
        engine.refreshShift(before: textDocumentProxy.documentContextBeforeInput)
        refreshKeys()
    }

    /// Swaps the keys and the panel with a short fade, so the keyboard never
    /// jumps. With Reduce Motion on, the swap is immediate.
    private func crossfade(from outgoing: UIView, to incoming: UIView) {
        incoming.layer.removeAllAnimations()
        outgoing.layer.removeAllAnimations()
        guard !UIAccessibility.isReduceMotionEnabled else {
            outgoing.isHidden = true
            outgoing.alpha = 1
            incoming.alpha = 1
            incoming.isHidden = false
            return
        }
        incoming.alpha = 0
        incoming.isHidden = false
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction]) {
            outgoing.alpha = 0
            incoming.alpha = 1
        } completion: { [weak self] _ in
            // The state may have changed again while the fade ran. Show whatever is current.
            guard let self else { return }
            let showsPanel = self.panel != nil
            self.panelView.isHidden = !showsPanel
            self.keysView.isHidden = showsPanel
            self.panelView.alpha = 1
            self.keysView.alpha = 1
        }
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
            detail: "iOS only lets a keyboard use the internet with Full Access. ReplyRight sends text only when you tap Reply or Rewrite, never your keystrokes, and typing works without it.\n\nTo turn it on: Settings, General, Keyboard, Keyboards, ReplyRight, Allow Full Access. The Keyboard tab in the ReplyRight app walks you through it."
        )
        return false
    }

    // MARK: Reply

    private func openReply() {
        guard !isSensitive, requireFullAccess() else { return }
        seenReplies = []
        adjustment = nil
        show(.reply, title: "Reply")
        offerCopiedMessage()
        renderReplySetup()
    }

    /// When nothing was handed over yet and the user has copied something that
    /// reads like a message, offer it straight away instead of asking them to
    /// tap "Use copied message". Read only because the user tapped Reply, shown
    /// back before anything is sent, and kept in memory only.
    private func offerCopiedMessage() {
        guard store.loadKeyboardContext() == nil, clipboardCandidate == nil else { return }
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings, pasteboard.changeCount != declinedClipboardChange else { return }
        guard let copied = pasteboard.string?.trimmed, CopiedText.looksLikeMessage(copied) else { return }
        clipboardCandidate = KeyboardContext(text: copied, source: .clipboard)
    }

    /// What the reply is to: what was handed over, otherwise the copied text on offer.
    private func replyContext() -> KeyboardContext? {
        store.loadKeyboardContext() ?? clipboardCandidate
    }

    /// The profile used as context: what the user picked here, otherwise the
    /// one chosen in the app, otherwise the one that came with the shared conversation.
    private func activePerson(context: KeyboardContext?) -> CrushProfile? {
        let people = store.loadPeople()
        if personWasChosen {
            return people.first { $0.id == selectedPersonID }
        }
        let fallback = store.loadSettings().keyboardCrushID ?? context?.crushID
        return people.first { $0.id == fallback }
    }

    private func renderReplySetup() {
        guard let context = replyContext() else {
            screen = .replyNeedsContext
            let hasText = !currentDraft().isEmpty
            panelView.showMessage(
                title: "What are you replying to?",
                detail: "I can only see the box you're typing in, not the chat above it. Copy their message and tap below"
                    + (hasText ? ", or use the text that's in the box right now." : ".")
                    + " You can also share a screenshot to ReplyRight and choose \u{201C}Send to my keyboard\u{201D}.",
                primaryTitle: "Use copied message",
                secondaryTitle: hasText ? "Use the text in the box" : "Back to keys"
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

        // Whose profile to use. Shown only when the user has saved someone.
        let people = store.loadPeople().filter { !$0.alias.trimmed.isEmpty }
        let active = activePerson(context: context)
        var personChips: [AssistPanelView.Chip] = []
        if !people.isEmpty {
            personChips.append(AssistPanelView.Chip(id: "none", title: "No one", isSelected: active == nil))
            personChips.append(contentsOf: people.prefix(8).map { person in
                AssistPanelView.Chip(id: person.id.uuidString, title: person.alias, isSelected: person.id == active?.id)
            })
        }

        var notes: [String] = []
        let isFromClipboard = store.loadKeyboardContext() == nil
        if isFromClipboard {
            notes.append("This is what you copied. Tap Not this if it's something else.")
        }
        if !currentDraft().isEmpty {
            notes.append("I'll use what you've typed as a starting point.")
        }
        if let active {
            notes.append("\(active.alias)'s profile is sent with this request, only the parts you allowed.")
        }

        screen = .replySetup
        panelView.showSetup(
            title: "Reply to this",
            quote: context.preview,
            chips: chips,
            people: personChips,
            primaryTitle: "Write replies",
            secondaryTitle: isFromClipboard ? "Not this" : "Clear",
            footnote: notes.isEmpty ? nil : notes.joined(separator: " ")
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
        clipboardCandidate = nil
        store.saveKeyboardContext(KeyboardContext(text: copied, source: .clipboard))
        renderReplySetup()
    }

    /// Takes the text in the field as what the other person said, then empties
    /// the field so the user can write their answer. Only on an explicit tap.
    private func useTextInBox() {
        let draft = currentDraft()
        let text = draft.text.trimmed
        guard !text.isEmpty else {
            renderReplySetup()
            return
        }
        store.saveKeyboardContext(KeyboardContext(text: text, source: .clipboard))
        clearField(draft) { [weak self] in
            self?.renderReplySetup()
        }
    }

    /// Removes everything in the field. The host app applies a cursor move on
    /// its next turn of the run loop, so the deletion waits a moment.
    private func clearField(_ draft: DraftContext, then: @escaping () -> Void) {
        let proxy = textDocumentProxy
        lastOwnEdit = CACurrentMediaTime()
        if draft.cursorOffsetToEnd > 0 {
            proxy.adjustTextPosition(byCharacterOffset: draft.cursorOffsetToEnd)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self else { return }
            let proxy = self.textDocumentProxy
            var remaining = draft.deletionCount
            while remaining > 0, let before = proxy.documentContextBeforeInput, !before.isEmpty {
                proxy.deleteBackward()
                remaining -= 1
            }
            self.lastOwnEdit = CACurrentMediaTime()
            then()
        }
    }

    private func writeReplies(regenerate: Bool) {
        guard let context = replyContext() else {
            renderReplySetup()
            return
        }
        let draft = currentDraft()
        if !regenerate {
            seenReplies = []
        }
        let person = activePerson(context: context)
        // When the user chose "No one", nothing about anyone is sent, including
        // what came along with a conversation shared from the app.
        let crush: CrushPayload? = personWasChosen ? person?.payload : (person?.payload ?? context.crush)
        let request = RepliesRequest(
            kind: .reply,
            conversation: context.text,
            intent: selectedIntent,
            instruction: adjustment.map { "Make these \($0.tweakTitle.lowercased())." } ?? "",
            draft: draft.text,
            avoid: regenerate ? seenReplies : [],
            voice: store.loadVoice().payload,
            crush: crush
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
                if envelope.mode != .demo, !envelope.result.replies.isEmpty {
                    self.recordActivity(.suggestionsShown(.keyboard))
                }
                self.presentResults(
                    envelope.result.replies,
                    note: envelope.result.headsUp ?? envelope.result.note,
                    isDemo: envelope.mode == .demo,
                    moreTitle: "Three more",
                    allowsAdjusting: true
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
        let actions = RefineAction.keyboardActions + [.moreRomantic, .askQuestion]
        let chips = actions.map { AssistPanelView.Chip(id: $0.rawValue, title: $0.tweakTitle) }
        screen = .rewriteSetup
        panelView.showSetup(
            title: "Make it\u{2026}",
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
                if envelope.mode != .demo, !envelope.result.options.isEmpty {
                    self.recordActivity(.suggestionsShown(.keyboard))
                }
                self.presentResults(
                    envelope.result.options,
                    note: envelope.result.note ?? "",
                    isDemo: envelope.mode == .demo,
                    moreTitle: "Another way",
                    allowsAdjusting: false
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
            if hasFullAccess {
                showNote(
                    title: "Nothing saved yet",
                    detail: "Bookmark a reply in the ReplyRight app and it will be waiting here, ready to drop into any chat."
                )
            } else {
                showNote(
                    title: "Saved lines live in the app",
                    detail: "Lines you bookmark in ReplyRight show up here. Without Full Access, iOS may not let the keyboard read them, so if you've saved some and see none, turn on Full Access in Settings, General, Keyboard, Keyboards, ReplyRight."
                )
            }
            return
        }
        resultsReplaceDraft = false
        shownAreLive = false
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

    // MARK: Status

    /// What the keyboard knows about itself, and a way to show the app it works.
    private func openStatus() {
        show(.status, title: "ReplyRight Keyboard")
        screen = .status
        let detail: String
        if hasFullAccess {
            detail = "Full Access is on, so Reply and Rewrite can write suggestions. Text leaves your iPhone only when you tap one of them, never while you type."
        } else {
            detail = "Full Access is off. Typing works and nothing leaves your iPhone. Reply and Rewrite need Full Access, because iOS only lets a keyboard reach the internet with it."
        }
        let canType = !isSensitive
        panelView.showMessage(
            title: hasFullAccess ? "Ready to help" : "Typing only",
            detail: detail + (canType
                ? "\n\nTesting setup? Open the Keyboard tab in ReplyRight, tap its test box, then tap below. It types one short line you can delete."
                : ""),
            primaryTitle: canType ? "Type a test message" : nil,
            secondaryTitle: "Back to keys"
        )
    }

    /// Types the fixed test sentence. ReplyRight's test field recognises it,
    /// which is how the app learns the keyboard works even without Full Access.
    private func typeTestMessage() {
        guard !isSensitive else { return }
        let phrase = KeyboardHandshake.phrase(hasFullAccess: hasFullAccess)
        closePanel()
        insert(phrase, replacingDraft: false)
    }

    // MARK: Results and failures

    private func presentResults(
        _ options: [Suggestion],
        note: String,
        isDemo: Bool,
        moreTitle: String,
        allowsAdjusting: Bool
    ) {
        shownOptions = options
        shownAreLive = !isDemo
        guard !options.isEmpty else {
            showNote(
                title: "No suggestions this time",
                detail: note.isEmpty ? "Try a different tone, or share a little more of the conversation." : note
            )
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Demo samples are always labelled as such, never passed off as written for this chat.
        let header = isDemo
            ? "Demo mode: pre-written samples, not replies to your conversation."
            : (note.isEmpty ? "Tap one to use it. You can still edit before sending." : note)
        let chips: [AssistPanelView.Chip] = allowsAdjusting
            ? RefineAction.keyboardActions.map {
                AssistPanelView.Chip(id: $0.rawValue, title: $0.tweakTitle, isSelected: $0 == adjustment)
            }
            : []
        screen = .results
        panelView.showResults(
            header: header,
            rows: options.map { AssistPanelView.Row(badge: isDemo ? "Sample" : $0.style, text: $0.text, isSample: isDemo) },
            chips: chips,
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
            return
        }
        var detail = error.userMessage
        if error.isConnectionProblem {
            detail += " Typing still works as usual."
            // In development builds, say what to check. A release build shows only the plain message.
            if AppConfig.allowsEnvironmentSwitching,
               let hint = error.setupHint(for: AppConfig.backend(settings: store.loadSettings())) {
                detail += "\n\n" + hint
            }
        }
        screen = .failure
        panelView.showMessage(
            title: error.title,
            detail: detail,
            primaryTitle: error.isRetryable ? "Try again" : nil,
            secondaryTitle: "Back to keys"
        )
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
        case .results:
            // "Adjust": ask for three new replies in that direction. Tapping the
            // selected adjustment again goes back to plain replies.
            guard case .replies = lastAction, let action = RefineAction(rawValue: id) else { return }
            adjustment = adjustment == action ? nil : action
            writeReplies(regenerate: false)
        default:
            break
        }
    }

    /// The user picked whose profile to use as context, or no one.
    private func handlePersonChip(_ id: String) {
        guard screen == .replySetup else { return }
        personWasChosen = true
        selectedPersonID = UUID(uuidString: id)
        // Remember the choice for next time. This needs Full Access, which Reply already requires.
        var settings = store.loadSettings()
        if settings.keyboardCrushID != selectedPersonID {
            settings.keyboardCrushID = selectedPersonID
            store.saveSettings(settings)
        }
        UISelectionFeedbackGenerator().selectionChanged()
        renderReplySetup()
    }

    private func handlePrimary() {
        switch screen {
        case .replyNeedsContext:
            useCopiedMessage()
        case .replySetup:
            writeReplies(regenerate: false)
        case .failure:
            retryLastAction()
        case .status:
            typeTestMessage()
        default:
            break
        }
    }

    private func handleSecondary() {
        switch screen {
        case .replyNeedsContext:
            if currentDraft().isEmpty {
                closePanel()
            } else {
                useTextInBox()
            }
        case .replySetup:
            if store.loadKeyboardContext() == nil, clipboardCandidate != nil {
                // "Not this": the copied text was something else. Don't offer it again.
                clipboardCandidate = nil
                declinedClipboardChange = UIPasteboard.general.changeCount
            } else {
                // "Clear": forget the conversation that was shared with the keyboard.
                store.clearKeyboardContext()
            }
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
        if shownAreLive {
            recordActivity(.suggestionUsed(.keyboard))
        }
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
