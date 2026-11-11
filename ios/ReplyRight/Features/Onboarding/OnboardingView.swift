import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// First run: meet ReplyRight, confirm you are an adult, and sketch how you text.
/// No account, and every answer can be changed later in My Voice.
struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    enum Step: Int, CaseIterable {
        case welcome, age, goals, personality, texting, languages, tone, ready
    }

    @State private var step: Step = .welcome
    @State private var draft = VoiceProfile.standard
    @State private var isAdult = false

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

            if step == .age {
                Text("ReplyRight is only for people aged 18 and over.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            }
        }
        .padding(.horizontal, RRSpace.screen)
        .padding(.top, RRSpace.s)
        .padding(.bottom, RRSpace.m)
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: return "Let's begin"
        case .ready: return "Show me what they said"
        default: return "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .age: return isAdult
        case .languages: return !draft.languages.isEmpty
        default: return true
        }
    }

    private func advance() {
        Haptics.tap()
        if let next = Step(rawValue: step.rawValue + 1) {
            move(to: next)
        } else {
            finish()
        }
    }

    private func move(to target: Step) {
        withAnimation(.rrGentle) {
            step = target
        }
    }

    private func finish() {
        app.voice = draft
        var settings = app.settings
        settings.confirmedAdult = true
        settings.hasOnboarded = true
        app.settings = settings
        Haptics.success()
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .age:
            ageStep
        case .goals:
            VStack(alignment: .leading, spacing: RRSpace.xl) {
                ScreenHeader(
                    lead: "What would ",
                    emphasis: "help most?",
                    subtitle: "Pick as many as you like. This just helps me know where to start."
                )
                MultiChoiceGroup(
                    title: "I'd like help with",
                    options: VoiceProfile.Goal.allCases,
                    label: { $0.title },
                    selection: $draft.goals
                )
            }
        case .personality:
            VStack(alignment: .leading, spacing: RRSpace.xl) {
                ScreenHeader(
                    lead: "How would a friend ",
                    emphasis: "describe you?",
                    subtitle: "Choose up to two. There's no better or worse answer. Shy people send great texts."
                )
                MultiChoiceGroup(
                    title: "I'm naturally",
                    options: VoiceProfile.Personality.allCases,
                    label: { $0.title },
                    limit: 2,
                    selection: $draft.personality
                )
            }
        case .texting:
            textingStep
        case .languages:
            languagesStep
        case .tone:
            VStack(alignment: .leading, spacing: RRSpace.xl) {
                ScreenHeader(
                    lead: "With your crush, you'd like to ",
                    emphasis: "sound…",
                    subtitle: "This becomes your default. You can pick something different for any message."
                )
                VStack(spacing: RRSpace.xs) {
                    ForEach(Tone.allCases) { tone in
                        ToneRow(tone: tone, isSelected: draft.defaultTone == tone) {
                            draft.defaultTone = tone
                            Haptics.select()
                        }
                    }
                }
            }
        case .ready:
            readyStep
        }
    }

    private var ageStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.xl) {
            ScreenHeader(
                lead: "First, ",
                emphasis: "a quick one.",
                subtitle: "ReplyRight helps adults talk to people they're interested in. Please confirm that's you."
            )

            Button {
                isAdult.toggle()
                Haptics.select()
            } label: {
                HStack(spacing: RRSpace.m) {
                    Image(systemName: isAdult ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(isAdult ? Color.rrAccent : Color.rrTextTertiary)
                    Text("I'm 18 or older")
                        .rrText(.headline)
                        .foregroundStyle(Color.rrText)
                    Spacer()
                }
                .rrCard()
            }
            .buttonStyle(.rrPress)
            .accessibilityAddTraits(isAdult ? .isSelected : [])
            .accessibilityIdentifier("onboarding-adult")

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Text("By continuing you agree to the Terms of Use and Privacy Policy.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                HStack(spacing: RRSpace.m) {
                    Button("Terms") { openURL(AppConfig.termsURL(base: app.apiBaseURL)) }
                    Button("Privacy") { openURL(AppConfig.privacyURL(base: app.apiBaseURL)) }
                }
                .rrText(.footnote)
                .tint(Color.rrAccent)
            }
        }
    }

    private var textingStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.xl) {
            ScreenHeader(
                lead: "How do ",
                emphasis: "you text?",
                subtitle: "Watch the message change. Stop when it looks like something you'd send."
            )

            VStack(spacing: RRSpace.xs) {
                MessageBubble("so are we actually getting that coffee or what", side: .theirs)
                MessageBubble(TextingPreview.message(length: draft.length, emoji: draft.emoji), side: .mine)
                    .animation(.rrSnappy, value: draft.length)
                    .animation(.rrSnappy, value: draft.emoji)
            }
            .padding(.vertical, RRSpace.xs)

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
        }
    }

    private var languagesStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.xl) {
            ScreenHeader(
                lead: "Which languages do you ",
                emphasis: "text in?",
                subtitle: "Replies are written the way a native texter would say it, never translated word for word."
            )

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
                                .foregroundStyle(Color.rrTextTertiary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
                                .overlay {
                                    Capsule().strokeBorder(Color.rrLine, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                }
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

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.xl) {
            ScreenHeader(
                lead: "That's ",
                emphasis: "you.",
                subtitle: "I'll keep this in mind every time. Change anything, any time, in My Voice."
            )

            VStack(alignment: .leading, spacing: RRSpace.m) {
                SummaryLine(label: "Sounds", value: draft.defaultTone.title)
                if !draft.personality.isEmpty {
                    SummaryLine(label: "Naturally", value: draft.personality.map(\.title).joined(separator: ", "))
                }
                SummaryLine(label: "Messages", value: "\(draft.length.title), emoji \(draft.emoji.title.lowercased())")
                SummaryLine(
                    label: "Languages",
                    value: draft.languages.map { ReplyLanguage.name(for: $0) }.joined(separator: ", ")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rrCard(padding: RRSpace.l)

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Label("Nothing is sent anywhere until you ask for a reply.", systemImage: "lock")
                Label("Screenshots are read once and never stored.", systemImage: "photo")
                Label("You always choose what gets sent.", systemImage: "hand.tap")
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
                Eyebrow("ReplyRight")
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

private struct ToneRow: View {
    let tone: Tone
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tone.title)
                        .rrText(.headline)
                        .foregroundStyle(Color.rrText)
                    Text(tone.blurb)
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.rrAccent : Color.rrTextTertiary)
            }
            .padding(.horizontal, RRSpace.m)
            .padding(.vertical, RRSpace.s)
            .background {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                    .fill(isSelected ? Color.rrAccentSoft : Color.rrSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? Color.rrAccent.opacity(0.7) : Color.rrLine, lineWidth: 1)
            }
        }
        .buttonStyle(.rrPress)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SummaryLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: RRSpace.m) {
            Text(label)
                .rrText(.eyebrow)
                .foregroundStyle(Color.rrTextTertiary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
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
