import Foundation

/// An invented conversation for showing how ReplyRight works without a real
/// chat at hand: "Try an example" on Home and in onboarding.
///
/// The example never calls the AI. Its three replies are written in advance,
/// and every screen that shows them says so. No real person is involved.
public enum SampleConversation {
    public static let lines: [(speaker: Speaker, text: String)] = [
        (.them, "ok be honest. pineapple on pizza?"),
        (.me, "depends who's asking"),
        (.them, "someone deciding whether we can be friends"),
    ]

    /// The conversation as pasted text, labelled so the reader knows who said what.
    public static var text: String {
        lines.map { line in
            let label = line.speaker == .them ? "Them" : "Me"
            return label + ": " + line.text
        }
        .joined(separator: "\n")
    }

    /// Their last message.
    public static var lastMessage: String {
        lines.last { $0.speaker == .them }?.text ?? ""
    }

    /// Three replies written in advance by the ReplyRight team, to show the
    /// shape of a real result: three different approaches, each with its reason.
    /// They are not AI output and are never presented as such.
    public static let exampleReplies: [Suggestion] = [
        Suggestion(
            style: "Playful",
            text: "then I'm pro-pineapple. obviously. did I pass?",
            why: "Plays along with the joke and hands the question back, so it's their turn to talk."
        ),
        Suggestion(
            style: "Honest",
            text: "honestly yes, sweet and salty is elite. hope we can still be friends",
            why: "Gives a real opinion and keeps it light. Having a view is more interesting than dodging."
        ),
        Suggestion(
            style: "Curious",
            text: "wait, what's the right answer here? tell me yours first",
            why: "Turns it into a question about them, which keeps the conversation two-sided."
        ),
    ]
}
