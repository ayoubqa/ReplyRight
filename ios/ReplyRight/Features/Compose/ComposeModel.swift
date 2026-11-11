import Foundation
import Observation
import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// One pass through the core experience:
/// share a conversation, understand it, choose what the reply should do, get three options.
///
/// Everything here lives in memory. Screenshots are held only until the
/// conversation has been read; nothing is saved unless the user saves a session.
@MainActor
@Observable
final class ComposeModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// A screenshot prepared for upload, with a preview for the screen.
    struct Shot: Identifiable {
        let id = UUID()
        let jpeg: Data
        let preview: UIImage
    }

    // Input
    var text = ""
    var shots: [Shot] = []
    var isPreparingImages = false
    var inputNotice: String?
    var crush: CrushProfile?

    // Understanding
    var analysisState: LoadState = .idle
    var analysis: Analysis?
    var transcript: [TranscriptLine] = []

    // Intent
    var intent: Intent = .natural
    /// True once the user (or a shortcut) picked the intent, so a suggestion never overrides it.
    var intentWasChosen = false
    var instruction = ""

    // Replies
    var repliesState: LoadState = .idle
    var note = ""
    var headsUp: String?
    var options: [ReplyOption] = []
    var mode: GenerationMode?
    var refiningID: UUID?
    var refineNotice: String?
    var savedSessionID: UUID?

    @ObservationIgnored private var seen: [String] = []
    @ObservationIgnored private var work: Task<Void, Never>?

    var hasInput: Bool {
        !shots.isEmpty || text.trimmed.count >= 2
    }

    var canAddShots: Bool {
        shots.count < RequestLimits.maxImages
    }

    /// The conversation as text: what was read from the screenshots when there is a transcript, otherwise what was pasted.
    var conversationText: String {
        transcript.isEmpty ? text.trimmed : ConversationText.render(transcript)
    }

    // MARK: Input

    func reset() {
        work?.cancel()
        work = nil
        text = ""
        shots = []
        isPreparingImages = false
        inputNotice = nil
        crush = nil
        analysisState = .idle
        analysis = nil
        transcript = []
        intent = .natural
        intentWasChosen = false
        instruction = ""
        resetReplies()
    }

    private func resetReplies() {
        repliesState = .idle
        note = ""
        headsUp = nil
        options = []
        refiningID = nil
        refineNotice = nil
        savedSessionID = nil
        seen = []
    }

    /// Prepares images picked from the photo library: downsized, re-encoded, metadata removed.
    func addImages(_ rawItems: [Data]) async {
        guard !rawItems.isEmpty else { return }
        inputNotice = nil
        isPreparingImages = true
        defer { isPreparingImages = false }

        for raw in rawItems {
            guard canAddShots else {
                inputNotice = "You can add up to \(RequestLimits.maxImages) screenshots."
                break
            }
            let prepared = await Task.detached(priority: .userInitiated) {
                ScreenshotPreparer.prepare(raw)
            }.value
            if let prepared, let preview = UIImage(data: prepared) {
                shots.append(Shot(jpeg: prepared, preview: preview))
            } else {
                inputNotice = "One of those couldn't be read. Try a regular screenshot."
            }
        }
    }

    /// Adds images that were already prepared (by the share sheet).
    func addPrepared(_ jpegs: [Data]) {
        for jpeg in jpegs where canAddShots {
            if let preview = UIImage(data: jpeg) {
                shots.append(Shot(jpeg: jpeg, preview: preview))
            }
        }
    }

    func removeShot(_ id: UUID) {
        shots.removeAll { $0.id == id }
        inputNotice = nil
    }

    /// Restores a saved session so it can be reviewed or continued. Saved sessions hold text only.
    func load(session: SavedSession, person: CrushProfile?) {
        reset()
        text = session.conversation
        crush = person
        intent = session.intent
        intentWasChosen = true
        instruction = session.instruction
        options = session.options
        seen = session.options.map(\.text)
        note = session.read
        repliesState = .loaded
        savedSessionID = session.id
    }

    // MARK: Understanding

    func startAnalysis(app: AppModel) {
        work?.cancel()
        resetReplies()
        analysis = nil
        transcript = []
        analysisState = .loading

        let request = AnalyzeRequest(conversation: text, crush: crush?.payload)
        let images = shots.map(\.jpeg)

        work = Task { [weak self] in
            do {
                let envelope = try await app.api.analyze(request, images: images)
                guard let self, !Task.isCancelled else { return }
                app.record(envelope.usage, mode: envelope.mode)
                self.mode = envelope.mode
                self.analysis = envelope.result
                self.transcript = envelope.result.transcript
                if !self.intentWasChosen,
                   let suggested = envelope.result.suggestedIntents.first(where: { !app.isLocked($0) }) {
                    self.intent = suggested
                }
                self.analysisState = .loaded
            } catch let error as APIError {
                guard let self, !Task.isCancelled, error != .cancelled else { return }
                self.analysisState = .failed(app.present(error))
            } catch {
                self?.analysisState = .failed("Something went wrong. Please try again.")
            }
        }
    }

    /// Lets the user correct who said a line when a screenshot was read the wrong way round.
    func cycleSpeaker(_ lineID: UUID) {
        guard let index = transcript.firstIndex(where: { $0.id == lineID }) else { return }
        transcript[index].speaker = transcript[index].speaker.next
    }

    // MARK: Replies

    func startReplies(app: AppModel, regenerate: Bool = false) {
        work?.cancel()
        if !regenerate {
            seen = []
        }
        options = []
        refineNotice = nil
        savedSessionID = nil
        repliesState = .loading

        // Once the conversation has been read, only its text is sent. Screenshots are needed
        // again only if there is no transcript to work from.
        let needsImages = transcript.isEmpty && !shots.isEmpty
        let request = RepliesRequest(
            kind: .reply,
            conversation: transcript.isEmpty ? text : "",
            transcript: transcript,
            intent: intent,
            instruction: instruction,
            avoid: regenerate ? seen : [],
            voice: app.voice.payload,
            crush: crush?.payload
        )
        let images = needsImages ? shots.map(\.jpeg) : []

        work = Task { [weak self] in
            do {
                let envelope = try await app.api.replies(request, images: images)
                guard let self, !Task.isCancelled else { return }
                app.record(envelope.usage, mode: envelope.mode)
                self.mode = envelope.mode
                self.note = envelope.result.note
                self.headsUp = envelope.result.headsUp
                self.options = envelope.result.replies.map { ReplyOption(suggestion: $0) }
                self.seen = Array((self.seen + envelope.result.replies.map(\.text)).suffix(RequestLimits.avoidReplies))
                self.repliesState = .loaded
                if !self.options.isEmpty {
                    Haptics.success()
                }
            } catch let error as APIError {
                guard let self, !Task.isCancelled, error != .cancelled else { return }
                self.repliesState = .failed(app.present(error))
            } catch {
                self?.repliesState = .failed("Something went wrong. Please try again.")
            }
        }
    }

    /// Reworks one option in place. The previous wording is kept so it can be undone.
    func refine(optionID: UUID, action: RefineAction, app: AppModel) {
        guard refiningID == nil, let option = options.first(where: { $0.id == optionID }) else { return }
        refiningID = optionID
        refineNotice = nil

        let request = RefineRequest(
            text: option.text,
            action: action,
            count: 1,
            conversation: conversationText,
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

    /// A snapshot the user can keep. Text only: screenshots are never saved.
    func makeSession() -> SavedSession {
        let id = savedSessionID ?? UUID()
        savedSessionID = id
        return SavedSession(
            id: id,
            title: ConversationText.title(latestMessage: analysis?.latestMessage, fallback: conversationText),
            conversation: conversationText,
            read: analysis?.read ?? note,
            intent: intent,
            instruction: instruction,
            options: options,
            crushID: crush?.id
        )
    }
}
