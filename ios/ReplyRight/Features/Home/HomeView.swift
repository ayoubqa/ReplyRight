import PhotosUI
import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// The Reply tab: where a conversation starts, and the flow it leads into.
struct HomeTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        NavigationStack(path: $app.homePath) {
            HomeView()
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .input:
                        ConversationInputView()
                    case .understanding:
                        UnderstandingView()
                    case .replies:
                        RepliesView()
                    case .polish:
                        DraftPolishView()
                    case .starter(let kind):
                        StartersView(kind: kind)
                    case .saved:
                        SavedRepliesView()
                    case .example:
                        ExampleRepliesView()
                    }
                }
        }
    }
}

/// The first screen: one question, one place to answer it, the keyboard, and
/// a short menu of the other things ReplyRight is good for.
///
/// First-time users see the composer and a guided way into the keyboard.
/// Returning users also see where they left off and their saved lines.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var draft = ""
    @State private var person: CrushProfile?
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var showsShareGuide = false
    @FocusState private var isWriting: Bool

    var body: some View {
        ScreenScroll(spacing: RRSpace.l) {
            topBar

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Text(Microcopy.greeting(hour: Calendar.current.component(.hour, from: Date())))
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                EditorialTitle("What did they say?", style: .hero)
            }
            .padding(.top, RRSpace.xs)

            if let inbox = app.inbox {
                InboxNotice(item: inbox)
            }

            composer

            ConnectionNotice()

            KeyboardHomeCard()

            if hasHistory {
                returning
            }

            menu

            footer
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsShareGuide) {
            ShareGuideSheet()
                .preferredColorScheme(app.colorScheme)
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: RRSpace.xs) {
            BrandLogo(height: 21)
                .accessibilityLabel("ReplyRight")
            Spacer()
            // The connection indicator is for whoever is building the app.
            // A release build shows problems only where they matter, in ConnectionNotice.
            if AppConfig.allowsEnvironmentSwitching {
                Button {
                    app.showsConnection = true
                } label: {
                    ConnectionPill(app.connection)
                }
                .buttonStyle(.rrPress)
                .accessibilityIdentifier("home-connection")
            }
            ProfileButton()
        }
    }

    // MARK: Composer

    /// The one filled surface on the screen: a place to put what they said.
    private var composer: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Paste their message here, or the last few lines of the chat.")
                        .rrText(.bodyLarge)
                        .foregroundStyle(Color.rrTextTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $draft)
                    .rrText(.bodyLarge)
                    .foregroundStyle(Color.rrText)
                    .tint(Color.rrCursor)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 104, maxHeight: 220)
                    .focused($isWriting)
                    .accessibilityLabel("What they said")
                    .accessibilityHint("Paste or type their message, or a few lines of the chat")
                    .accessibilityIdentifier("home-message")
            }

            // Wraps onto a second line at large text sizes instead of truncating.
            FlowLayout(spacing: RRSpace.xs, lineSpacing: RRSpace.xs) {
                sourceButtons
            }

            if !app.people.isEmpty {
                personMenu
            }

            Button("Help me reply") {
                readDraft()
            }
            .buttonStyle(.rrPrimary)
            .disabled(draft.trimmed.count < 2)
            .accessibilityHint("Reads the conversation, then suggests three replies")
            .accessibilityIdentifier("home-read")

            Text("Nothing is sent until you tap Help me reply. Screenshots aren't kept.")
                .rrText(.caption)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .rrPanel()
    }

    @ViewBuilder
    private var sourceButtons: some View {
        Button {
            pasteFromClipboard()
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.rrSecondaryCompact)
        .accessibilityIdentifier("home-paste")

        PhotosPicker(
            selection: $pickedPhotos,
            maxSelectionCount: RequestLimits.maxImages,
            matching: .images
        ) {
            Label(isLoadingPhotos ? "Getting it ready…" : "Screenshot", systemImage: "photo")
        }
        .buttonStyle(.rrSecondaryCompact)
        .accessibilityIdentifier("home-upload")

        if draft.trimmed.isEmpty {
            // Opens a worked example with replies written in advance. No AI call.
            Button {
                Haptics.tap()
                isWriting = false
                app.homePath = [.example]
            } label: {
                Label("See an example", systemImage: "sparkles")
            }
            .buttonStyle(.rrSecondaryCompact)
            .accessibilityHint("Shows a made-up chat with example replies. Nothing is sent.")
            .accessibilityIdentifier("home-example")
        }
    }

    private var personMenu: some View {
        Menu {
            Button("No one in particular") { person = nil }
            ForEach(app.people) { candidate in
                Button(candidate.alias) {
                    person = candidate
                    app.settings.lastCrushID = candidate.id
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(person.map { "With \($0.alias)" } ?? "With no one in particular")
                    .rrText(.callout)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.rrAccent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(person.map { "Context: \($0.alias)" } ?? "Context: no one in particular")
        .accessibilityHint("Chooses whose profile to use as context")
    }

    private func readDraft() {
        let text = draft.trimmed
        guard text.count >= 2 else { return }
        Haptics.tap()
        isWriting = false
        app.compose.reset()
        app.compose.text = text
        app.compose.crush = person
        app.compose.startAnalysis(app: app)
        app.homePath = [.understanding]
        draft = ""
    }

    /// Reads the clipboard only because the user tapped Paste.
    private func pasteFromClipboard() {
        guard let copied = UIPasteboard.general.string?.trimmed, !copied.isEmpty else {
            app.toast = "There's no text on the clipboard."
            return
        }
        Haptics.tap()
        draft = draft.trimmed.isEmpty ? copied : draft + "\n" + copied
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        defer {
            isLoadingPhotos = false
            pickedPhotos = []
        }
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }
        guard !loaded.isEmpty else {
            app.toast = "Those photos couldn't be loaded."
            return
        }
        app.compose.reset()
        app.compose.text = draft.trimmed
        app.compose.crush = person
        await app.compose.addImages(loaded)
        draft = ""
        app.homePath = [.input]
    }

    // MARK: Returning

    private var hasHistory: Bool {
        !app.sessions.isEmpty || !app.savedReplies.isEmpty
    }

    /// Where the user left off: the last saved conversation and their saved lines.
    private var returning: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Pick up where you left off")
                .padding(.bottom, RRSpace.xxs)
            if let last = app.sessions.first {
                Button {
                    Haptics.tap()
                    app.reopen(last)
                } label: {
                    MenuRow(
                        last.title,
                        detail: lastSessionDetail(last),
                        trailing: last.createdAt.formatted(.relative(presentation: .named))
                    )
                }
                .buttonStyle(.rrPress)
                .accessibilityIdentifier("home-last-session")
            }
            Button {
                Haptics.tap()
                app.homePath = [.saved]
            } label: {
                MenuRow(
                    "Saved lines",
                    detail: app.savedReplies.isEmpty
                        ? "Bookmark a reply and it waits here."
                        : (app.keyboardStatus.isReady ? "Ready in your keyboard too." : "Copy one, or use it from your keyboard."),
                    trailing: app.savedReplies.isEmpty ? nil : "\(app.savedReplies.count)"
                )
            }
            .buttonStyle(.rrPress)
            .accessibilityIdentifier("home-saved")
            Rule()
        }
    }

    private func lastSessionDetail(_ session: SavedSession) -> String {
        if let person = app.person(session.crushID) {
            return "With \(person.alias). Write new replies from here."
        }
        return "Write new replies from here."
    }

    // MARK: Menu

    /// Everything else, as a short menu. Each line says what you get.
    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("More ways to get help")
                .padding(.bottom, RRSpace.xxs)
            menuButton("Start a conversation", detail: "An opener that isn't \u{201C}hey\u{201D}.", id: "home-starter") {
                app.homePath = [.starter(.opener)]
            }
            menuButton("Polish something I wrote", detail: "Bring a draft. Keep what's you, fix the rest.", id: "home-polish") {
                app.homePath = [.polish]
            }
            menuButton("Ask them out", detail: "From chatting to an actual plan.", id: "home-askout") {
                app.homePath = [.starter(.askOut)]
            }
            menuButton("Talk it through", detail: "Not sure what to say? Your coach is here.", id: "home-coach") {
                app.askCoach(question: nil)
            }
            menuButton("Share from another app", detail: "Send a screenshot or a message straight here.", id: "home-share") {
                showsShareGuide = true
            }
            if !hasHistory {
                menuButton("Saved lines", detail: "Bookmark a reply and it waits here.", id: "home-saved") {
                    app.homePath = [.saved]
                }
            }
            Rule()
        }
    }

    private func menuButton(_ title: String, detail: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            MenuRow(title, detail: detail)
        }
        .buttonStyle(.rrPress)
        .accessibilityIdentifier(id)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(allowanceText)
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
            Spacer()
            if !app.isPro {
                Button("See Pro") {
                    app.paywall = .general
                }
                .buttonStyle(.rrQuiet)
            }
        }
    }

    private var allowanceText: String {
        if app.isPro { return "ReplyRight Pro" }
        guard let remaining = app.remainingGenerations else { return "Free plan" }
        return Microcopy.allowance(remaining: remaining, isPro: false)
    }
}

// MARK: - Pieces

/// Shown when something was shared to ReplyRight from another app.
private struct InboxNotice: View {
    @Environment(AppModel.self) private var app
    let item: SharedInboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Shared with ReplyRight")
            Text(summary)
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
                .lineLimit(3)
            HStack(spacing: RRSpace.s) {
                Button("Pick it up") {
                    Haptics.tap()
                    app.openInbox()
                }
                .buttonStyle(RRPrimaryButtonStyle(fullWidth: false))
                Button("Discard") {
                    app.dismissInbox()
                }
                .buttonStyle(.rrQuiet)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RRSpace.m)
        .background {
            RoundedRectangle(cornerRadius: RRRadius.card, style: .continuous).fill(Color.rrAccentSoft)
        }
    }

    private var summary: String {
        if !item.text.isEmpty {
            return "\u{201C}\(item.text)\u{201D}"
        }
        let count = item.imageFiles.count
        return count == 1 ? "A screenshot is waiting." : "\(count) screenshots are waiting."
    }
}

/// Explains the two honest ways to bring a conversation in from another app.
struct ShareGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScreenScroll {
                ScreenHeader(
                    lead: "Send it over ",
                    emphasis: "from any app",
                    subtitle: "ReplyRight can't see your chats, and it never will. You choose what to share, every time."
                )

                GuideStep(
                    number: "1",
                    title: "Share a screenshot",
                    detail: "Take a screenshot of the chat, tap the preview, then the share button, and choose ReplyRight."
                )
                GuideStep(
                    number: "2",
                    title: "Or share selected text",
                    detail: "In apps that allow it, select the message, tap Share, and choose ReplyRight."
                )
                GuideStep(
                    number: "3",
                    title: "Pick up where you left off",
                    detail: "Get replies right in the share sheet, send the conversation to your ReplyRight keyboard, or open it here later."
                )

                Text("Don't see ReplyRight in the share sheet? Scroll the row of apps to the end, tap More, and switch it on.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct GuideStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: RRSpace.m) {
            Text(number)
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrHighlightInk)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: RRSpace.xxs) {
                Text(title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                Text(detail)
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
