import Foundation
import Observation
import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// A running conversation with the coach. Kept in memory only; "New" clears it.
/// The server keeps no chat history: each question is sent with the exchange so far.
@MainActor
@Observable
final class CoachModel {
    struct Entry: Identifiable {
        let id = UUID()
        let role: CoachTurn.Role
        let text: String
        var suggestions: [CoachSuggestion] = []
        var followUps: [String] = []
        var headsUp: String?
        var isDemo = false
    }

    var entries: [Entry] = []
    var input = ""
    var isThinking = false
    var errorMessage: String?
    /// Conversation text the user chose to bring along for context.
    var conversation = ""
    /// A message the user is thinking of sending.
    var draft = ""

    @ObservationIgnored private var work: Task<Void, Never>?

    var hasContext: Bool {
        !conversation.trimmed.isEmpty || !draft.trimmed.isEmpty
    }

    func reset() {
        work?.cancel()
        work = nil
        entries = []
        input = ""
        isThinking = false
        errorMessage = nil
        conversation = ""
        draft = ""
    }

    func apply(_ seed: CoachSeed) {
        if !seed.conversation.trimmed.isEmpty || !seed.draft.trimmed.isEmpty {
            // New context means a new conversation with the coach.
            reset()
            conversation = seed.conversation
            draft = seed.draft
        }
        if let question = seed.question?.trimmed, !question.isEmpty {
            input = question
        }
    }

    func send(_ question: String, app: AppModel) {
        let clean = question.trimmed
        guard !clean.isEmpty, !isThinking else { return }
        errorMessage = nil
        entries.append(Entry(role: .user, text: clean))
        input = ""
        ask(app: app)
    }

    /// Re-sends after a failure. The user's last question is already in `entries`.
    func retry(app: AppModel) {
        guard !isThinking, entries.last?.role == .user else { return }
        errorMessage = nil
        ask(app: app)
    }

    private func ask(app: AppModel) {
        isThinking = true
        let request = CoachRequest(
            messages: entries.map { CoachTurn(role: $0.role, text: $0.text) },
            conversation: conversation,
            draft: draft,
            voice: app.voice.payload
        )
        work?.cancel()
        work = Task { [weak self] in
            do {
                let envelope = try await app.api.coach(request)
                guard let self, !Task.isCancelled else { return }
                app.record(envelope.usage, mode: envelope.mode)
                let result = envelope.result
                self.entries.append(
                    Entry(
                        role: .coach,
                        text: result.message,
                        suggestions: result.suggestions,
                        followUps: result.followUps,
                        headsUp: result.headsUp,
                        isDemo: envelope.mode == .demo
                    )
                )
                self.isThinking = false
            } catch let error as APIError {
                guard let self, !Task.isCancelled else { return }
                self.isThinking = false
                if error != .cancelled {
                    self.errorMessage = app.present(error)
                }
            } catch {
                self?.isThinking = false
                self?.errorMessage = "Something went wrong. Please try again."
            }
        }
    }
}

struct CoachTab: View {
    @Environment(AppModel.self) private var app
    @State private var coach = CoachModel()

    var body: some View {
        NavigationStack {
            CoachView(coach: coach)
        }
        .onAppear { consumeSeed() }
        .onChange(of: app.coachSeed) { _, _ in consumeSeed() }
    }

    private func consumeSeed() {
        guard let seed = app.coachSeed else { return }
        coach.apply(seed)
        app.coachSeed = nil
    }
}

/// The coach is laid out like an advice column rather than a chat app: questions are small,
/// answers are set as text, and anything worth sending appears as a message bubble.
struct CoachView: View {
    @Environment(AppModel.self) private var app
    @Bindable var coach: CoachModel
    @FocusState private var inputFocused: Bool

    private let bottomID = "coach-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScreenScroll {
                if coach.entries.isEmpty {
                    intro
                } else {
                    ForEach(coach.entries) { entry in
                        if entry.role == .user {
                            QuestionRow(text: entry.text)
                        } else {
                            AnswerBlock(entry: entry, isLatest: entry.id == coach.entries.last?.id) { followUp in
                                coach.send(followUp, app: app)
                            }
                        }
                    }
                }

                if coach.isThinking {
                    ThinkingView(lines: Microcopy.coaching)
                }
                if let message = coach.errorMessage {
                    ErrorNote(message) {
                        coach.retry(app: app)
                    }
                }
                Color.clear
                    .frame(height: 1)
                    .id(bottomID)
            }
            .onChange(of: coach.entries.count) { _, _ in
                withAnimation(.rrGentle) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
            .onChange(of: coach.isThinking) { _, _ in
                withAnimation(.rrGentle) {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !coach.entries.isEmpty || coach.hasContext {
                    Button("New") {
                        coach.reset()
                    }
                }
            }
        }
    }

    // MARK: Empty state

    private var intro: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                lead: "Talk it ",
                emphasis: "through.",
                subtitle: "Ask me anything about a conversation. I'll be honest, I'll explain my thinking, and I won't pretend to read minds."
            )

            if coach.hasContext {
                contextCard
            }

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("People often ask")
                VStack(spacing: 0) {
                    ForEach(Array(Microcopy.coachStarters.enumerated()), id: \.offset) { index, question in
                        if index > 0 {
                            Divider().overlay(Color.rrLine)
                        }
                        Button {
                            Haptics.tap()
                            coach.send(question, app: app)
                        } label: {
                            HStack {
                                Text(question)
                                    .rrText(.body)
                                    .foregroundStyle(Color.rrText)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.rrTextTertiary)
                            }
                            .padding(.horizontal, RRSpace.s)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.rrPress)
                    }
                }
                .rrCard(padding: RRSpace.xs)
            }
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            HStack {
                Eyebrow("What I'm working with")
                Spacer()
                Button("Remove") {
                    coach.conversation = ""
                    coach.draft = ""
                }
                .buttonStyle(.rrQuiet)
            }
            if !coach.conversation.trimmed.isEmpty {
                Text(coach.conversation)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .lineLimit(4)
            }
            if !coach.draft.trimmed.isEmpty {
                MessageBubble(coach.draft, side: .mine, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard()
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: RRSpace.xxs) {
            HStack(alignment: .bottom, spacing: RRSpace.xs) {
                TextField("Ask your coach…", text: $coach.input, axis: .vertical)
                    .lineLimit(1...4)
                    .rrText(.body)
                    .foregroundStyle(Color.rrText)
                    .focused($inputFocused)
                    .padding(.horizontal, RRSpace.m)
                    .padding(.vertical, RRSpace.s)
                    .background {
                        RoundedRectangle(cornerRadius: RRRadius.bubble, style: .continuous).fill(Color.rrSurface)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: RRRadius.bubble, style: .continuous)
                            .strokeBorder(Color.rrLineStrong, lineWidth: 1)
                    }
                    .accessibilityIdentifier("coach-input")

                Button {
                    Haptics.tap()
                    coach.send(coach.input, app: app)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.rrButtonText)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.rrButtonFill))
                }
                .disabled(coach.input.trimmed.isEmpty || coach.isThinking)
                .opacity(coach.input.trimmed.isEmpty || coach.isThinking ? 0.35 : 1)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("coach-send")
            }

            if !app.isPro, let remaining = app.usage?.coach.remaining {
                Text(remaining == 1 ? "1 free question left today" : "\(remaining) free questions left today")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            }
        }
        .padding(.horizontal, RRSpace.screen)
        .padding(.vertical, RRSpace.xs)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Rows

private struct QuestionRow: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: RRSpace.xl)
            Text(text)
                .rrText(.callout)
                .foregroundStyle(Color.rrText)
                .padding(.horizontal, RRSpace.m)
                .padding(.vertical, RRSpace.s)
                .background {
                    RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous).fill(Color.rrSurfaceRaised)
                }
        }
        .accessibilityLabel("You asked: \(text)")
    }
}

private struct AnswerBlock: View {
    @Environment(AppModel.self) private var app
    let entry: CoachModel.Entry
    let isLatest: Bool
    let onFollowUp: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            if entry.isDemo {
                DemoBadge()
            }
            Text(entry.text)
                .rrText(.bodyLarge)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let headsUp = entry.headsUp, !headsUp.isEmpty {
                HeadsUpNote(headsUp)
            }

            ForEach(entry.suggestions, id: \.self) { suggestion in
                VStack(alignment: .trailing, spacing: RRSpace.xxs) {
                    Text(suggestion.label)
                        .rrText(.eyebrow)
                        .foregroundStyle(Color.rrAccent)
                    Button {
                        app.copy(suggestion.text)
                    } label: {
                        MessageBubble(suggestion.text, side: .mine)
                    }
                    .buttonStyle(.rrPress)
                    .accessibilityHint("Copies this message")
                    Text("Tap to copy")
                        .rrText(.caption)
                        .foregroundStyle(Color.rrTextTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if isLatest, !entry.followUps.isEmpty {
                FlowLayout {
                    ForEach(entry.followUps, id: \.self) { followUp in
                        RRChip(followUp) {
                            onFollowUp(followUp)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
