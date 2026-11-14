import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

// The Keyboard tab: set up, test and get the most out of the ReplyRight keyboard.
//
// What the app can and cannot know. iOS gives an app no way to ask whether its
// keyboard is switched on or has Full Access. Everything shown here comes from
// what the keyboard itself reported (a check-in, which needs Full Access, or
// the test sentence typed into the field on this screen) or from what the user
// told us. It is always shown as "last confirmed", never as a live reading.

struct KeyboardTab: View {
    var body: some View {
        NavigationStack {
            KeyboardHubView()
        }
    }
}

struct KeyboardHubView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScreenScroll(spacing: RRSpace.l) {
            HStack(alignment: .center) {
                Eyebrow("ReplyRight Keyboard")
                Spacer()
                ProfileButton()
            }

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                EditorialTitle("Replies, right where you type.", style: .display)
                Text("Reply to a message you copied, or rewrite your draft, without leaving the chat. You stay in charge: nothing is sent until you tap.")
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            KeyboardPreview(highlight: app.keyboardStatus.isReady ? .reply : nil)

            KeyboardStatusPanel()

            KeyboardTestSection()

            HowToUseSection()

            FullAccessExplainer()

            whatItSees

            sharedContext

            preferences

            TypingNotes()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { app.reloadSharedState() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings or another app: pick up a fresh check-in.
            if phase == .active { app.reloadSharedState() }
        }
    }

    private var whatItSees: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("What the keyboard can see")
            Text("Only the box you're typing in. It can't read the conversation above it in WhatsApp, Instagram, Tinder or Messages, and ReplyRight doesn't pretend to. You give it the conversation yourself:")
                .rrText(.callout)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
            Fact("Copy their message, then tap Reply. The keyboard offers what you copied, and shows it before anything is sent.")
            Fact("Share a screenshot or selected text to ReplyRight and choose \u{201C}Send to my keyboard\u{201D}.")
            Fact("Or tap \u{201C}Use this chat in my keyboard\u{201D} after getting replies in the app.")
        }
        .rrCard()
    }

    @ViewBuilder
    private var sharedContext: some View {
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
                .accessibilityIdentifier("keyboard-clear-context")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .rrCard()
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("In your keyboard")
                .padding(.bottom, RRSpace.xxs)
            NavigationLink {
                SavedRepliesView()
            } label: {
                MenuRow(
                    "Saved lines",
                    detail: app.savedReplies.isEmpty
                        ? "Bookmark a reply in the app and it shows up under the bookmark in your keyboard."
                        : "Tap the bookmark in the keyboard to drop one into any chat.",
                    trailing: app.savedReplies.isEmpty ? nil : "\(app.savedReplies.count)"
                )
            }
            .buttonStyle(.rrPress)
            .accessibilityIdentifier("keyboard-saved")

            if !app.people.isEmpty {
                defaultPerson
            }
            Rule()
        }
    }

    /// Whose profile the keyboard uses as context unless the user picks someone else there.
    private var defaultPerson: some View {
        Menu {
            Button("No one in particular") { setKeyboardPerson(nil) }
            ForEach(app.people) { person in
                Button(person.alias) { setKeyboardPerson(person.id) }
            }
        } label: {
            MenuRow(
                "Who it's about",
                detail: "Used as context for keyboard replies unless you pick someone else there. Only the parts of a profile you allowed are sent.",
                trailing: app.person(app.settings.keyboardCrushID)?.alias ?? "No one",
                showsChevron: false
            )
        }
        .buttonStyle(.rrPress)
        .accessibilityIdentifier("keyboard-default-person")
    }

    private func setKeyboardPerson(_ id: UUID?) {
        Haptics.select()
        app.settings.keyboardCrushID = id
    }
}

// MARK: - Status

/// The keyboard's setup state, what it means, and the one next step.
struct KeyboardStatusPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let status = app.keyboardStatus
        VStack(alignment: .leading, spacing: RRSpace.s) {
            KeyboardStatusBadge(status: status)
            Text(status.explanation)
                .rrText(.body)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = evidenceLine(status) {
                Text(detail)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action(for: status)
            Text("iOS doesn't let apps check this directly. This is what your keyboard last reported, or what you told us.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rrPanel()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard-status")
    }

    private func evidenceLine(_ status: KeyboardSetupStatus) -> String? {
        guard let date = status.evidenceDate else { return nil }
        let when = date.formatted(.relative(presentation: .named))
        switch status {
        case .notSetUp: return nil
        case .enabledNotTested: return "You said it was on \(when)."
        case .limitedAccess: return "Last test \(when): typing worked, Full Access was off."
        case .ready: return "Last confirmed \(when)."
        }
    }

    @ViewBuilder
    private func action(for status: KeyboardSetupStatus) -> some View {
        switch status {
        case .notSetUp:
            Button("Set up the keyboard") { app.showsKeyboardSetup = true }
                .buttonStyle(.rrPrimary)
                .accessibilityIdentifier("keyboard-setup")
        case .enabledNotTested:
            Button("Finish setup") { app.showsKeyboardSetup = true }
                .buttonStyle(.rrPrimary)
                .accessibilityIdentifier("keyboard-setup")
        case .limitedAccess:
            Button("Turn on Full Access") { app.showsKeyboardSetup = true }
                .buttonStyle(.rrPrimary)
                .accessibilityIdentifier("keyboard-setup")
        case .ready:
            Button("Walk through setup again") { app.showsKeyboardSetup = true }
                .buttonStyle(.rrSecondaryCompact)
                .accessibilityIdentifier("keyboard-setup")
        }
    }
}

/// A small mark and label for the status. Shape and words carry the meaning,
/// not colour alone.
struct KeyboardStatusBadge: View {
    let status: KeyboardSetupStatus

    var body: some View {
        HStack(spacing: RRSpace.xs) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(status.title)
                .rrText(.headline)
                .foregroundStyle(Color.rrText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard status: \(status.title)")
        .accessibilityIdentifier("keyboard-status-badge")
    }

    private var symbol: String {
        switch status {
        case .notSetUp: return "circle.dashed"
        case .enabledNotTested: return "questionmark.circle"
        case .limitedAccess: return "exclamationmark.circle"
        case .ready: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .notSetUp: return .rrTextSecondary
        case .enabledNotTested: return .rrHighlightInk
        case .limitedAccess: return .rrWarning
        case .ready: return .rrSuccess
        }
    }
}

// MARK: - Test field

/// A field to try the keyboard in. When the keyboard types its test sentence
/// here, the app records the result. Nothing typed here is sent or kept.
struct KeyboardTestSection: View {
    @Environment(AppModel.self) private var app
    @State private var text = ""
    @State private var result: KeyboardHandshake.Result?
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            if showsHeader {
                Eyebrow("Test it here")
            }
            RRField("Tap here, then switch to ReplyRight", text: $text, lineLimit: 4)
                .accessibilityIdentifier("keyboard-practice")
            Text("Switch keyboards with the globe key, tap the ReplyRight mark at the left of the bar, then Type a test message. Or type a rough draft and tap Rewrite.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let result {
                TestResultNote(result: result)
                    .transition(.opacity)
            }
        }
        .onChange(of: text) { _, newText in
            guard let found = KeyboardHandshake.detect(in: newText), found != result else { return }
            result = found
            app.recordKeyboardTest(found)
            UIAccessibility.post(
                notification: .announcement,
                argument: found.hasFullAccess
                    ? "ReplyRight keyboard works, with Full Access."
                    : "ReplyRight keyboard works for typing. Full Access is off."
            )
        }
        .animation(.rrGentle, value: result)
    }
}

private struct TestResultNote: View {
    let result: KeyboardHandshake.Result

    var body: some View {
        HStack(alignment: .top, spacing: RRSpace.xs) {
            Image(systemName: result.hasFullAccess ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(result.hasFullAccess ? Color.rrSuccess : Color.rrWarning)
                .accessibilityHidden(true)
            Text(result.hasFullAccess
                 ? "It works. Full Access is on, so Reply and Rewrite are ready in your chats."
                 : "The keyboard works for typing, but Full Access is off. Turn it on to get replies.")
                .rrText(.callout)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("keyboard-test-result")
    }
}

// MARK: - How to use it

private struct HowToUseSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            Eyebrow("Using it in a chat")
            GuideStep(number: "1", title: "Copy their message", detail: "Touch and hold it in the chat, then tap Copy.")
            GuideStep(number: "2", title: "Switch to ReplyRight", detail: "Tap the reply box, then touch and hold the globe key and choose ReplyRight.")
            GuideStep(number: "3", title: "Tap Reply", detail: "Check it's the right message, pick a tone, and tap Write replies.")
            GuideStep(number: "4", title: "Tap the one you like", detail: "It goes into the box. Edit it if you want. You send it yourself.")
            Text("Already typed something? Tap Rewrite instead and pick how it should sound.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rrCard()
    }
}

// MARK: - Full Access

/// Why Full Access is asked for, what it enables, and how the text is handled.
struct FullAccessExplainer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("About Full Access")
            Text("iOS requires Full Access for any keyboard that uses the internet. ReplyRight needs it to send the text you ask about to our server and bring suggestions back.")
                .rrText(.callout)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)

            Text("What it turns on")
                .rrText(.headline)
                .foregroundStyle(Color.rrText)
                .padding(.top, RRSpace.xxs)
            Fact("Reply and Rewrite, inside any app.")
            Fact("Your saved lines and people from the app, in the keyboard.")
            Fact("Using a message you copied as what you're replying to.")

            Text("How your text is handled")
                .rrText(.headline)
                .foregroundStyle(Color.rrText)
                .padding(.top, RRSpace.xxs)
            Fact("Nothing is sent while you type. Only when you tap Reply or Rewrite.")
            Fact("Only that draft, and the conversation you chose to give it, is sent.")
            Fact("Keystrokes are never collected or stored, and nothing is sent automatically to anyone.")
            Fact("Suggestions switch off in password, code and payment fields.")
            Fact("The keyboard tells this app only when it last opened and how many suggestions you used. Numbers, never text.")

            Text("When you switch it on, iOS shows its own warning that a keyboard with Full Access could send what you type. That warning appears for every keyboard. ReplyRight only sends text when you tap one of its buttons.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, RRSpace.xxs)
            Text("Prefer not to? Leave Full Access off and use it as a plain keyboard, or use the app and the share sheet instead.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rrCard()
    }
}

// MARK: - Typing

/// What ordinary typing includes today, stated plainly.
private struct TypingNotes: View {
    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Typing")
            Fact("English and Spanish layouts. Tap EN or ES in the bar to switch.")
            Fact("Hold a letter for accents, double-tap shift for caps lock, double space for a full stop.")
            Text("Not yet in the ReplyRight keyboard: autocorrect, predictions and emoji. iOS doesn't let any third-party keyboard use dictation. For those, tap the globe key to switch back to the iPhone keyboard, then switch again when you want a reply.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rrCard()
    }
}

// MARK: - Setup journey

/// Four guided steps: add the keyboard, allow Full Access, test it, use it.
struct KeyboardSetupJourney: View {
    enum Step: Int, CaseIterable {
        case add
        case fullAccess
        case test
        case use

        var title: String {
            switch self {
            case .add: return "Add the keyboard"
            case .fullAccess: return "Allow Full Access"
            case .test: return "Test it"
            case .use: return "Use it in a chat"
            }
        }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var step: Step = .add

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: RRSpace.l) {
                progress

                switch step {
                case .add: addStep
                case .fullAccess: fullAccessStep
                case .test: testStep
                case .use: useStep
                }
            }
            .navigationTitle("Keyboard setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("setup-close")
                }
            }
            .animation(.rrGentle, value: step)
        }
        .onAppear { step = startingStep }
    }

    /// Picks up where the evidence says the user is.
    private var startingStep: Step {
        switch app.keyboardStatus {
        case .notSetUp: return .add
        case .enabledNotTested, .limitedAccess: return .fullAccess
        case .ready: return .test
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? Color.rrAccent : Color.rrLineStrong)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count): \(step.title)")
        }
    }

    // Step 1
    private var addStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                lead: "Add the ",
                emphasis: "ReplyRight keyboard",
                subtitle: "It takes about a minute, and you only do it once."
            )
            VStack(alignment: .leading, spacing: RRSpace.m) {
                GuideStep(number: "1", title: "Open ReplyRight in Settings", detail: "The button below takes you straight there.")
                GuideStep(number: "2", title: "Tap Keyboards", detail: "Then switch on ReplyRight.")
                GuideStep(number: "3", title: "Come back here", detail: "Swipe back to ReplyRight when you're done.")
            }
            openSettingsButton
            Button("I've switched it on") {
                app.confirmKeyboardEnabled()
                Haptics.success()
                step = .fullAccess
            }
            .buttonStyle(.rrSecondaryWide)
            .accessibilityIdentifier("setup-confirm-enabled")
            Text("The app can't see your Settings. We'll check the keyboard really works in step 3.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Step 2
    private var fullAccessStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                lead: "Allow ",
                emphasis: "Full Access",
                subtitle: "This is what lets the keyboard write replies. Typing works without it."
            )
            VStack(alignment: .leading, spacing: RRSpace.m) {
                GuideStep(number: "1", title: "Open ReplyRight in Settings", detail: "Then Keyboards.")
                GuideStep(number: "2", title: "Switch on Allow Full Access", detail: "iOS shows a warning it shows for every keyboard. Tap Allow.")
            }
            openSettingsButton
            Button("Next: test it") {
                step = .test
            }
            .buttonStyle(.rrSecondaryWide)
            .accessibilityIdentifier("setup-next")
            FullAccessExplainer()
        }
    }

    // Step 3
    private var testStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                lead: "Let's make sure ",
                emphasis: "it works",
                subtitle: "Tap the box, switch to ReplyRight with the globe key, tap the ReplyRight mark at the left of the bar, then Type a test message."
            )
            KeyboardPreview(highlight: .mark)
            KeyboardTestSection(showsHeader: false)
            switch app.keyboardStatus {
            case .ready:
                Button("Next") { step = .use }
                    .buttonStyle(.rrPrimary)
                    .accessibilityIdentifier("setup-next")
            case .limitedAccess:
                Button("Turn on Full Access") { step = .fullAccess }
                    .buttonStyle(.rrPrimary)
                Button("Use it for typing only") { step = .use }
                    .buttonStyle(.rrQuiet)
                    .accessibilityIdentifier("setup-next")
            case .notSetUp, .enabledNotTested:
                Button("I don't see ReplyRight") { step = .add }
                    .buttonStyle(.rrQuiet)
                Button("Skip for now") { step = .use }
                    .buttonStyle(.rrQuiet)
                    .accessibilityIdentifier("setup-next")
            }
        }
    }

    // Step 4
    private var useStep: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            ScreenHeader(
                lead: "Now try it ",
                emphasis: "in a real chat",
                subtitle: app.keyboardStatus.isReady
                    ? "Copy their message, switch to ReplyRight, and tap Reply."
                    : "Typing works now. Turn on Full Access whenever you want replies there too."
            )
            KeyboardPreview(highlight: .reply)
            HowToUseSection()
            Button("Done") {
                Haptics.success()
                dismiss()
            }
            .buttonStyle(.rrPrimary)
            .accessibilityIdentifier("setup-done")
        }
    }

    private var openSettingsButton: some View {
        Button("Open ReplyRight in Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }
        .buttonStyle(.rrPrimary)
        .accessibilityHint("Opens the Settings app at ReplyRight, where Keyboards is")
        .accessibilityIdentifier("keyboard-open-settings")
    }
}

// MARK: - Home card

/// The keyboard's place on Home. Large and inviting until the keyboard is
/// set up, a single quiet line once it has confirmed itself.
struct KeyboardHomeCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let status = app.keyboardStatus
        switch status {
        case .ready(let confirmed):
            readyLine(confirmed)
        case .notSetUp where app.keyboardSetup.isHomeCardSnoozed():
            snoozedLine
        default:
            showcase(status)
        }
    }

    private func showcase(_ status: KeyboardSetupStatus) -> some View {
        VStack(alignment: .leading, spacing: RRSpace.m) {
            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Eyebrow(status == .notSetUp ? "ReplyRight Keyboard" : "Keyboard setup")
                Text(headline(status))
                    .rrText(.title)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(detail(status))
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KeyboardPreview(highlight: .reply, compact: true)
            HStack(spacing: RRSpace.s) {
                Button(buttonTitle(status)) {
                    Haptics.tap()
                    app.openKeyboard(startSetup: true)
                }
                .buttonStyle(RRPrimaryButtonStyle(fullWidth: false))
                .accessibilityIdentifier("home-keyboard")
                if status == .notSetUp {
                    Button("Not now") {
                        app.snoozeKeyboardCard()
                    }
                    .buttonStyle(.rrQuiet)
                    .accessibilityHint("Hides this for a week. The Keyboard tab is always there.")
                    .accessibilityIdentifier("home-keyboard-later")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RRSpace.m)
        .background {
            RoundedRectangle(cornerRadius: RRRadius.card, style: .continuous).fill(Color.rrAccentSoft)
        }
        .accessibilityElement(children: .contain)
    }

    private func headline(_ status: KeyboardSetupStatus) -> String {
        switch status {
        case .notSetUp: return "Get replies inside any chat."
        case .enabledNotTested: return "Almost there."
        case .limitedAccess: return "Your keyboard is typing only."
        case .ready: return ""
        }
    }

    private func detail(_ status: KeyboardSetupStatus) -> String {
        switch status {
        case .notSetUp:
            return "Copy their message, tap Reply in the ReplyRight keyboard, and drop in the one you like. About a minute to set up."
        case .enabledNotTested:
            return "Allow Full Access if you want replies in your chats, then type the test message once so we know it works."
        case .limitedAccess:
            return "Full Access is off, so it can't write replies yet. Here's why it's needed and how your text is handled."
        case .ready:
            return ""
        }
    }

    private func buttonTitle(_ status: KeyboardSetupStatus) -> String {
        switch status {
        case .notSetUp: return "Set up the keyboard"
        case .enabledNotTested: return "Finish setup"
        case .limitedAccess: return "See how"
        case .ready: return ""
        }
    }

    private func readyLine(_ confirmed: Date) -> some View {
        Button {
            app.openKeyboard()
        } label: {
            HStack(spacing: RRSpace.xs) {
                Image(systemName: "keyboard")
                    .foregroundStyle(Color.rrAccent)
                    .accessibilityHidden(true)
                Text("Keyboard ready")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrText)
                Text("· confirmed \(confirmed.formatted(.relative(presentation: .named)))")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.rrTextTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.rrPress)
        .accessibilityHint("Opens the Keyboard tab")
        .accessibilityIdentifier("home-keyboard-ready")
    }

    private var snoozedLine: some View {
        Button {
            app.openKeyboard(startSetup: true)
        } label: {
            MenuRow("Add the ReplyRight keyboard", detail: "Replies inside any chat, in about a minute.")
        }
        .buttonStyle(.rrPress)
        .accessibilityIdentifier("home-keyboard")
    }
}

// MARK: - Illustration

/// A drawing of the ReplyRight keyboard: the bar with Reply and Rewrite above
/// a few rows of keys. Decorative; VoiceOver reads one description.
struct KeyboardPreview: View {
    enum Highlight {
        case mark
        case reply
    }

    var highlight: Highlight? = nil
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            HStack(spacing: 8) {
                BrandMark(size: compact ? 22 : 26)
                    .padding(3)
                    .overlay {
                        if highlight == .mark {
                            Circle().stroke(Color.rrAccent, lineWidth: 2)
                        }
                    }
                pill("Reply", symbol: "quote.opening", prominent: true)
                pill("Rewrite", symbol: "pencil", prominent: false)
                Spacer(minLength: 0)
                pill("EN", symbol: nil, prominent: false)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, count in
                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color(Palette.keyboardKey))
                            .frame(height: compact ? 22 : 30)
                            .shadow(color: Color(Palette.keyboardKeyShadow), radius: 0, x: 0, y: 1)
                    }
                }
                .padding(.horizontal, CGFloat(10 - count) * 6)
            }
        }
        .padding(compact ? 10 : 12)
        .background {
            RoundedRectangle(cornerRadius: RRRadius.control, style: .continuous)
                .fill(Color(Palette.keyboardPanel))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The ReplyRight keyboard, with Reply and Rewrite above the keys")
    }

    private var rows: [Int] { compact ? [10, 9] : [10, 9, 7] }

    private func pill(_ title: String, symbol: String?, prominent: Bool) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(prominent ? Color.rrButtonText : Color.rrText)
        .background {
            Capsule().fill(prominent ? Color.rrAccent : Color.clear)
        }
        .overlay {
            if !prominent {
                Capsule().stroke(Color.rrLine, lineWidth: 1)
            }
            if prominent && highlight == .reply {
                Capsule().stroke(Color.rrText.opacity(0.5), lineWidth: 1.5).padding(-3)
            }
        }
        .fixedSize()
    }
}

// MARK: - Shared

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
                .accessibilityHidden(true)
            Text(text)
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
