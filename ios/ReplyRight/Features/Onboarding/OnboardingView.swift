import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// First run in three screens: meet ReplyRight and confirm you are an adult,
/// sketch how you text, then get a first real result. No account, and every
/// answer can be changed later in My Voice. The keyboard is introduced on
/// Home afterwards, once the user has seen what ReplyRight does.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    enum Step: Int, CaseIterable {
        case welcome, style, firstResult
    }

    /// Where the first result comes from. The example costs nothing: its
    /// replies are written in advance and no request is made. A pasted chat
    /// makes exactly one request, when the user taps the button.
    enum Source: Hashable {
        case example
        case pasted
    }

    @State private var step: Step = .welcome
    @State private var draft = VoiceProfile.standard
    @State private var isAdult = false
    @State private var source: Source = .example
    @State private var pasted = ""

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                content
                    .padding(.horizontal, RRSpace.screen)
                    .padding(.top, RRSpace.l)
                    .padding(.bottom, RRSpace.xl)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(.opacity.combined(with: .offset(y: 12)))
            }
            .scrollDismissesKeyboard(.interactively)
            bottomBar
        }
        .rrScreenBackground(intensity: 1.2)
        .onAppear {
            draft = app.voice
            isAdult = app.settings.confirmedAdult
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            Button {
                move(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.rrTextSecondary)
                    .frame(width: 44, height: 44)
            }
            .opacity(step == .welcome ? 0 : 1)
            .disabled(step == .welcome)
            .accessibilityLabel("Back")
            .accessibilityHidden(step == .welcome)

            Spacer()

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.rrAccent : Color.rrLineStrong)
                        .frame(width: item == step ? 18 : 6, height: 6)
                }
            }
            .animation(.rrSnappy, value: step)
            .accessibilityElement()
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, RRSpace.xs)
    }

    private var bottomBar: some View {
        VStack(spacing: RRSpace.xs) {
            Button(primaryTitle) {
                advance()
            }
            .buttonStyle(.rrPrimary)
            .disabled(!canAdvance)
            .accessibilityIdentifier("onboarding-continue")

            switch step {
            case .welcome:
                Text("ReplyRight is only for people aged 18 and over.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            case .style:
                EmptyView()
            case .firstResult:
                Button("Skip for now") {
                    finish(with: nil)
                }
                .buttonStyle(.rrQuiet)
                .accessibilityIdentifier("onboarding-skip")
            }
        }
        .padding(.horizontal, RRSpace.screen)
        .padding(.top, RRSpace.s)
        .padding(.bottom, RRSpace.m)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Let's begin"
        case .style: return "Continue"
        case .firstResult: return source == .example ? "Show me how it works" : "Write my first replies"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .welcome: return isAdult
        case .style: return !draft.languages.isEmpty
        case .firstResult: return source == .example || pasted.trimmed.count >= 2
        }
    }

    private func advance() {
        Haptics.tap()
        if let next = Step(rawValue: step.rawValue + 1) {
            move(to: next)
        } else {
            switch source {
            case .example: finish(with: .example)
            case .pasted: finish(with: .conversation(pasted.trimmed))
            }
        }
    }

    private func move(to target: Step) {
        withAnimation(.rrGentle) {
            step = target
        }
    }

    private enum FirstResult {
        /// The worked example. No request.
        case example
        /// The user's own chat. One replies request, nothing else.
        case conversation(String)
    }

    /// Saves the answers and opens the app on the first result, if one was chosen.
    private func finish(with first: FirstResult?) {
        app.voice = draft
        var settings = app.settings
        settings.confirmedAdult = true
        settings.hasOnboarded = true
        app.settings = settings
        Haptics.success()

        switch first {
        case nil:
            break
        case .example?:
            app.selectedTab = .home
            app.homePath = [.example]
        case .conversation(let text)?:
            guard !text.isEmpty else { return }
            // Straight to three replies: one request, no separate reading step.
            app.compose.reset()
            app.compose.text = text
            app.selectedTab = .home
            app.homePath = [.replies]
            app.compose.startReplies(app: app)
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .style:
            styleStep
        case .firstResult:
            firstResultStep
        }
    }

    // MARK: 1. Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.xl) {
            WelcomeStep()

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Button {
                    isAdult.toggle()
                    Haptics.select()
                } label: {
                    HStack(spacing: RRSpace.m) {
                        Image(systemName: isAdult ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 26, weight: .regular))
                            .foregroundStyle(isAdult ? Color.rrAccent : Color.rrTextSecondary)
                            .accessibilityHidden(true)
                        Text("I'm 18 or older")
                            .rrText(.headline)
                            .foregroundStyle(Color.rrText)
                        Spacer()
                    }
                    .rrCard()
                }
                .buttonStyle(.rrPress)
                .accessibilityLabel("I'm 18 or older")
                .accessibilityValue(isAdult ? "Confirmed" : "Not confirmed")
                .accessibilityAddTraits(isAdult ? .isSelected : [])
                .accessibilityIdentifier("onboarding-adult")

                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Text("By continuing you agree to the Terms of Use and Privacy Policy.")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                    HStack(spacing: RRSpace.m) {
                        Button("Terms") { openURL(AppConfig.termsURL(base: app.apiBaseURL)) }
                            .frame(minHeight: 44)
                        Button("Privacy") { openURL(AppConfig.privacyURL(base: app.apiBaseURL)) }
                            .frame(minHeight: 44)
                    }
                    .rrText(.footnote)
                    .tint(Color.rrAccent)
                }
            }
        }
    }

    // MARK: 2. Communication style

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.xl) {
            ScreenHeader(
                lead: "How do ",
                emphasis: "you text?",
                subtitle: "Watch the message change. Stop when it looks like something you'd send. All of this can change later in My Voice."
            )

            VStack(spacing: RRSpace.xs) {
                MessageBubble("so are we actually getting that coffee or what", side: .theirs)
                MessageBubble(TextingPreview.message(length: draft.length, emoji: draft.emoji), side: .mine)
                    .animation(.rrSnappy, value: draft.length)
                    .animation(.rrSnappy, value: draft.emoji)
            }
            .padding(.vertical, RRSpace.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preview: \(TextingPreview.message(length: draft.length, emoji: draft.emoji))")

            ChoiceGroup(
                title: "My messages are usually",
                options: VoiceProfile.Length.allCases,
                label: { "\($0.title) · \($0.blurb)" },
                selection: $draft.length
            )
            ChoiceGroup(
                title: "Emoji",
                options: VoiceProfile.EmojiUse.allCases,
                label: { $0.title },
                selection: $draft.emoji
            )

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("With someone I like, I'd rather sound")
                FlowLayout {
                    ForEach(Tone.allCases) { tone in
                        RRChip(tone.title, isSelected: draft.defaultTone == tone) {
                            draft.defaultTone = tone
                            Haptics.select()
                        }
                        .accessibilityHint(tone.blurb)
                    }
                }
                Text(draft.defaultTone.blurb)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            languages
        }
    }

    private var languages: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("I text in")
                FlowLayout {
                    ForEach(ReplyLanguage.all) { language in
                        if language.isAvailable {
                            RRChip(language.nativeName, isSelected: draft.languages.contains(language.id)) {
                                toggleLanguage(language.id)
                            }
                        } else {
                            Text("\(language.nativeName) · soon")
                                .rrText(.callout)
                                .foregroundStyle(Color.rrTextSecondary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .overlay {
                                    Capsule().strokeBorder(Color.rrLine, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
                                .accessibilityLabel("\(language.nativeName), coming soon")
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Write my replies in")
                FlowLayout {
                    RRChip("Whatever they're using", isSelected: draft.replyLanguage == "match") {
                        draft.replyLanguage = "match"
                        Haptics.select()
                    }
                    ForEach(ReplyLanguage.available.filter { draft.languages.contains($0.id) }) { language in
                        RRChip("Always \(language.name)", isSelected: draft.replyLanguage == language.id) {
                            draft.replyLanguage = language.id
                            Haptics.select()
                        }
                    }
                }
                Text("Replies are written the way a native texter would say it, never translated word for word.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggleLanguage(_ id: String) {
        if let index = draft.languages.firstIndex(of: id) {
            draft.languages.remove(at: index)
            if draft.replyLanguage == id {
                draft.replyLanguage = "match"
            }
        } else {
            draft.languages.append(id)
        }
        Haptics.select()
    }

    // MARK: 3. First result

    private var firstResultStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                lead: "Let's write your ",
                emphasis: "first reply.",
                subtitle: "See a worked example, or paste a real chat and get three different ways to answer."
            )

            Picker("Conversation", selection: $source) {
                Text("Use an example").tag(Source.example)
                Text("Paste my own").tag(Source.pasted)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding-source")

            switch source {
            case .example:
                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Label("A made-up chat. Its example replies are written in advance, so nothing is sent.", systemImage: "sparkles")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrHighlightInk)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(SampleConversation.lines.enumerated()), id: \.offset) { _, line in
                        MessageBubble(line.text, side: line.speaker == .them ? .theirs : .mine)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding-example")
            case .pasted:
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    RRTextArea(text: $pasted, placeholder: "Paste their message, or the last few lines of the chat.", minHeight: 120)
                        .accessibilityLabel("Their message")
                        .accessibilityIdentifier("onboarding-paste-field")
                    Button {
                        if let copied = UIPasteboard.general.string?.trimmed, !copied.isEmpty {
                            pasted = copied
                            Haptics.tap()
                        } else {
                            app.toast = "There's no text on the clipboard."
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.rrSecondaryCompact)
                }
                .rrPanel()
            }

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                if source == .pasted {
                    Label("Nothing is sent until you tap Write my first replies.", systemImage: "lock")
                    Label("This uses one of today's free replies.", systemImage: "number")
                }
                Label("ReplyRight never sends anything to anyone. You copy what you like.", systemImage: "hand.tap")
            }
            .rrText(.footnote)
            .foregroundStyle(Color.rrTextSecondary)
        }
    }
}

// MARK: - Pieces

/// A tiny scene that plays once: a message arrives, there's a pause, the right words appear.
private struct WelcomeStep: View {
    @State private var stage = 0

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.xl) {
            VStack(spacing: RRSpace.xs) {
                if stage >= 1 {
                    MessageBubble("so… what are you up to this weekend?", side: .theirs)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                }
                if stage == 2 {
                    HStack {
                        Spacer()
                        TypingDots()
                            .foregroundStyle(Color.rrBubbleMineText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 15)
                            .background {
                                BubbleShape(side: .mine).fill(LinearGradient.rrBubbleMine)
                            }
                    }
                    .transition(.opacity)
                }
                if stage >= 3 {
                    MessageBubble("depends. are you about to make it better?", side: .mine)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
                }
            }
            .frame(minHeight: 132, alignment: .top)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: RRSpace.m) {
                BrandLogo(height: 24)
                    .padding(.bottom, RRSpace.xxs)
                EditorialTitle("Say it better.\n", emphasis: "Be yourself.", style: .hero)
                Text("For the moment you stare at a message and think: what do I even say? Let's find words that sound like you.")
                    .rrText(.bodyLarge)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            let delays: [UInt64] = [350_000_000, 900_000_000, 1_500_000_000]
            for (index, delay) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }
                withAnimation(.rrGentle) {
                    stage = index + 1
                }
            }
        }
    }
}

/// The same message written the way different people would text it.
enum TextingPreview {
    static func message(length: VoiceProfile.Length, emoji: VoiceProfile.EmojiUse) -> String {
        let base: String
        switch length {
        case .short:
            base = "obviously. thursday?"
        case .medium:
            base = "Obviously. Are you free Thursday after work?"
        case .long:
            base = "Obviously, I've been thinking about it all week. Are you free Thursday after work? I know a place with great pastries."
        }
        switch emoji {
        case .none:
            return base
        case .rare:
            return base + " ☕"
        case .often:
            return "😄 " + base + " ☕✨"
        }
    }
}
