import Foundation
import Observation
import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// A set of suggestions that is not part of the main conversation flow:
/// reworked drafts, conversation starters, ways to ask someone out.
@MainActor
@Observable
final class SuggestionBoard {
    var state: ComposeModel.LoadState = .idle
    var options: [ReplyOption] = []
    var note = ""
    var headsUp: String?
    var mode: GenerationMode?
    var refiningID: UUID?
    var refineNotice: String?
    /// The typed error behind a failed state.
    var failure: APIError?

    @ObservationIgnored private var seen: [String] = []
    @ObservationIgnored private var work: Task<Void, Never>?

    func cancel() {
        work?.cancel()
        work = nil
    }

    /// Asks for three messages. `makeRequest` receives the options already shown so new ones differ.
    func loadReplies(app: AppModel, regenerate: Bool = false, makeRequest: @escaping ([String]) -> RepliesRequest) {
        work?.cancel()
        if !regenerate { seen = [] }
        options = []
        refineNotice = nil
        failure = nil
        state = .loading
        let request = makeRequest(regenerate ? seen : [])

        work = Task { [weak self] in
            do {
                let envelope = try await app.api.replies(request)
                guard let self, !Task.isCancelled else { return }
                app.record(envelope.usage, mode: envelope.mode)
                if !envelope.result.replies.isEmpty {
                    app.noteSuggestionsShown(mode: envelope.mode)
                }
                self.finish(
                    suggestions: envelope.result.replies,
                    note: envelope.result.note,
                    headsUp: envelope.result.headsUp,
                    mode: envelope.mode
                )
            } catch let error as APIError {
                guard let self, !Task.isCancelled, error != .cancelled else { return }
                self.failure = error
                self.state = .failed(app.present(error))
            } catch {
                self?.failure = nil
                self?.state = .failed("Something went wrong. Please try again.")
            }
        }
    }

    /// Asks for three reworked versions of a draft.
    func loadRewrites(app: AppModel, request: RefineRequest) {
        work?.cancel()
        options = []
        refineNotice = nil
        failure = nil
        state = .loading

        work = Task { [weak self] in
            do {
                let envelope = try await app.api.refine(request)
                guard let self, !Task.isCancelled else { return }
                app.record(envelope.usage, mode: envelope.mode)
                if !envelope.result.options.isEmpty {
                    app.noteSuggestionsShown(mode: envelope.mode)
                }
                self.finish(
                    suggestions: envelope.result.options,
                    note: envelope.result.note ?? "",
                    headsUp: nil,
                    mode: envelope.mode
                )
            } catch let error as APIError {
                guard let self, !Task.isCancelled, error != .cancelled else { return }
                self.failure = error
                self.state = .failed(app.present(error))
            } catch {
                self?.failure = nil
                self?.state = .failed("Something went wrong. Please try again.")
            }
        }
    }

    private func finish(suggestions: [Suggestion], note: String, headsUp: String?, mode: GenerationMode) {
        self.options = suggestions.map { ReplyOption(suggestion: $0) }
        self.seen = Array((seen + suggestions.map(\.text)).suffix(RequestLimits.avoidReplies))
        self.note = note
        self.headsUp = headsUp
        self.mode = mode
        self.state = .loaded
        if !options.isEmpty {
            Haptics.success()
        }
    }

    func refine(optionID: UUID, action: RefineAction, conversation: String, crush: CrushProfile?, app: AppModel) {
        guard refiningID == nil, let option = options.first(where: { $0.id == optionID }) else { return }
        refiningID = optionID
        refineNotice = nil
        let request = RefineRequest(
            text: option.text,
            action: action,
            count: 1,
            conversation: conversation,
            voice: app.voice.payload,
            crush: crush?.payload
        )

        Task { [weak self] in
            do {
                let envelope = try await app.api.refine(request)
                guard let self else { return }
                app.record(envelope.usage, mode: envelope.mode)
                if let suggestion = envelope.result.options.first,
                   let index = self.options.firstIndex(where: { $0.id == optionID }) {
                    withAnimation(.rrSnappy) {
                        self.options[index].apply(suggestion)
                    }
                    Haptics.tap()
                }
                self.refineNotice = envelope.result.note
                self.refiningID = nil
            } catch let error as APIError {
                self?.refineNotice = error == .cancelled ? nil : app.present(error)
                self?.refiningID = nil
            } catch {
                self?.refineNotice = "That tweak didn't go through. Try again."
                self?.refiningID = nil
            }
        }
    }
}

/// Renders a board: loading, failure, or the suggestions.
struct SuggestionBoardView: View {
    @Environment(AppModel.self) private var app
    @Bindable var board: SuggestionBoard
    var intent: Intent? = nil
    var conversation: String = ""
    var crush: CrushProfile? = nil
    var loadingLines: [String] = Microcopy.writing
    let onRetry: () -> Void
    var onMore: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            switch board.state {
            case .idle:
                EmptyView()
            case .loading:
                ThinkingView(lines: loadingLines)
            case .failed(let message):
                FailureNote(error: board.failure, message: message, retry: onRetry)
            case .loaded:
                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    if !board.note.isEmpty {
                        Text(board.note)
                            .rrText(.titleSmall)
                            .foregroundStyle(Color.rrText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let mode = board.mode {
                        ProvenanceLabel(mode)
                    }
                }
                if let headsUp = board.headsUp, !headsUp.isEmpty {
                    HeadsUpNote(headsUp)
                }
                if board.options.isEmpty {
                    Text("Nothing to suggest this time. Try changing what you asked for.")
                        .rrText(.callout)
                        .foregroundStyle(Color.rrTextSecondary)
                } else {
                    ForEach($board.options) { $option in
                        ReplyCard(
                            option: $option,
                            isDemo: board.mode == .demo,
                            isLive: board.mode == .live,
                            isRefining: board.refiningID == option.id,
                            intent: intent,
                            crushID: crush?.id,
                            onRefine: { action in
                                board.refine(
                                    optionID: option.id,
                                    action: action,
                                    conversation: conversation,
                                    crush: crush,
                                    app: app
                                )
                            }
                        )
                    }
                    if let notice = board.refineNotice, !notice.isEmpty {
                        MarginNote(notice)
                    }
                    if let onMore {
                        Button {
                            Haptics.tap()
                            onMore()
                        } label: {
                            Label("Three more", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.rrSecondaryCompact)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.rrGentle, value: board.state)
    }
}
