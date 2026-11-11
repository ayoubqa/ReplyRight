import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// "I wrote something, but it isn't right." Bring a draft and choose what should change.
struct DraftPolishView: View {
    @Environment(AppModel.self) private var app
    @State private var board = SuggestionBoard()
    @State private var draft = ""
    @State private var context = ""
    @State private var action: RefineAction = .flirty
    @State private var showsContext = false

    private static let choices: [RefineAction] = [
        .flirty, .playful, .moreConfident, .moreNatural, .lessIntense, .shorter, .funnier, .moreRomantic, .charming, .moreLikeMe,
    ]

    var body: some View {
        ScreenScroll {
            ScreenHeader(
                lead: "Bring me ",
                emphasis: "your draft.",
                subtitle: "You're closer than you think. Let's make it sound natural."
            )

            VStack(alignment: .leading, spacing: RRSpace.s) {
                HStack {
                    Eyebrow("What you've got so far")
                    Spacer()
                    Button {
                        if let copied = UIPasteboard.general.string?.trimmed, !copied.isEmpty {
                            draft = copied
                            Haptics.tap()
                        } else {
                            app.toast = "There's no text on your clipboard yet."
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.rrSecondaryCompact)
                }
                RRTextArea(text: $draft, placeholder: "hey, I was wondering if maybe you'd want to hang out sometime, no worries if not", minHeight: 96)
                    .accessibilityIdentifier("polish-draft")
            }

            ChoiceGroup(
                title: "Make it",
                options: DraftPolishView.choices,
                label: { $0.title },
                selection: $action
            )

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Button {
                    withAnimation(.rrSnappy) { showsContext.toggle() }
                } label: {
                    Label(
                        showsContext ? "Hide what they said" : "Add what they said (optional)",
                        systemImage: showsContext ? "minus.circle" : "plus.circle"
                    )
                }
                .buttonStyle(.rrQuiet)

                if showsContext {
                    RRTextArea(text: $context, placeholder: "Paste their message so the rewrite fits the conversation.", minHeight: 80)
                }
            }

            Button("Rework it") {
                run()
            }
            .buttonStyle(.rrPrimary)
            .disabled(draft.trimmed.isEmpty || board.state == .loading)
            .accessibilityIdentifier("polish-run")

            SuggestionBoardView(
                board: board,
                conversation: context,
                loadingLines: Microcopy.refining,
                onRetry: { run() }
            )

            if board.state == .loaded {
                Button {
                    app.askCoach(question: "Does this sound okay to send?", conversation: context, draft: draft)
                } label: {
                    Label("Not sure? Ask the coach about this draft", systemImage: "lightbulb")
                }
                .buttonStyle(.rrQuiet)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            board.cancel()
        }
    }

    private func run() {
        Haptics.tap()
        board.loadRewrites(
            app: app,
            request: RefineRequest(
                text: draft,
                action: action,
                count: 3,
                conversation: context,
                voice: app.voice.payload
            )
        )
    }
}
