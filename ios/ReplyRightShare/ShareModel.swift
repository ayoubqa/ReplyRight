import Foundation
import Observation
import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// State and actions for the share sheet.
///
/// Reading what was shared happens on the device. The network is only used
/// after the user taps "Write replies" or "Send to my keyboard".
@MainActor
@Observable
final class ShareModel {
    enum Job: Equatable {
        case replies
        case keyboard
    }

    enum Phase: Equatable {
        /// Reading the shared items locally.
        case loading
        /// The app has not been opened and set up yet.
        case needsSetup
        case nothingShared
        /// Showing what was shared and waiting for the user to choose.
        case ready
        case working(Job)
        case replies
        case sentToKeyboard
        case savedForLater
        case failed(message: String, suggestsUpgrade: Bool, job: Job?)
    }

    private(set) var phase: Phase = .loading
    private(set) var sharedText = ""
    private(set) var shots: [PreparedShot] = []
    private(set) var intent: Intent = .natural

    private(set) var note = ""
    private(set) var headsUp: String?
    private(set) var options: [ReplyOption] = []
    private(set) var isDemo = false
    private(set) var copiedID: UUID?
    var toast: String?

    private(set) var appearance: AppSettings.Appearance = .evening

    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var seen: [String] = []
    @ObservationIgnored private var copyCount = 0

    private let store: SharedStore
    private let api: APIClient
    private let plan: PlanInfo
    private let isSetUp: Bool

    init(store: SharedStore = .shared) {
        self.store = store
        self.api = APIClient.standard(component: "share", store: store)

        let settings = store.loadSettings()
        self.isSetUp = settings.hasOnboarded && settings.confirmedAdult
        self.plan = store.loadService().plans.plan(for: store.lastKnownTier())
        self.appearance = settings.appearance
        Haptics.isEnabled = settings.hapticsEnabled

        if let firstOpen = Intent.quickChoices.first(where: { self.plan.includes($0) }) {
            self.intent = firstOpen
        }
    }

    // MARK: Derived state

    var images: [Data] { shots.map(\.data) }

    var hasScreenshots: Bool { !shots.isEmpty }

    /// A short excerpt of the shared text for the preview bubble.
    var textPreview: String {
        ConversationText.clampRecent(sharedText, limit: 320)
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .evening: return .dark
        case .daylight: return .light
        case .system: return nil
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch appearance {
        case .evening: return .dark
        case .daylight: return .light
        case .system: return .unspecified
        }
    }

    func isLocked(_ intent: Intent) -> Bool {
        !plan.includes(intent)
    }

    // MARK: Loading (local only)

    func load(from items: [NSExtensionItem]) {
        guard isSetUp else {
            // Nothing is read before the 18+ confirmation in the app.
            phase = .needsSetup
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            let content = await ShareItemLoader.load(from: items)
            guard let self, !Task.isCancelled else { return }
            self.sharedText = content.text
            self.shots = content.shots
            self.phase = content.isEmpty ? .nothingShared : .ready
        }
    }

    // MARK: Choosing

    func choose(_ candidate: Intent) {
        if isLocked(candidate) {
            Haptics.warning()
            toast = "\(candidate.shortTitle) is part of Pro. Open ReplyRight to see plans."
            return
        }
        Haptics.select()
        intent = candidate
    }

    // MARK: Write replies

    func writeReplies(regenerate: Bool = false) {
        task?.cancel()
        phase = .working(.replies)

        let request = RepliesRequest(
            conversation: sharedText,
            intent: intent,
            avoid: regenerate ? seen : [],
            voice: store.loadVoice().payload
        )
        let attachments = images

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let envelope = try await self.api.replies(request, images: attachments)
                if Task.isCancelled { return }
                self.store.record(usage: envelope.usage, mode: envelope.mode)
                self.show(envelope, regenerate: regenerate)
            } catch {
                if Task.isCancelled { return }
                self.fail(error, job: .replies)
            }
        }
    }

    private func show(_ envelope: Envelope<RepliesResult>, regenerate: Bool) {
        let texts = envelope.result.replies.map(\.text)
        seen = Array((regenerate ? seen + texts : texts).suffix(RequestLimits.avoidReplies))
        note = envelope.result.note
        headsUp = envelope.result.headsUp
        options = envelope.result.replies.map { ReplyOption(suggestion: $0) }
        isDemo = envelope.mode == .demo
        copiedID = nil
        phase = .replies
        // On-device counts only, and only for live AI. See ProductActivity.
        if envelope.mode == .live, !options.isEmpty {
            store.recordActivity(.suggestionsShown(.share))
        }
    }

    func copy(_ option: ReplyOption) {
        UIPasteboard.general.string = option.text
        Haptics.success()
        if !isDemo {
            store.recordActivity(.suggestionUsed(.share))
        }
        copiedID = option.id
        copyCount += 1
        toast = Microcopy.pick(Microcopy.copied, seed: copyCount)
    }

    // MARK: Send to my keyboard

    func sendToKeyboard() {
        guard hasScreenshots else {
            saveKeyboardContext(sharedText)
            return
        }

        // The keyboard only ever receives text. Screenshots are read once, in
        // memory on the server, and the transcript is what gets saved.
        task?.cancel()
        phase = .working(.keyboard)
        let request = AnalyzeRequest(conversation: sharedText)
        let attachments = images

        task = Task { [weak self] in
            guard let self else { return }
            do {
                let envelope = try await self.api.analyze(request, images: attachments)
                if Task.isCancelled { return }
                self.store.record(usage: envelope.usage, mode: envelope.mode)

                let transcript = ConversationText.render(envelope.result.transcript).trimmed
                let text = transcript.isEmpty ? self.sharedText : transcript
                if text.trimmed.isEmpty {
                    let reason = envelope.mode == .demo
                        ? "Screenshots can't be read in demo mode. Share the text of the conversation instead."
                        : "I couldn't find any messages in that screenshot. Try a clearer one, or share the text."
                    self.phase = .failed(message: reason, suggestsUpgrade: false, job: nil)
                } else {
                    self.saveKeyboardContext(text)
                }
            } catch {
                if Task.isCancelled { return }
                self.fail(error, job: .keyboard)
            }
        }
    }

    private func saveKeyboardContext(_ text: String) {
        let clean = text.trimmed
        guard !clean.isEmpty else {
            phase = .failed(message: "There's no text here to hand to the keyboard.", suggestsUpgrade: false, job: nil)
            return
        }
        if store.saveKeyboardContext(KeyboardContext(text: clean, source: .shareSheet)) {
            Haptics.success()
            phase = .sentToKeyboard
        } else {
            phase = .failed(message: "I couldn't save that for the keyboard. Please try again.", suggestsUpgrade: false, job: .keyboard)
        }
    }

    // MARK: Open in ReplyRight later

    func saveForLater() {
        if store.saveInbox(text: sharedText, images: images) != nil {
            Haptics.success()
            phase = .savedForLater
        } else {
            phase = .failed(message: "I couldn't save that for later. Please try again.", suggestsUpgrade: false, job: nil)
        }
    }

    // MARK: Errors and navigation

    private func fail(_ error: Error, job: Job) {
        let apiError = (error as? APIError) ?? APIError.server(message: "Something went wrong. Please try again.")
        if apiError == .cancelled {
            phase = .ready
            return
        }
        if let usage = apiError.usage {
            store.record(usage: usage, mode: nil)
        }
        Haptics.warning()
        phase = .failed(message: apiError.userMessage, suggestsUpgrade: apiError.suggestsUpgrade, job: job)
    }

    func retry() {
        guard case .failed(_, _, let job) = phase else { return }
        switch job {
        case .replies:
            writeReplies(regenerate: false)
        case .keyboard:
            sendToKeyboard()
        case nil:
            phase = .ready
        }
    }

    func backToStart() {
        task?.cancel()
        phase = .ready
    }

    /// Ends the share sheet. Any request still in flight is cancelled.
    func close() {
        task?.cancel()
        task = nil
        onFinish?()
    }
}
