import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// Step three: three genuinely different ways to say it, each with its reason.
/// The user adjusts, edits, copies and sends. ReplyRight never sends anything.
struct RepliesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var compose = app.compose

        ScreenScroll {
            switch compose.repliesState {
            case .idle, .loading:
                ThinkingView(lines: Microcopy.writing)
                    .padding(.top, RRSpace.xl)

            case .failed(let message):
                FailureNote(error: compose.failure, message: message) {
                    compose.startReplies(app: app)
                }
                .padding(.top, RRSpace.l)

            case .loaded:
                header

                if let headsUp = compose.headsUp, !headsUp.isEmpty {
                    HeadsUpNote(headsUp)
                }

                if compose.options.isEmpty {
                    noOptions
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach($compose.options) { $option in
                            ReplyCard(
                                option: $option,
                                isDemo: compose.mode == .demo,
                                isRefining: compose.refiningID == option.id,
                                intent: compose.intent,
                                crushID: compose.crush?.id,
                                onRefine: { action in
                                    compose.refine(optionID: option.id, action: action, app: app)
                                }
                            )
                        }
                        Rule()
                    }

                    if let notice = compose.refineNotice, !notice.isEmpty {
                        MarginNote(notice)
                            .transition(.opacity)
                    }

                    LearnFromEditsPrompt(options: compose.options)

                    footer
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if compose.repliesState == .loaded, !compose.options.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.save(compose.makeSession())
                    } label: {
                        Image(systemName: compose.savedSessionID == nil ? "bookmark" : "bookmark.fill")
                    }
                    .accessibilityLabel(compose.savedSessionID == nil ? "Save this conversation" : "Conversation saved")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            Eyebrow(app.compose.intent.title)
            Text(app.compose.note.isEmpty ? "Here are three ways to say it." : app.compose.note)
                .rrText(.title)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let mode = app.compose.mode {
                ProvenanceLabel(mode)
                    .padding(.top, RRSpace.xxs)
                    .accessibilityIdentifier("replies-provenance")
            }
        }
    }

    private var noOptions: some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            Text("No suggestions this time.")
                .rrText(.headline)
                .foregroundStyle(Color.rrText)
            Text("Sometimes the kindest move isn't another message. If you'd like to talk it through, the coach is here.")
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: RRSpace.s) {
                Button("Change the goal") {
                    app.homePath.removeLast()
                }
                .buttonStyle(.rrSecondaryCompact)
                Button("Talk to the coach") {
                    app.askCoach(conversation: app.compose.conversationText, crushID: app.compose.crush?.id)
                }
                .buttonStyle(.rrQuiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            HStack(spacing: RRSpace.xs) {
                Button {
                    Haptics.tap()
                    app.compose.startReplies(app: app, regenerate: true)
                } label: {
                    Label("Three more", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.rrSecondaryCompact)
                .accessibilityIdentifier("replies-regenerate")

                Button {
                    app.homePath.removeLast()
                } label: {
                    Label("Change the goal", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.rrSecondaryCompact)
            }

            VStack(spacing: 0) {
                Rule()
                Button {
                    app.handToKeyboard(app.compose.conversationText, crush: app.compose.crush)
                } label: {
                    NavigationRow(
                        title: "Use this chat in my keyboard",
                        subtitle: "Pull up replies right where you type.",
                        systemImage: "keyboard"
                    )
                }
                .buttonStyle(.rrPress)
                Rule()
                Button {
                    app.askCoach(
                        question: nil,
                        conversation: app.compose.conversationText,
                        crushID: app.compose.crush?.id
                    )
                } label: {
                    NavigationRow(
                        title: "Ask the coach about this",
                        subtitle: "Not sure which to send, or what comes after?",
                        systemImage: "graduationcap"
                    )
                }
                .buttonStyle(.rrPress)
                if let person = app.compose.crush, let read = app.compose.analysis?.read, !read.isEmpty {
                    Rule()
                    Button {
                        keepSummary(read, for: person)
                    } label: {
                        NavigationRow(
                            title: "Keep this read in \(person.alias)'s notes",
                            subtitle: "A one-line summary of this conversation, saved on your iPhone.",
                            systemImage: "book.closed"
                        )
                    }
                    .buttonStyle(.rrPress)
                }
                Rule()
            }

            Text("Send what feels true to you. These are options, not scripts.")
                .rrText(.note)
                .foregroundStyle(Color.rrTextTertiary)
        }
        .padding(.top, RRSpace.xs)
    }

    /// Adds ReplyRight's read of this conversation to the person's profile. Only on an explicit tap.
    private func keepSummary(_ read: String, for person: CrushProfile) {
        guard var stored = app.person(person.id) else { return }
        guard !stored.summaries.contains(where: { $0.text == read.trimmed }) else {
            app.toast = "Already in \(person.alias)'s notes."
            return
        }
        stored.addSummary(read, source: .conversation)
        app.savePerson(stored)
        app.compose.crush = stored
        Haptics.success()
        app.toast = "Kept in \(person.alias)'s notes."
    }
}

// MARK: - One reply

/// One suggestion: the approach it takes, the message as it would be sent, why
/// it could work, and everything the user can do with it.
///
/// It is a section on the page, not a card. The only shape is the bubble,
/// because the only message is the message.
struct ReplyCard: View {
    @Environment(AppModel.self) private var app
    @Binding var option: ReplyOption
    var isDemo = false
    var isRefining = false
    var intent: Intent? = nil
    var crushID: UUID? = nil
    var showsRefine = true
    let onRefine: (RefineAction) -> Void

    @State private var isEditing = false
    @State private var showsTweaks = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack(alignment: .center, spacing: RRSpace.xs) {
                Text(option.style)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrAccent)
                if option.isEdited {
                    Text("edited by you")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextTertiary)
                }
                Spacer()
                Button {
                    app.toggleSaved(text: option.text, style: option.style, intent: intent, crushID: crushID)
                } label: {
                    Image(systemName: app.isSaved(option.text.trimmed) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(app.isSaved(option.text.trimmed) ? Color.rrAccent : Color.rrTextTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(app.isSaved(option.text.trimmed) ? "Remove from saved" : "Save this reply")
            }

            message
                .opacity(isRefining ? 0.4 : 1)
                .overlay(alignment: .trailing) {
                    if isRefining {
                        BrandMark(size: 34, isWriting: true)
                            .padding(.trailing, RRSpace.m)
                    }
                }

            if !option.why.isEmpty {
                MarginNote(option.why)
            }

            actions

            if showsTweaks && showsRefine {
                tweaks
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard(padding: RRSpace.m)
        .animation(.rrSnappy, value: showsTweaks)
        .animation(.rrSnappy, value: isEditing)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(option.style) reply")
    }

    @ViewBuilder
    private var message: some View {
        if isEditing {
            TextField("Your message", text: $option.text, axis: .vertical)
                .lineLimit(1...8)
                .rrText(.message)
                .foregroundStyle(Color.rrText)
                .tint(Color.rrCursor)
                .focused($editorFocused)
                .padding(.horizontal, RRSpace.m)
                .padding(.vertical, RRSpace.s)
                .background {
                    BubbleShape(side: .mine).fill(Color.rrSurface)
                }
                .overlay {
                    BubbleShape(side: .mine).stroke(Color.rrAccent, lineWidth: 1.5)
                }
                .accessibilityIdentifier("reply-editor")
        } else {
            MessageBubble(option.text.isEmpty ? " " : option.text, side: .mine)
                .onTapGesture(count: 2) {
                    beginEditing()
                }
        }
    }

    private var actions: some View {
        HStack(spacing: RRSpace.s) {
            Button {
                isEditing = false
                app.copy(option.text, original: option.isEdited ? option.originalText : nil)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.rrSecondaryCompact)
            .disabled(option.text.trimmed.isEmpty || isRefining)
            .accessibilityIdentifier("reply-copy")

            Button(isEditing ? "Done" : "Edit") {
                if isEditing {
                    isEditing = false
                    editorFocused = false
                } else {
                    beginEditing()
                }
            }
            .buttonStyle(.rrQuiet)
            .accessibilityIdentifier("reply-edit")

            if showsRefine {
                Button(showsTweaks ? "Hide" : "Adjust") {
                    showsTweaks.toggle()
                    Haptics.tap()
                }
                .buttonStyle(.rrQuiet)
                .disabled(isRefining)
                .accessibilityIdentifier("reply-tweak")
            }

            if !option.text.trimmed.isEmpty {
                // Opens the system share sheet. The user picks the app and sends it themselves.
                ShareLink(item: option.text.trimmed) {
                    Text("Send\u{2026}")
                }
                .buttonStyle(.rrQuiet)
                .accessibilityLabel("Send with another app")
            }

            Spacer(minLength: 0)

            if !option.history.isEmpty || option.isEdited {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.rrTextSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Undo")
            }
        }
    }

    /// The ways to adjust this one reply. Each keeps the meaning and changes the delivery.
    private var tweaks: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            FlowLayout {
                ForEach(RefineAction.cardActions) { action in
                    RRChip(action.tweakTitle) {
                        isEditing = false
                        onRefine(action)
                    }
                    .accessibilityIdentifier("tweak-\(action.rawValue)")
                }
            }
            Text("Each adjustment uses one of today's replies.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
        }
    }

    private func beginEditing() {
        isEditing = true
        editorFocused = true
        Haptics.tap()
    }

    /// Steps back: first undoes hand edits, then earlier versions from adjustments.
    private func undo() {
        if option.isEdited {
            option.text = option.originalText
        } else {
            option.undo()
        }
        Haptics.tap()
    }
}

/// Offered once, after the user reworks a reply: would they like ReplyRight to learn from edits like that?
/// Personalisation is opt-in and everything learned is visible in My Voice.
private struct LearnFromEditsPrompt: View {
    @Environment(AppModel.self) private var app
    let options: [ReplyOption]

    var body: some View {
        if !app.settings.learnFromEdits, !app.settings.learnPromptSeen, options.contains(where: { $0.isEdited }) {
            VStack(alignment: .leading, spacing: RRSpace.s) {
                Text("You made that one yours.")
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                Text("Want me to learn from replies you edit and copy? They're kept on your iPhone in My Voice, where you can see and delete them.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: RRSpace.s) {
                    Button("Yes, learn from my edits") {
                        var settings = app.settings
                        settings.learnFromEdits = true
                        settings.learnPromptSeen = true
                        app.settings = settings
                        Haptics.success()
                    }
                    .buttonStyle(.rrSecondaryCompact)
                    Button("Not now") {
                        app.settings.learnPromptSeen = true
                    }
                    .buttonStyle(.rrQuiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(RRSpace.m)
            .background {
                RoundedRectangle(cornerRadius: RRRadius.card, style: .continuous).fill(Color.rrSurface)
            }
            .transition(.opacity)
        }
    }
}
