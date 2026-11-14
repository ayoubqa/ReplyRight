import Foundation
import Observation
import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// Time with the coach. Three ways to use it:
///
///   ask       a question about flirting, conversation, asking someone out, confidence
///   review    feedback on one message the user wrote
///   practice  a rehearsal where the coach plays the other person and steps out to give feedback
///
/// Everything is kept in memory only. The server keeps no history: each
/// request carries the exchange so far.
@MainActor
@Observable
final class CoachModel {
    enum Stage: Equatable {
        case lobby
        case ask
        case review
        case practice
    }

    struct Entry: Identifiable {
        let id = UUID()
        let role: CoachTurn.Role
        let text: String
        var suggestions: [CoachSuggestion] = []
        var followUps: [String] = []
        var lesson: String?
        var review: CoachReview?
        var headsUp: String?
        var mode: GenerationMode?
    }

    /// One line of a rehearsal. `.user` is what the user sent; `.coach` is the simulated person.
    struct PracticeTurn: Identifiable {
        let id = UUID()
        let role: CoachTurn.Role
        let text: String
        var feedback: String?
        var tryThis: String?
    }

    struct ReviewOutcome {
        var message: String
        var review: CoachReview?
        var headsUp: String?
        var followUps: [String]
        var mode: GenerationMode
    }

    var stage: Stage = .lobby
    var topic: CoachTopic = .general
    var input = ""
    var isThinking = false
    var errorMessage: String?
    var failure: APIError?

    // Ask
    var entries: [Entry] = []
    /// Conversation text the user chose to bring along for context.
    var conversation = ""
    /// A message the user is thinking of sending.
    var draft = ""
    /// The profile the user chose to bring along. Never used in practice.
    var crush: CrushProfile?

    // Review
    var reviewDraft = ""
    var reviewGoal = ""
    var reviewOutcome: ReviewOutcome?

    // Practice
    var scenario: PracticeSetup?
    var practiceIntro = ""
    var practiceTurns: [PracticeTurn] = []
    var practiceNote = ""
    var practiceFinished = false
    var practiceMode: GenerationMode?

    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var retryWork: (() -> Void)?

    var hasContext: Bool {
        !conversation.trimmed.isEmpty || !draft.trimmed.isEmpty
    }

    /// Back to the start, with nothing kept.
    func reset() {
        work?.cancel()
        work = nil
        retryWork = nil
        stage = .lobby
        topic = .general
        input = ""
        isThinking = false
        errorMessage = nil
        failure = nil
        entries = []
        conversation = ""
        draft = ""
        crush = nil
        reviewDraft = ""
        reviewGoal = ""
        reviewOutcome = nil
        scenario = nil
        practiceIntro = ""
        practiceTurns = []
        practiceNote = ""
        practiceFinished = false
        practiceMode = nil
    }

    func apply(_ seed: CoachSeed, app: AppModel) {
        let bringsContext = !seed.conversation.trimmed.isEmpty || !seed.draft.trimmed.isEmpty
        if bringsContext || seed.mode == .review {
            // New context means a new conversation with the coach.
            reset()
            conversation = seed.conversation
            crush = app.person(seed.crushID)
        }
        switch seed.mode {
        case .review:
            reviewDraft = seed.draft
            stage = .review
        case .ask, .practice:
            draft = seed.draft
            if let question = seed.question?.trimmed, !question.isEmpty {
                input = question
            }
            if bringsContext {
                stage = .ask
            }
        }
    }

    func retry() {
        guard !isThinking else { return }
        retryWork?()
    }

    // MARK: Ask

    func open(_ topic: CoachTopic) {
        self.topic = topic
        stage = .ask
    }

    func send(_ question: String, app: AppModel) {
        let clean = question.trimmed
        guard !clean.isEmpty, !isThinking else { return }
        stage = .ask
        entries.append(Entry(role: .user, text: clean))
        input = ""
        ask(app: app)
    }

    private func ask(app: AppModel) {
        let request = CoachRequest(
            mode: .ask,
            topic: topic,
            messages: entries.map { CoachTurn(role: $0.role, text: $0.text) },
            conversation: conversation,
            draft: draft,
            voice: app.voice.payload,
            crush: crush?.payload
        )
        retryWork = { [weak self] in self?.ask(app: app) }
        run(request, app: app) { [weak self] result, mode in
            self?.entries.append(
                Entry(
                    role: .coach,
                    text: result.message,
                    suggestions: result.suggestions,
                    followUps: result.followUps,
                    lesson: result.lesson,
                    review: result.review,
                    headsUp: result.headsUp,
                    mode: mode
                )
            )
        }
    }

    // MARK: Review

    func requestReview(app: AppModel) {
        let text = reviewDraft.trimmed
        guard !text.isEmpty, !isThinking else { return }
        reviewOutcome = nil
        let request = CoachRequest(
            mode: .review,
            topic: topic,
            conversation: conversation,
            draft: text,
            goal: reviewGoal,
            voice: app.voice.payload,
            crush: crush?.payload
        )
        retryWork = { [weak self] in self?.requestReview(app: app) }
        run(request, app: app) { [weak self] result, mode in
            self?.reviewOutcome = ReviewOutcome(
                message: result.message,
                review: result.review,
                headsUp: result.headsUp,
                followUps: result.followUps,
                mode: mode
            )
            Haptics.success()
        }
    }

    /// Carries a finished review into a conversation, so the user can ask about it.
    func discussReview(_ question: String, app: AppModel) {
        guard let outcome = reviewOutcome else { return }
        draft = reviewDraft
        entries = [
            Entry(role: .user, text: "Can you look at this message I wrote?"),
            Entry(role: .coach, text: outcome.message, review: outcome.review, headsUp: outcome.headsUp, mode: outcome.mode),
        ]
        send(question, app: app)
    }

    // MARK: Practice

    func startPractice(_ scenario: PracticeScenario, detail: String, app: AppModel) {
        guard !isThinking else { return }
        self.scenario = PracticeSetup(id: scenario, detail: detail)
        practiceIntro = ""
        practiceTurns = []
        practiceNote = ""
        practiceFinished = false
        practiceMode = nil
        stage = .practice
        practiceStep(app: app)
    }

    func sendPractice(_ text: String, app: AppModel) {
        let clean = text.trimmed
        guard !clean.isEmpty, !isThinking, !practiceFinished else { return }
        practiceTurns.append(PracticeTurn(role: .user, text: clean))
        input = ""
        practiceStep(app: app)
    }

    private func practiceStep(app: AppModel) {
        guard let scenario else { return }
        let isOpening = practiceTurns.isEmpty
        // No profile is sent here: practice is with an invented person, never a real one.
        let request = CoachRequest(
            mode: .practice,
            topic: topic,
            messages: practiceTurns.map { CoachTurn(role: $0.role, text: $0.text) },
            scenario: scenario,
            voice: app.voice.payload
        )
        retryWork = { [weak self] in self?.practiceStep(app: app) }
        run(request, app: app) { [weak self] result, mode in
            guard let self else { return }
            self.practiceMode = mode
            if isOpening {
                self.practiceIntro = result.message
                self.practiceNote = ""
            } else {
                self.practiceNote = result.message
            }
            guard let practice = result.practice else { return }
            if let index = self.practiceTurns.lastIndex(where: { $0.role == .user }) {
                self.practiceTurns[index].feedback = practice.feedback
                self.practiceTurns[index].tryThis = practice.tryThis
            }
            if let reply = practice.partnerReply?.trimmed, !reply.isEmpty {
                self.practiceTurns.append(PracticeTurn(role: .coach, text: reply))
                Haptics.tap()
            }
            self.practiceFinished = practice.finished
        }
    }

    // MARK: Sending

    private func run(_ request: CoachRequest, app: AppModel, onSuccess: @escaping (CoachResult, GenerationMode) -> Void) {
        isThinking = true
        errorMessage = nil
        failure = nil
        work?.cancel()
        work = Task { [weak self] in
            do {
                let envelope = try await app.api.coach(request)
                guard let self, !Task.isCancelled else { return }
                app.record(envelope.usage, mode: envelope.mode)
                self.isThinking = false
                onSuccess(envelope.result, envelope.mode)
            } catch let error as APIError {
                guard let self, !Task.isCancelled else { return }
                self.isThinking = false
                if error != .cancelled {
                    self.failure = error
                    self.errorMessage = app.present(error)
                }
            } catch {
                self?.isThinking = false
                self?.failure = nil
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
        coach.apply(seed, app: app)
        app.coachSeed = nil
    }
}

/// The coach. It is laid out like a lesson, not a chat app: questions are
/// small, answers are set as text, lessons are marked with the pencil, and
/// anything worth sending appears as a message bubble.
struct CoachView: View {
    @Environment(AppModel.self) private var app
    @Bindable var coach: CoachModel

    var body: some View {
        Group {
            switch coach.stage {
            case .lobby:
                CoachLobby(coach: coach)
            case .ask:
                AskView(coach: coach)
            case .review:
                ReviewView(coach: coach)
            case .practice:
                PracticeView(coach: coach)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(coach.stage == .lobby ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            if coach.stage != .lobby {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        coach.reset()
                    } label: {
                        Label("Coach", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("coach-back")
                }
            }
        }
        .animation(.rrGentle, value: coach.stage)
    }

    private var title: String {
        switch coach.stage {
        case .lobby: return "Coach"
        case .ask: return coach.topic == .general ? "Ask" : coach.topic.title
        case .review: return "Message check"
        case .practice: return "Practice"
        }
    }
}

// MARK: - Lobby

/// Where a session starts: what to work on, and the two hands-on tools.
private struct CoachLobby: View {
    @Environment(AppModel.self) private var app
    @Bindable var coach: CoachModel
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScreenScroll(spacing: RRSpace.l) {
            HStack {
                Spacer()
                ProfileButton()
            }

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                EditorialTitle("What do you want to get better at?", style: .display)
                Text("Honest feedback, a little practice, and the reasons behind it. So next time you need me less.")
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ConnectionNotice()

            VStack(alignment: .leading, spacing: 0) {
                row("Check a message I wrote", detail: "Does it sound natural? Too much? I'll tell you why.", id: "coach-review") {
                    coach.stage = .review
                }
                row("Practise a conversation", detail: "I play the other person. You try things with nothing at stake.", id: "coach-practice") {
                    coach.stage = .practice
                }
                ForEach([CoachTopic.flirting, .conversation, .askingOut, .confidence]) { topic in
                    row(topic.title, detail: topic.blurb, id: "coach-topic-\(topic.rawValue)") {
                        coach.open(topic)
                    }
                }
                Rule()
            }

            Text(allowance)
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
        }
        .safeAreaInset(edge: .bottom) {
            CoachComposer(text: $coach.input, placeholder: "Or ask me anything", isBusy: coach.isThinking, focused: $inputFocused) {
                coach.send(coach.input, app: app)
            }
        }
    }

    private func row(_ title: String, detail: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            MenuRow(title, detail: detail)
        }
        .buttonStyle(.rrPress)
        .accessibilityIdentifier(id)
    }

    private var allowance: String {
        if app.isPro { return "Coaching is included in Pro." }
        guard let coachUsage = app.usage?.coach else { return "The free plan includes a few coaching turns a day." }
        let left = coachUsage.remaining
        return left == 1 ? "1 coaching turn left today on the free plan." : "\(left) coaching turns left today on the free plan."
    }
}

// MARK: - Ask

private struct AskView: View {
    @Environment(AppModel.self) private var app
    @Bindable var coach: CoachModel
    @FocusState private var inputFocused: Bool

    private let bottomID = "coach-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScreenScroll {
                if coach.hasContext {
                    contextNote
                }

                if coach.entries.isEmpty {
                    starters
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
                    FailureNote(error: coach.failure, message: message) {
                        coach.retry()
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
            CoachComposer(text: $coach.input, placeholder: "Ask your coach", isBusy: coach.isThinking, focused: $inputFocused) {
                coach.send(coach.input, app: app)
            }
        }
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            EditorialTitle(coach.topic == .general ? "What's on your mind?" : coach.topic.blurb, style: .title)
                .padding(.top, RRSpace.s)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(coach.topic.starters, id: \.self) { starter in
                    Button {
                        Haptics.tap()
                        coach.send(starter, app: app)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(starter)
                                .rrText(.bodyLarge)
                                .foregroundStyle(Color.rrText)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: RRSpace.xs)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.rrTextTertiary)
                        }
                        .padding(.vertical, RRSpace.m)
                        .overlay(alignment: .top) { Rule() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.rrPress)
                }
                Rule()
            }
        }
    }

    /// Reminds the user what they brought along, and lets them drop it.
    private var contextNote: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            Eyebrow(coach.crush.map { "You brought this along, with \($0.alias)'s profile" } ?? "You brought this along")
            if !coach.draft.trimmed.isEmpty {
                MessageBubble(coach.draft.trimmed, side: .mine, compact: true)
            } else {
                Text(ConversationText.title(latestMessage: nil, fallback: coach.conversation))
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct QuestionRow: View {
    let text: String

    var body: some View {
        Text(text)
            .rrText(.headline)
            .foregroundStyle(Color.rrTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, RRSpace.s)
            .accessibilityLabel("You asked: \(text)")
    }
}

/// One answer: the words, the review if there was a message to look at, lines
/// worth sending, the lesson, and what to ask next.
private struct AnswerBlock: View {
    @Environment(AppModel.self) private var app
    let entry: CoachModel.Entry
    let isLatest: Bool
    let onFollowUp: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            if let mode = entry.mode {
                ProvenanceLabel(mode)
            }
            Text(entry.text)
                .rrText(.bodyLarge)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let headsUp = entry.headsUp, !headsUp.isEmpty {
                HeadsUpNote(headsUp)
            }

            if let review = entry.review {
                ReviewDetail(review: review)
            }

            if !entry.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    ForEach(entry.suggestions, id: \.self) { suggestion in
                        SendableLine(label: suggestion.label, text: suggestion.text)
                    }
                }
            }

            if entry.review == nil, let lesson = entry.lesson, !lesson.isEmpty {
                LessonNote(lesson)
            }

            if isLatest && !entry.followUps.isEmpty {
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

/// A line the user could send, shown as it would look, with a way to copy it.
private struct SendableLine: View {
    @Environment(AppModel.self) private var app
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: RRSpace.xxs) {
            if !label.isEmpty {
                Text(label)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
            }
            MessageBubble(text, side: .mine)
            Button {
                app.copy(text)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.rrQuiet)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The one idea worth keeping from an answer, marked with the pencil.
private struct LessonNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.xxs) {
            Highlighted("Worth remembering", style: .footnote)
            Text(text)
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Worth remembering. \(text)")
    }
}

// MARK: - Review

/// The six parts of feedback on a message, in the order they help:
/// what you mean, how it reads, what to change, a version to try, why, and the lesson.
private struct ReviewDetail: View {
    @Environment(AppModel.self) private var app
    let review: CoachReview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            part("What you're going for", body: review.intent)
            part("How it reads right now", body: review.comesAcross)

            if !review.checks.isEmpty {
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    ForEach(review.checks) { check in
                        CheckRow(check: check)
                    }
                }
                .padding(.vertical, RRSpace.m)
                .overlay(alignment: .top) { Rule() }
            }

            if !review.improvements.isEmpty {
                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Eyebrow("What could be better")
                    ForEach(review.improvements, id: \.self) { item in
                        HStack(alignment: .firstTextBaseline, spacing: RRSpace.xs) {
                            Text("\u{2013}")
                                .rrText(.body)
                                .foregroundStyle(Color.rrTextTertiary)
                            Text(item)
                                .rrText(.body)
                                .foregroundStyle(Color.rrText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, RRSpace.m)
                .overlay(alignment: .top) { Rule() }
            }

            if !review.alternative.trimmed.isEmpty {
                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Eyebrow("Try this")
                    MessageBubble(review.alternative, side: .mine)
                    HStack {
                        Spacer()
                        Button {
                            app.copy(review.alternative)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.rrSecondaryCompact)
                        .accessibilityIdentifier("review-copy")
                    }
                    if !review.whyItWorks.isEmpty {
                        MarginNote(review.whyItWorks)
                    }
                }
                .padding(.vertical, RRSpace.m)
                .overlay(alignment: .top) { Rule() }
            }

            if !review.lesson.isEmpty {
                LessonNote(review.lesson)
                    .padding(.vertical, RRSpace.m)
                    .overlay(alignment: .top) { Rule() }
            }
        }
    }

    @ViewBuilder
    private func part(_ title: String, body text: String) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: RRSpace.xxs) {
                Eyebrow(title)
                Text(text)
                    .rrText(.body)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, RRSpace.m)
            .overlay(alignment: .top) { Rule() }
        }
    }
}

/// One question about the message, its short answer, and the words that caused it.
private struct CheckRow: View {
    let check: CoachReview.Check

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: RRSpace.xs) {
                Text(check.question)
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                Spacer(minLength: RRSpace.xs)
                Text(check.answer)
                    .rrText(.headline)
                    .foregroundStyle(tint)
            }
            if !check.note.isEmpty {
                Text(check.note)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch check.level {
        case .good: return Color.rrSuccess
        case .watch: return Color.rrHighlightInk
        case .rework: return Color.rrDanger
        }
    }
}

private struct ReviewView: View {
    @Environment(AppModel.self) private var app
    @Bindable var coach: CoachModel

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: RRSpace.xs) {
                EditorialTitle("Let's look at what you wrote", style: .title)
                Text("Paste the message. I'll tell you how it reads and what I'd change, and why.")
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, RRSpace.s)

            RRTextArea(text: $coach.reviewDraft, placeholder: "The message you wrote, or are about to send", minHeight: 96)
                .accessibilityIdentifier("review-draft")

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Eyebrow("What do you want it to get across? Optional.")
                RRField("Interested, without sounding too eager", text: $coach.reviewGoal, lineLimit: 2)
                    .accessibilityIdentifier("review-goal")
            }

            if !app.people.isEmpty {
                PersonPicker(selection: $coach.crush, title: "Is this for someone in your notebook?")
            }

            ConnectionNotice()

            Button(coach.reviewOutcome == nil ? "Look at it" : "Look again") {
                Haptics.tap()
                coach.requestReview(app: app)
            }
            .buttonStyle(.rrPrimary)
            .disabled(coach.reviewDraft.trimmed.isEmpty || coach.isThinking)
            .accessibilityIdentifier("review-submit")

            if coach.isThinking {
                ThinkingView(lines: Microcopy.coaching)
            }
            if let message = coach.errorMessage {
                FailureNote(error: coach.failure, message: message) {
                    coach.retry()
                }
            }

            if let outcome = coach.reviewOutcome {
                VStack(alignment: .leading, spacing: RRSpace.m) {
                    ProvenanceLabel(outcome.mode)
                    Text(outcome.message)
                        .rrText(.bodyLarge)
                        .foregroundStyle(Color.rrText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let headsUp = outcome.headsUp, !headsUp.isEmpty {
                        HeadsUpNote(headsUp)
                    }
                    if let review = outcome.review {
                        ReviewDetail(review: review)
                    }
                    if !outcome.followUps.isEmpty {
                        FlowLayout {
                            ForEach(outcome.followUps, id: \.self) { followUp in
                                RRChip(followUp) {
                                    coach.discussReview(followUp, app: app)
                                }
                            }
                        }
                    }
                }
                .accessibilityIdentifier("review-result")
            }
        }
    }
}

// MARK: - Practice

private struct PracticeView: View {
    @Environment(AppModel.self) private var app
    @Bindable var coach: CoachModel
    @State private var customDetail = ""
    @FocusState private var inputFocused: Bool

    private let bottomID = "practice-bottom"

    var body: some View {
        if coach.scenario == nil {
            picker
        } else {
            conversation
        }
    }

    // MARK: Choosing a scenario

    private var picker: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: RRSpace.xs) {
                EditorialTitle("Pick something to practise", style: .title)
                Text("I'll play the other person, an invented one, and tell you what worked after each message. It's a rehearsal, not a prediction of how anyone real would answer.")
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, RRSpace.s)

            ConnectionNotice()

            VStack(alignment: .leading, spacing: 0) {
                ForEach(PracticeScenario.allCases.filter { $0 != .custom }) { scenario in
                    Button {
                        Haptics.tap()
                        coach.startPractice(scenario, detail: "", app: app)
                    } label: {
                        MenuRow(scenario.title, detail: scenario.blurb)
                    }
                    .buttonStyle(.rrPress)
                    .accessibilityIdentifier("practice-\(scenario.rawValue)")
                }
                Rule()
            }

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Or describe your own situation")
                RRField("We matched last week and I haven't said anything yet", text: $customDetail, lineLimit: 4)
                Text("Describe the situation, not a real person. Leave out names and anything private.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Practise this") {
                    Haptics.tap()
                    coach.startPractice(.custom, detail: customDetail, app: app)
                }
                .buttonStyle(.rrSecondaryCompact)
                .disabled(customDetail.trimmed.count < 8)
            }
        }
    }

    // MARK: The rehearsal

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScreenScroll(spacing: RRSpace.m) {
                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Eyebrow("Practice: \(coach.scenario?.id.title ?? "")")
                    if let mode = coach.practiceMode {
                        ProvenanceLabel(mode)
                    }
                    if !coach.practiceIntro.isEmpty {
                        Text(coach.practiceIntro)
                            .rrText(.body)
                            .foregroundStyle(Color.rrTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(coach.practiceTurns) { turn in
                    VStack(alignment: .leading, spacing: RRSpace.xs) {
                        MessageBubble(turn.text, side: turn.role == .user ? .mine : .theirs)
                        if let feedback = turn.feedback, !feedback.isEmpty {
                            MarginNote(feedback)
                        }
                        if let tryThis = turn.tryThis, !tryThis.isEmpty {
                            Text("You could also try: \(tryThis)")
                                .rrText(.footnote)
                                .foregroundStyle(Color.rrTextTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }

                if coach.isThinking {
                    HStack {
                        TypingDots()
                            .foregroundStyle(Color.rrTextSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background {
                                BubbleShape(side: .theirs).fill(Color.rrBubbleTheirs)
                            }
                        Spacer()
                    }
                    .accessibilityLabel("They are typing")
                }

                if let message = coach.errorMessage {
                    FailureNote(error: coach.failure, message: message) {
                        coach.retry()
                    }
                }

                if coach.practiceFinished {
                    VStack(alignment: .leading, spacing: RRSpace.s) {
                        Highlighted("That's a natural place to stop", style: .headline)
                        if !coach.practiceNote.isEmpty {
                            Text(coach.practiceNote)
                                .rrText(.body)
                                .foregroundStyle(Color.rrText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Practise something else") {
                            coach.scenario = nil
                            coach.practiceTurns = []
                            coach.practiceFinished = false
                        }
                        .buttonStyle(.rrSecondaryCompact)
                    }
                    .padding(.top, RRSpace.s)
                }

                Color.clear
                    .frame(height: 1)
                    .id(bottomID)
            }
            .onChange(of: coach.practiceTurns.count) { _, _ in
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
            if !coach.practiceFinished {
                CoachComposer(
                    text: $coach.input,
                    placeholder: coach.practiceTurns.isEmpty ? "Send the first message" : "Your message",
                    isBusy: coach.isThinking,
                    focused: $inputFocused
                ) {
                    coach.sendPractice(coach.input, app: app)
                }
            }
        }
    }
}

// MARK: - Composer

/// The field at the bottom of every coach screen.
private struct CoachComposer: View {
    @Binding var text: String
    let placeholder: String
    let isBusy: Bool
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: RRSpace.xs) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...5)
                .rrText(.body)
                .foregroundStyle(Color.rrText)
                .tint(Color.rrCursor)
                .focused(focused)
                .padding(.horizontal, RRSpace.m)
                .padding(.vertical, 13)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.rrSurface)
                }
                .accessibilityIdentifier("coach-input")

            Button {
                Haptics.tap()
                onSend()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.rrButtonText)
                    .frame(width: 48, height: 48)
                    .background {
                        Circle().fill(Color.rrButtonFill)
                    }
            }
            .disabled(text.trimmed.isEmpty || isBusy)
            .opacity(text.trimmed.isEmpty || isBusy ? 0.35 : 1)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("coach-send")
        }
        .padding(.horizontal, RRSpace.screen)
        .padding(.vertical, RRSpace.xs)
        .background(Color.rrBackground)
        .overlay(alignment: .top) { Rule() }
    }
}
