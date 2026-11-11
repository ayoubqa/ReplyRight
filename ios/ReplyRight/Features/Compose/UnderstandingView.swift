import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// Step two: what ReplyRight understood, then what the reply should do.
///
/// The read keeps what is visible in the messages apart from what nobody can
/// know from a text. ReplyRight never claims to know how the other person feels.
struct UnderstandingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let compose = app.compose

        ScreenScroll {
            switch compose.analysisState {
            case .idle, .loading:
                ThinkingView(lines: Microcopy.reading)
                    .padding(.top, RRSpace.xl)
            case .failed(let message):
                ErrorNote(message) {
                    compose.startAnalysis(app: app)
                }
                .padding(.top, RRSpace.l)
            case .loaded:
                if let analysis = compose.analysis {
                    ReadSection(analysis: analysis, isDemo: compose.mode == .demo)
                    if analysis.canReply {
                        IntentSection()
                    } else {
                        cannotReply
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if compose.analysisState == .loaded, compose.analysis?.canReply == true {
                Button("Write my replies") {
                    Haptics.tap()
                    app.homePath.append(.replies)
                    compose.startReplies(app: app)
                }
                .buttonStyle(.rrPrimary)
                .padding(.horizontal, RRSpace.screen)
                .padding(.vertical, RRSpace.s)
                .background(.ultraThinMaterial)
                .accessibilityIdentifier("understanding-write")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var cannotReply: some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            Text("I'd rather not write replies for this one. If I've misread it, try sharing a clearer part of the conversation.")
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: RRSpace.xs) {
                Button("Try again") {
                    app.homePath.removeLast()
                }
                .buttonStyle(.rrSecondaryCompact)
                Button("Talk to the coach") {
                    app.askCoach(conversation: app.compose.conversationText)
                }
                .buttonStyle(.rrQuiet)
            }
        }
    }
}

// MARK: - The read

private struct ReadSection: View {
    @Environment(AppModel.self) private var app
    let analysis: Analysis
    let isDemo: Bool
    @State private var showsTranscript = false

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            VStack(alignment: .leading, spacing: RRSpace.s) {
                HStack {
                    Eyebrow("My read")
                    Spacer()
                    if !analysis.toneLabel.isEmpty {
                        Text(analysis.toneLabel)
                            .rrText(.caption)
                            .foregroundStyle(Color.rrTextSecondary)
                            .padding(.horizontal, RRSpace.s)
                            .padding(.vertical, RRSpace.xxs)
                            .overlay {
                                Capsule().strokeBorder(Color.rrLineStrong, lineWidth: 1)
                            }
                    }
                }
                Text(analysis.read)
                    .rrText(.title)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("understanding-read")
            }

            if isDemo {
                DemoBadge(detailed: true)
            }

            if let latest = analysis.latestMessage, !latest.isEmpty {
                MessageBubble(latest, side: .theirs)
            }

            if let headsUp = analysis.headsUp, !headsUp.isEmpty {
                HeadsUpNote(headsUp)
            }

            if !analysis.observations.isEmpty || !analysis.assumptions.isEmpty {
                VStack(alignment: .leading, spacing: RRSpace.m) {
                    if !analysis.observations.isEmpty {
                        FactList(title: "What I can see", systemImage: "eye", items: analysis.observations)
                    }
                    if !analysis.assumptions.isEmpty {
                        FactList(title: "What I can't know", systemImage: "questionmark.circle", items: analysis.assumptions)
                    }
                    Text("Only they know what they meant. This is a read, not a verdict.")
                        .rrText(.caption)
                        .foregroundStyle(Color.rrTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rrCard()
            }

            if !analysis.opportunity.isEmpty {
                MarginNote(analysis.opportunity)
            }

            if !app.compose.transcript.isEmpty {
                transcript
            }
        }
    }

    /// What was read from the screenshots, so the user can check it and fix who said what.
    private var transcript: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Button {
                withAnimation(.rrSnappy) {
                    showsTranscript.toggle()
                }
            } label: {
                HStack {
                    Text("What I read (\(app.compose.transcript.count) messages)")
                        .rrText(.callout)
                        .foregroundStyle(Color.rrTextSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.rrTextTertiary)
                        .rotationEffect(.degrees(showsTranscript ? 180 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsTranscript {
                VStack(spacing: RRSpace.xxs + 2) {
                    ForEach(app.compose.transcript) { line in
                        Button {
                            app.compose.cycleSpeaker(line.id)
                            Haptics.select()
                        } label: {
                            MessageBubble(
                                line.speaker == .unknown ? "? \(line.text)" : line.text,
                                side: line.speaker == .me ? .mine : .theirs,
                                compact: true
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Double tap if this was sent by someone else")
                    }
                }
                Text("Got one the wrong way round? Tap a message to switch who said it.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            }
        }
    }
}

private struct FactList: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            Label(title, systemImage: systemImage)
                .rrText(.eyebrow)
                .foregroundStyle(Color.rrTextSecondary)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: RRSpace.xs) {
                    Circle()
                        .fill(Color.rrAccent)
                        .frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                    Text(item)
                        .rrText(.callout)
                        .foregroundStyle(Color.rrText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Intent

/// "What do you want this reply to do?" The choice that makes the suggestions purposeful.
struct IntentSection: View {
    @Environment(AppModel.self) private var app
    @State private var exampleIndex = 0

    var body: some View {
        @Bindable var compose = app.compose

        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                lead: "What should this reply ",
                emphasis: "do?",
                style: .title
            )

            IntentGrid(
                selection: compose.intent,
                suggested: compose.analysis?.suggestedIntents ?? []
            ) { intent in
                compose.intent = intent
                compose.intentWasChosen = true
            }

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Anything specific?")
                RRField(Microcopy.pick(Microcopy.instructionExamples, seed: exampleIndex), text: $compose.instruction, lineLimit: 3)
                    .accessibilityIdentifier("intent-instruction")
                StyleChips(instruction: $compose.instruction)
            }

            PersonPicker(selection: $compose.crush)
        }
        .onAppear {
            exampleIndex = Int.random(in: 0..<Microcopy.instructionExamples.count)
        }
    }
}

/// All the things a reply can be for. Suggested ones are marked; Pro ones show a lock on the free plan.
struct IntentGrid: View {
    @Environment(AppModel.self) private var app
    let selection: Intent
    var suggested: [Intent] = []
    let onSelect: (Intent) -> Void

    private let columns = [GridItem(.flexible(), spacing: RRSpace.xs), GridItem(.flexible(), spacing: RRSpace.xs)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: RRSpace.xs) {
            ForEach(Intent.selectorOrder) { intent in
                IntentTile(
                    intent: intent,
                    isSelected: intent == selection,
                    isSuggested: suggested.contains(intent),
                    isLocked: app.isLocked(intent)
                ) {
                    if app.isLocked(intent) {
                        _ = app.requirePro(.intent(intent))
                    } else {
                        onSelect(intent)
                        Haptics.select()
                    }
                }
            }
        }
    }
}

private struct IntentTile: View {
    let intent: Intent
    let isSelected: Bool
    let isSuggested: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: RRSpace.xs) {
                HStack {
                    Image(systemName: intent.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? Color.rrAccent : Color.rrTextSecondary)
                    Spacer()
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.rrTextTertiary)
                    } else if isSuggested {
                        Text("Fits")
                            .rrText(.caption)
                            .foregroundStyle(Color.rrCoral)
                    }
                }
                Text(intent.title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(intent.blurb)
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(RRSpace.s)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                    .fill(isSelected ? Color.rrAccentSoft : Color.rrSurface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                    .strokeBorder(isSelected ? Color.rrAccent.opacity(0.75) : Color.rrLine, lineWidth: 1)
            }
            .opacity(isLocked ? 0.72 : 1)
        }
        .buttonStyle(.rrPress)
        .accessibilityLabel(intent.title)
        .accessibilityValue(isLocked ? "Part of ReplyRight Pro" : (isSuggested ? "Suggested" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("intent-\(intent.rawValue)")
    }
}

/// The user's favourite styles as one-tap instructions, plus saving the current one.
struct StyleChips: View {
    @Environment(AppModel.self) private var app
    @Binding var instruction: String

    var body: some View {
        let trimmed = instruction.trimmed
        let alreadySaved = app.styles.contains { $0.instruction.caseInsensitiveCompare(trimmed) == .orderedSame }

        if !app.styles.isEmpty || !trimmed.isEmpty {
            FlowLayout {
                ForEach(app.styles) { style in
                    RRChip(style.name, systemImage: "star", isSelected: style.instruction == trimmed) {
                        instruction = style.instruction
                        Haptics.select()
                    }
                }
                if !trimmed.isEmpty && !alreadySaved {
                    RRChip("Save as a style", systemImage: "plus") {
                        let name = trimmed.count > 28 ? String(trimmed.prefix(26)) + "…" : trimmed
                        app.styles.insert(FavouriteStyle(name: name, instruction: trimmed), at: 0)
                        app.toast = "Saved to your styles."
                        Haptics.success()
                    }
                }
            }
        }
    }
}
