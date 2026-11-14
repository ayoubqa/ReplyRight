import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// What ReplyRight does, shown with an invented conversation and three replies
/// written in advance. Nothing is sent and the AI is not called, so trying the
/// example costs nothing and uses none of today's free replies. The screen says
/// plainly that these replies were not written by AI.
struct ExampleRepliesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScroll(spacing: RRSpace.l) {
            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Eyebrow("Example")
                EditorialTitle("Here's how it works.", style: .display)
            }

            Label("A made-up chat with replies written in advance by the ReplyRight team. Not written by AI, and nothing was sent.", systemImage: "info.circle")
                .rrText(.footnote)
                .foregroundStyle(Color.rrHighlightInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("example-label")

            VStack(spacing: RRSpace.xs) {
                ForEach(Array(SampleConversation.lines.enumerated()), id: \.offset) { _, line in
                    MessageBubble(line.text, side: line.speaker == .them ? .theirs : .mine)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(conversationLabel)

            VStack(alignment: .leading, spacing: RRSpace.l) {
                Eyebrow("Three ways to answer")
                ForEach(Array(SampleConversation.exampleReplies.enumerated()), id: \.offset) { _, reply in
                    VStack(alignment: .leading, spacing: RRSpace.s) {
                        Text(reply.style)
                            .rrText(.headline)
                            .foregroundStyle(Color.rrAccent)
                        MessageBubble(reply.text, side: .mine)
                        MarginNote(reply.why)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Text("With a real chat, ReplyRight reads that conversation and writes three replies for it, in the way you text. You choose one, edit it if you like, and send it yourself.")
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Button("Try it with a real message") {
                    Haptics.tap()
                    app.homePath = []
                }
                .buttonStyle(.rrPrimary)
                .accessibilityIdentifier("example-try-real")

                if !app.keyboardStatus.isReady {
                    Button("Get this in your keyboard") {
                        app.homePath = []
                        app.openKeyboard(startSetup: true)
                    }
                    .buttonStyle(.rrSecondaryWide)
                    .accessibilityIdentifier("example-keyboard")
                }
            }
        }
        .navigationTitle("Example")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var conversationLabel: String {
        let lines = SampleConversation.lines.map { line in
            (line.speaker == .them ? "Them: " : "You: ") + line.text
        }
        return "Example conversation. " + lines.joined(separator: ". ")
    }
}
