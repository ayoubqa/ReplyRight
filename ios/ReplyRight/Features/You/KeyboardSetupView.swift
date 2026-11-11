import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// How to turn on the ReplyRight keyboard, why Full Access is asked for, and what the keyboard can and cannot see.
struct KeyboardSetupView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var practice = ""

    var body: some View {
        ScreenScroll {
            ScreenHeader(
                lead: "ReplyRight, ",
                emphasis: "right where you type.",
                subtitle: "Rewrite a draft or pull up replies without leaving the chat."
            )

            VStack(alignment: .leading, spacing: RRSpace.l) {
                GuideStep(
                    number: "1",
                    title: "Add the keyboard",
                    detail: "Tap the button below, then Keyboards, and switch on ReplyRight."
                )
                GuideStep(
                    number: "2",
                    title: "Allow Full Access for AI features",
                    detail: "On the same screen, turn on Allow Full Access. Typing works without it. It's only needed for suggestions."
                )
                GuideStep(
                    number: "3",
                    title: "Switch to it in any app",
                    detail: "Touch and hold the globe key on your keyboard and choose ReplyRight."
                )
                Button("Open ReplyRight in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.rrPrimary)
                .accessibilityIdentifier("keyboard-open-settings")
            }
            .rrCard(padding: RRSpace.l)

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Why \u{201C}Full Access\u{201D}?")
                Text("iOS requires Full Access for any keyboard that uses the internet. ReplyRight needs the internet for one thing: sending the text you ask it to work on to our server and bringing suggestions back.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
                Fact("Nothing is sent while you type. Only when you tap Reply or Rewrite.")
                Fact("Only that draft, and any conversation you chose to share, is sent.")
                Fact("Keystrokes are never collected or stored.")
                Fact("AI features switch off in password, code and payment fields.")
                Fact("Prefer not to? Leave Full Access off and use it as a plain keyboard, or just use the app.")
            }
            .rrCard()

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("What the keyboard can see")
                Text("A keyboard can only see the box you're typing in. It can't read the conversation above it in WhatsApp, Instagram, Tinder or Messages, and ReplyRight doesn't pretend to. To get replies that fit the chat, give it the conversation yourself:")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
                Fact("Copy their message, then tap Reply and \u{201C}Use copied message\u{201D} in the keyboard.")
                Fact("Share a screenshot or selected text to ReplyRight and choose \u{201C}Send to my keyboard\u{201D}.")
                Fact("Or tap \u{201C}Use this chat in my keyboard\u{201D} after getting replies in the app.")
            }
            .rrCard()

            keyboardContext

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Try it")
                RRField("Switch keyboards and type here", text: $practice, lineLimit: 4)
                    .accessibilityIdentifier("keyboard-practice")
                Text("Type a rough draft, then tap Rewrite in the ReplyRight bar above the keys.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            }
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            app.reloadSharedState()
        }
    }

    @ViewBuilder
    private var keyboardContext: some View {
        if let context = app.keyboardContext {
            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Shared with your keyboard")
                Text(context.preview)
                    .rrText(.callout)
                    .foregroundStyle(Color.rrText)
                    .lineLimit(3)
                Text("Cleared automatically after a day.")
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
                Button("Clear it now") {
                    app.clearKeyboardContext()
                    app.toast = "Cleared."
                }
                .buttonStyle(.rrSecondaryCompact)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rrCard()
        }
    }
}

/// One plain statement with a tick.
struct Fact: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: RRSpace.xs) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.rrAccent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.rrAccentSoft))
                .padding(.top, 2)
            Text(text)
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
