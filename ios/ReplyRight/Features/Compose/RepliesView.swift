import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// Step three: three genuinely different ways to say it.
/// The user edits, tweaks, copies and sends. ReplyRight never sends anything.
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
                ErrorNote(message) {
                    compose.startReplies(app: app)
                }
                .padding(.top, RRSpace.l)

            case .loaded:
                header

                if compose.mode == .demo {
                    DemoBadge(detailed: true)
                }
                if let headsUp = compose.headsUp, !headsUp.isEmpty {
                    HeadsUpNote(headsUp)
                }

                if compose.options.isEmpty {
                    noOptions
                } else {
                    ForEach($compose.options) { $option in
                        ReplyCard(
                            option: $option,
                            isDemo: compose.mode == .demo,
                            isRefining: compose.refiningID == option.id,
                            intent: compose.intent,
                            onRefine: { action in
                                compose.refine(optionID: option.id, action: action, app: app)
                            }
                        )
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
                    .accessibilityLabel(compose.savedSessionID == nil ? "Save this session" : "Session saved")
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow(app.compose.intent.title)
            Text(app.compose.note.isEmpty ? "Here are a few ways to say it." : app.compose.note)
                .rrText(.title)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
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
            HStack(spacing: RRSpace.xs) {
                Button("Change the goal") {
                    app.homePath.removeLast()
                }
                .buttonStyle(.rrSecondaryCompact)
                Button("Talk to the coach") {
                    app.askCoach(conversation: app.compose.conversationText)
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
                Divider().overlay(Color.rrLine)
                Button {
                    app.askCoach(question: nil, conversation: app.compose.conversationText)
                } label: {
                    NavigationRow(
                        title: "Ask the coach about this",
                        subtitle: "Not sure which to send, or what comes after?",
                        systemImage: "lightbulb"
                    )
                }
                .buttonStyle(.rrPress)
            }
            .rrCard(padding: RRSpace.s)

            Text("Send what feels true to you. These are options, not scripts.")
                .rrText(.note)
                .foregroundStyle(Color.rrTextTertiary)
        }
        .padding(.top, RRSpace.xs)
    }
}

// MARK: - Reply card

/// One suggestion: the message as a bubble, why it could work, and everything the user can do with it.
struct ReplyCard: View {
    @Environment(AppModel.self) private var app
    @Binding var option: ReplyOption
    var isDemo = false
    var isRefining = false
    var intent: Intent? = nil
    var showsRefine = true
    let onRefine: (RefineAction) -> Void

    @State private var isEditing = false
    @State private var showsTweaks = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack(spacing: RRSpace.xs) {
                Text(option.style)
                    .rrText(.eyebrow)
                    .foregroundStyle(Color.rrAccent)
                if isDemo {
                    DemoBadge()
                }
                Spacer()
                if option.isEdited {
                    Text("Edited")
                        .rrText(.caption)
                        .foregroundStyle(Color.rrTextTertiary)
                }
                Button {
                    app.toggleSaved(text: option.text, style: option.style, intent: intent)
                } label: {
                    Image(systemName: app.isSaved(option.text.trimmed) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(app.isSaved(option.text.trimmed) ? Color.rrAccent : Color.rrTextTertiary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(app.isSaved(option.text.trimmed) ? "Remove from saved" : "Save this reply")
            }

            message
                .opacity(isRefining ? 0.45 : 1)
                .overlay(alignment: .center) {
                    if isRefining {
                        TypingDots().foregroundStyle(Color.rrText)
                    }
                }

            if !option.why.isEmpty {
                MarginNote(option.why)
            }

            actions

            if showsTweaks && showsRefine {
                tweaks
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard()
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
                .focused($editorFocused)
                .padding(.horizontal, RRSpace.m)
                .padding(.vertical, RRSpace.s)
                .background {
                    RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrSurfaceRaised)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                        .strokeBorder(Color.rrAccent.opacity(0.7), lineWidth: 1)
                }
                .accessibilityIdentifier("reply-editor")
        } else {
            MessageBubble(option.text.isEmpty ? " " : option.text, side: .mine)
                .padding(.leading, -44)
                .onTapGesture(count: 2) {
                    beginEditing()
                }
        }
    }

    private var actions: some View {
        HStack(spacing: RRSpace.xs) {
            Button {
                isEditing = false
                app.copy(option.text, original: option.isEdited ? option.originalText : nil)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(RRPrimaryButtonStyle(fullWidth: false))
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
            .buttonStyle(.rrSecondaryCompact)
            .accessibilityIdentifier("reply-edit")

            if showsRefine {
                Button {
                    showsTweaks.toggle()
                    Haptics.tap()
                } label: {
                    Label("Tweak", systemImage: "wand.and.stars")
                }
                .buttonStyle(.rrSecondaryCompact)
                .disabled(isRefining)
                .accessibilityIdentifier("reply-tweak")
            }

            Spacer(minLength: 0)

            if !option.history.isEmpty || option.isEdited {
                Button {
                    undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.rrTextSecondary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Undo")
            }
        }
    }

    private var tweaks: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            FlowLayout {
                ForEach(RefineAction.cardActions) { action in
                    RRChip(action.title, systemImage: action.symbol) {
                        isEditing = false
                        onRefine(action)
                    }
                }
            }
            Text("Each tweak uses one of today's replies.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
        }
    }

    private func beginEditing() {
        isEditing = true
        editorFocused = true
        Haptics.tap()
    }

    /// Steps back: first undoes hand edits, then earlier versions from tweaks.
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
                HStack(spacing: RRSpace.xs) {
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
            .rrCard()
            .transition(.opacity)
        }
    }
}
