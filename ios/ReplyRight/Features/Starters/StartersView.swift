import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// Two moments that don't begin with a message to answer:
/// starting (or restarting) a conversation, and suggesting a date.
struct StartersView: View {
    @Environment(AppModel.self) private var app
    let kind: StarterKind

    @State private var board = SuggestionBoard()
    @State private var crush: CrushProfile?
    @State private var situation = ""
    @State private var conversation = ""
    @State private var vibe: Intent = .natural

    private static let vibes: [Intent] = [.natural, .laugh, .flirt, .interest, .confident, .charming]

    var body: some View {
        ScreenScroll {
            switch kind {
            case .opener:
                ScreenHeader(
                    lead: "Start ",
                    emphasis: "the conversation.",
                    subtitle: "Specific beats clever. Tell me a little and I'll skip the pickup lines."
                )
            case .askOut:
                ScreenHeader(
                    lead: "From chatting to ",
                    emphasis: "an actual plan.",
                    subtitle: "The best invitations are specific and easy to say yes or no to."
                )
            }

            PersonPicker(selection: $crush)

            if kind == .askOut {
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    Eyebrow("Where the chat is (optional)")
                    RRTextArea(
                        text: $conversation,
                        placeholder: "Paste the last few messages so the invitation grows out of the conversation.",
                        minHeight: 90
                    )
                }
            }

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow(kind == .opener ? "What do you know about them?" : "Any plan in mind?")
                RRTextArea(
                    text: $situation,
                    placeholder: kind == .opener
                        ? "We matched yesterday. Their profile has a photo on a summit and says they make a mean lasagna."
                        : "Coffee this weekend, or that new ramen place they mentioned.",
                    minHeight: 80
                )
                .accessibilityIdentifier("starter-situation")
            }

            if kind == .opener {
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    Eyebrow("Open with something")
                    FlowLayout {
                        ForEach(StartersView.vibes) { intent in
                            RRChip(
                                intent.shortTitle,
                                systemImage: intent.symbol,
                                isSelected: vibe == intent,
                                isLocked: app.isLocked(intent)
                            ) {
                                if app.isLocked(intent) {
                                    _ = app.requirePro(.intent(intent))
                                } else {
                                    vibe = intent
                                    Haptics.select()
                                }
                            }
                        }
                    }
                }
            }

            Button(kind == .opener ? "Write openers" : "Help me ask") {
                run(regenerate: false)
            }
            .buttonStyle(.rrPrimary)
            .disabled(board.state == .loading)
            .accessibilityIdentifier("starter-run")

            SuggestionBoardView(
                board: board,
                intent: intent,
                conversation: conversation,
                crush: crush,
                onRetry: { run(regenerate: false) },
                onMore: { run(regenerate: true) }
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            board.cancel()
        }
    }

    private var intent: Intent {
        kind == .askOut ? .askOut : vibe
    }

    private func run(regenerate: Bool) {
        let chosen = intent
        if app.isLocked(chosen) {
            _ = app.requirePro(.intent(chosen))
            return
        }
        Haptics.tap()

        let pasted = conversation.trimmed
        let details = situation
        let voice = app.voice.payload
        let person = crush?.payload
        board.loadReplies(app: app, regenerate: regenerate) { avoid in
            RepliesRequest(
                kind: pasted.isEmpty ? .starter : .reply,
                conversation: pasted,
                situation: details,
                intent: chosen,
                avoid: avoid,
                voice: voice,
                crush: person
            )
        }
    }
}
