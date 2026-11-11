import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// My Voice: how the user actually texts. Optional, transparent, and easy to reset.
/// Changes save as they are made and stay on the device.
struct MyVoiceView: View {
    @Environment(AppModel.self) private var app
    @State private var newSample = ""
    @State private var confirmsReset = false
    @State private var showsPayload = false

    var body: some View {
        @Bindable var app = app

        ScreenScroll {
            ScreenHeader(
                lead: "My ",
                emphasis: "voice.",
                subtitle: "Nobody wants to sound like AI. This is how I make suggestions sound like you, on a good day."
            )

            ChoiceGroup(
                title: "With a crush I like to sound",
                options: Tone.allCases,
                label: { $0.title },
                selection: $app.voice.defaultTone
            )

            MultiChoiceGroup(
                title: "I'm naturally",
                caption: "Up to two.",
                options: VoiceProfile.Personality.allCases,
                label: { $0.title },
                limit: 2,
                selection: $app.voice.personality
            )

            ChoiceGroup(
                title: "Humour",
                caption: app.voice.humour.blurb,
                options: VoiceProfile.Humour.allCases,
                label: { $0.title },
                selection: $app.voice.humour
            )

            ChoiceGroup(
                title: "Message length",
                caption: app.voice.length.blurb,
                options: VoiceProfile.Length.allCases,
                label: { $0.title },
                selection: $app.voice.length
            )

            ChoiceGroup(
                title: "Emoji",
                options: VoiceProfile.EmojiUse.allCases,
                label: { $0.title },
                selection: $app.voice.emoji
            )

            ChoiceGroup(
                title: "Vocabulary",
                caption: "From relaxed and slangy to tidy and polished.",
                options: VoiceProfile.Vocabulary.allCases,
                label: { $0.title },
                selection: $app.voice.vocabulary
            )

            ChoiceGroup(
                title: "Confidence",
                caption: "How directly you say what you mean.",
                options: VoiceProfile.Directness.allCases,
                label: { $0.title },
                selection: $app.voice.directness
            )

            ChoiceGroup(
                title: "Romantic expression",
                caption: "From showing interest quietly to saying how you feel.",
                options: VoiceProfile.Romance.allCases,
                label: { $0.title },
                selection: $app.voice.romance
            )

            languages

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("How I write")
                RRTextArea(
                    text: $app.voice.writingStyle,
                    placeholder: "all lowercase, no exclamation marks, I say \u{201C}haha\u{201D} not \u{201C}lol\u{201D}",
                    minHeight: 72
                )
                LimitLabel(count: app.voice.writingStyle.count, limit: VoiceProfile.maxNoteLength)
            }

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("About me")
                RRTextArea(
                    text: $app.voice.aboutMe,
                    placeholder: "I climb, cook too much pasta, and just moved to Lisbon. Only used when it fits naturally.",
                    minHeight: 72
                )
                LimitLabel(count: app.voice.aboutMe.count, limit: VoiceProfile.maxNoteLength)
            }

            samples

            learning

            transparency

            Button("Reset My Voice") {
                confirmsReset = true
            }
            .buttonStyle(.rrQuiet)
            .confirmationDialog(
                "Reset My Voice?",
                isPresented: $confirmsReset,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    app.voice = .standard
                    app.toast = "My Voice is back to the defaults."
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your preferences and example messages will be deleted from this iPhone.")
            }
        }
        .navigationTitle("My Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Languages

    private var languages: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Languages I text in")
            FlowLayout {
                ForEach(ReplyLanguage.available) { language in
                    RRChip(language.nativeName, isSelected: app.voice.languages.contains(language.id)) {
                        toggleLanguage(language.id)
                    }
                }
            }
            Eyebrow("Write my replies in")
                .padding(.top, RRSpace.xs)
            FlowLayout {
                RRChip("Whatever they're using", isSelected: app.voice.replyLanguage == "match") {
                    app.voice.replyLanguage = "match"
                    Haptics.select()
                }
                ForEach(ReplyLanguage.available) { language in
                    RRChip("Always \(language.name)", isSelected: app.voice.replyLanguage == language.id) {
                        app.voice.replyLanguage = language.id
                        Haptics.select()
                    }
                }
            }
            Text("Replies are written the way a native texter would say it, not translated word for word.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
        }
    }

    private func toggleLanguage(_ id: String) {
        var voice = app.voice
        if let index = voice.languages.firstIndex(of: id) {
            guard voice.languages.count > 1 else { return }
            voice.languages.remove(at: index)
        } else {
            voice.languages.append(id)
        }
        app.voice = voice
        Haptics.select()
    }

    // MARK: Samples

    private var samples: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack {
                Eyebrow("Messages I've really sent")
                Spacer()
                if !app.plan.voiceSamples {
                    Label("Pro", systemImage: "lock.fill")
                        .rrText(.caption)
                        .foregroundStyle(Color.rrTextTertiary)
                }
            }
            Text("A few real examples teach me your rhythm, casing and punctuation. I copy the style, never the content.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(app.voice.samples) { sample in
                HStack(alignment: .top, spacing: RRSpace.xs) {
                    VStack(alignment: .leading, spacing: RRSpace.xxs) {
                        Text(sample.text)
                            .rrText(.callout)
                            .foregroundStyle(Color.rrText)
                            .fixedSize(horizontal: false, vertical: true)
                        if sample.source == .learned {
                            Text("Learned from a reply you edited")
                                .rrText(.caption)
                                .foregroundStyle(Color.rrTextTertiary)
                        }
                    }
                    Spacer(minLength: RRSpace.xs)
                    Button {
                        app.voice.samples.removeAll { $0.id == sample.id }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.rrTextTertiary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Remove example")
                }
                .padding(.horizontal, RRSpace.m)
                .padding(.vertical, RRSpace.xs)
                .background {
                    RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrSurface)
                }
            }

            if app.voice.samples.count < VoiceProfile.maxSamples {
                HStack(alignment: .bottom, spacing: RRSpace.xs) {
                    RRField("Paste or type a message you sent", text: $newSample, lineLimit: 3)
                    Button("Add") {
                        addSample()
                    }
                    .buttonStyle(.rrSecondaryCompact)
                    .disabled(newSample.trimmed.isEmpty)
                }
            } else {
                Text("That's the most I can use at once. Remove one to add another.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            }

            if !app.plan.voiceSamples {
                Button {
                    app.paywall = .voiceSamples
                } label: {
                    Text("Your examples are saved on this iPhone. Using them to shape replies is part of Pro.")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrAccent)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    private func addSample() {
        app.voice.addSample(newSample, source: .added)
        newSample = ""
        Haptics.success()
    }

    // MARK: Learning and transparency

    private var learning: some View {
        @Bindable var app = app
        return VStack(alignment: .leading, spacing: RRSpace.xs) {
            Toggle(isOn: $app.settings.learnFromEdits) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learn from my edits")
                        .rrText(.headline)
                        .foregroundStyle(Color.rrText)
                    Text("When you rework a suggestion and copy it, keep it above as an example. Off unless you turn it on.")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.rrAccent)
        }
        .rrCard()
    }

    private var transparency: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Button {
                withAnimation(.rrSnappy) { showsPayload.toggle() }
            } label: {
                HStack {
                    Label("See exactly what gets sent", systemImage: "eye")
                        .rrText(.callout)
                        .foregroundStyle(Color.rrText)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.rrTextTertiary)
                        .rotationEffect(.degrees(showsPayload ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsPayload {
                Text("This travels with each request you make, and nowhere else. It isn't stored on our servers.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(payloadJSON)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.rrTextSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .rrCard()
    }

    private var payloadJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var payload = app.voice.payload
        if !app.plan.voiceSamples {
            // On the free plan the server ignores examples, so they are shown as not sent.
            payload.samples = []
        }
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

struct LimitLabel: View {
    let count: Int
    let limit: Int

    var body: some View {
        Text("\(min(count, limit))/\(limit)")
            .rrText(.caption)
            .foregroundStyle(count > limit ? Color.rrWarning : Color.rrTextTertiary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
