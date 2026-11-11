import PhotosUI
import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// The Home tab: where a conversation starts, and the flow it leads into.
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
                    }
                }
        }
    }
}

/// "What's happening with your crush?" Three ways to bring a conversation in,
/// and shortcuts for the moments that don't start with one.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var showsShareGuide = false

    var body: some View {
        ScreenScroll(spacing: RRSpace.xl) {
            topBar

            ScreenHeader(
                eyebrow: Microcopy.greeting(hour: Calendar.current.component(.hour, from: Date())),
                lead: "What's happening with ",
                emphasis: "your crush?",
                subtitle: "Let's figure out what to say."
            )

            if let inbox = app.inbox {
                InboxCard(item: inbox)
            }

            if app.mode == .demo {
                DemoBadge(detailed: true)
            }

            startCards

            shortcuts

            if !app.settings.keyboardNudgeDismissed {
                KeyboardNudge()
            }
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
        HStack {
            Text("ReplyRight")
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
            Spacer()
            Button {
                if !app.isPro {
                    app.paywall = .general
                }
            } label: {
                HStack(spacing: 6) {
                    if app.isPro {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(allowanceText)
                        .rrText(.caption)
                }
                .foregroundStyle(app.isPro ? Color.rrAccent : Color.rrTextSecondary)
                .padding(.horizontal, RRSpace.s)
                .frame(minHeight: 32)
                .background {
                    Capsule().fill(app.isPro ? Color.rrAccentSoft : Color.rrSurfaceRaised)
                }
                .overlay {
                    Capsule().strokeBorder(Color.rrLine, lineWidth: 1)
                }
            }
            .buttonStyle(.rrPress)
            .accessibilityLabel(app.isPro ? "ReplyRight Pro" : "\(allowanceText). See plans")
        }
    }

    private var allowanceText: String {
        if app.isPro { return "Pro" }
        guard let remaining = app.remainingGenerations else { return "Free plan" }
        return Microcopy.allowance(remaining: remaining, isPro: false)
    }

    // MARK: Start cards

    private var startCards: some View {
        VStack(spacing: RRSpace.s) {
            PhotosPicker(
                selection: $pickedPhotos,
                maxSelectionCount: RequestLimits.maxImages,
                matching: .images
            ) {
                StartCard(
                    title: "Upload a screenshot",
                    subtitle: isLoadingPhotos ? "Getting it ready…" : "The fastest way. I'll read the conversation for you.",
                    systemImage: "photo.on.rectangle.angled",
                    isProminent: true
                )
            }
            .buttonStyle(.rrPress)
            .accessibilityIdentifier("home-upload")

            HStack(alignment: .top, spacing: RRSpace.s) {
                Button {
                    Haptics.tap()
                    app.startCompose()
                } label: {
                    StartCard(
                        title: "Paste a message",
                        subtitle: "Copy what they said and drop it in.",
                        systemImage: "doc.on.clipboard"
                    )
                }
                .buttonStyle(.rrPress)
                .accessibilityIdentifier("home-paste")

                Button {
                    Haptics.tap()
                    showsShareGuide = true
                } label: {
                    StartCard(
                        title: "Share a conversation",
                        subtitle: "Send it here from any app.",
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.rrPress)
            }
        }
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
        await app.compose.addImages(loaded)
        app.homePath = [.input]
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Or start here")
            VStack(spacing: 0) {
                ShortcutRow(title: "Help me reply", subtitle: "They said something. Now what?", systemImage: "arrowshape.turn.up.left") {
                    app.startCompose()
                }
                Divider().overlay(Color.rrLine)
                ShortcutRow(title: "Start a conversation", subtitle: "An opener that isn't \u{201C}hey\u{201D}.", systemImage: "hand.wave") {
                    app.homePath = [.starter(.opener)]
                }
                Divider().overlay(Color.rrLine)
                ShortcutRow(title: "Make it more flirty", subtitle: "Bring a draft. We'll warm it up.", systemImage: "sparkles") {
                    app.homePath = [.polish]
                }
                Divider().overlay(Color.rrLine)
                ShortcutRow(title: "Help me ask them out", subtitle: "From chatting to an actual plan.", systemImage: "calendar.badge.plus") {
                    app.homePath = [.starter(.askOut)]
                }
                Divider().overlay(Color.rrLine)
                ShortcutRow(title: "I don't know what to say", subtitle: "Talk it through with your coach.", systemImage: "lightbulb") {
                    app.askCoach(question: nil)
                }
            }
            .rrCard(padding: RRSpace.xs)
        }
    }
}

// MARK: - Pieces

/// One of the three ways in. The prominent one carries a small drawn conversation.
private struct StartCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var isProminent = false

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack(alignment: .top) {
                Image(systemName: systemImage)
                    .font(.system(size: isProminent ? 22 : 18, weight: .medium))
                    .foregroundStyle(Color.rrAccent)
                    .frame(width: isProminent ? 48 : 40, height: isProminent ? 48 : 40)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.rrAccentSoft)
                    }
                Spacer()
                if isProminent {
                    miniConversation
                }
            }
            Spacer(minLength: 0)
            Text(title)
                .rrText(isProminent ? .title : .headline)
                .foregroundStyle(Color.rrText)
                .multilineTextAlignment(.leading)
            Text(subtitle)
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: isProminent ? 150 : 128, alignment: .topLeading)
        .rrCard()
        .contentShape(RoundedRectangle(cornerRadius: RRRadius.card, style: .continuous))
    }

    /// A few abstract bubbles: theirs, yours, theirs. Decoration only.
    private var miniConversation: some View {
        VStack(alignment: .trailing, spacing: 5) {
            BubbleShape(side: .theirs, radius: 9)
                .fill(Color.rrBubbleTheirs)
                .frame(width: 74, height: 18)
                .frame(width: 104, alignment: .leading)
            BubbleShape(side: .mine, radius: 9)
                .fill(LinearGradient.rrBubbleMine)
                .frame(width: 58, height: 18)
            BubbleShape(side: .theirs, radius: 9)
                .fill(Color.rrBubbleTheirs)
                .frame(width: 88, height: 18)
                .frame(width: 104, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

private struct ShortcutRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            NavigationRow(title: title, subtitle: subtitle, systemImage: systemImage)
                .padding(.horizontal, RRSpace.s)
                .padding(.vertical, RRSpace.xxs)
        }
        .buttonStyle(.rrPress)
    }
}

/// Shown when something was shared to ReplyRight from another app.
private struct InboxCard: View {
    @Environment(AppModel.self) private var app
    let item: SharedInboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Shared with ReplyRight")
            Text(summary)
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
                .lineLimit(3)
            HStack(spacing: RRSpace.xs) {
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
        .rrCard()
        .overlay {
            RoundedRectangle(cornerRadius: RRRadius.card, style: .continuous)
                .strokeBorder(Color.rrAccent.opacity(0.5), lineWidth: 1)
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

/// A gentle pointer to the keyboard. Dismissible, and never shown again once dismissed.
private struct KeyboardNudge: View {
    @Environment(AppModel.self) private var app
    @State private var showsSetup = false

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack(alignment: .top) {
                Eyebrow("ReplyRight keyboard")
                Spacer()
                Button {
                    app.settings.keyboardNudgeDismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.rrTextTertiary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Dismiss")
            }
            Text("Get suggestions right where you type.")
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
            Text("Add the ReplyRight keyboard and rewrite a draft or pull up replies without leaving the chat.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set it up") {
                showsSetup = true
            }
            .buttonStyle(.rrSecondaryCompact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard()
        .sheet(isPresented: $showsSetup) {
            NavigationStack {
                KeyboardSetupView()
            }
            .preferredColorScheme(app.colorScheme)
        }
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
                    emphasis: "from any app.",
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
                .foregroundStyle(Color.rrCoral)
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
