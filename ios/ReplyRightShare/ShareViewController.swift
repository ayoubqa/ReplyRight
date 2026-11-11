import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

/// The share sheet entry point. Hosts the SwiftUI interface and hands it what was shared.
///
/// Reading the shared items happens on the device. Nothing is uploaded until the
/// user taps "Write replies" or "Send to my keyboard".
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = model.interfaceStyle
        view.backgroundColor = UIColor.dynamic(Palette.background)

        model.onFinish = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }

        let host = UIHostingController(rootView: ShareRootView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        model.load(from: items)
    }
}

/// The share sheet's interface: what was shared, what the reply should do, and three ways to go from there.
struct ShareRootView: View {
    @Bindable var model: ShareModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: RRSpace.l) {
                    content
                }
                .padding(.horizontal, RRSpace.screen)
                .padding(.top, RRSpace.s)
                .padding(.bottom, RRSpace.xl)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .rrScreenBackground()
        .rrToast($model.toast)
        .tint(Color.rrAccent)
        .preferredColorScheme(model.colorScheme)
        .animation(.rrGentle, value: model.phase)
    }

    private var header: some View {
        HStack {
            Text("ReplyRight")
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
            Spacer()
            Button {
                model.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.rrTextSecondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.rrSurfaceRaised))
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, RRSpace.screen)
        .padding(.vertical, RRSpace.s)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ThinkingView(lines: ["Getting that ready…"])
                .padding(.top, RRSpace.l)

        case .needsSetup:
            MessageScreen(
                lead: "Open ReplyRight ",
                emphasis: "once first.",
                detail: "There's a quick setup in the app, including confirming you're 18 or older. After that, sharing here works straight away.",
                model: model
            )

        case .nothingShared:
            MessageScreen(
                lead: "Nothing to ",
                emphasis: "work with.",
                detail: "I couldn't find any text or screenshots in what was shared. Try sharing a screenshot of the conversation, or the message text itself.",
                model: model
            )

        case .ready:
            StartScreen(model: model)

        case .working(let job):
            ThinkingView(lines: job == .replies ? Microcopy.writing : Microcopy.reading)
                .padding(.top, RRSpace.l)

        case .replies:
            RepliesScreen(model: model)

        case .sentToKeyboard:
            MessageScreen(
                lead: "It's in ",
                emphasis: "your keyboard.",
                detail: "Go back to the chat, switch to the ReplyRight keyboard with the globe key, and tap Reply. Only the text was saved, and it clears itself after a day.",
                model: model
            )

        case .savedForLater:
            MessageScreen(
                lead: "Saved ",
                emphasis: "for later.",
                detail: "It will be waiting on the Home screen next time you open ReplyRight. If you don't pick it up within a couple of hours, it's deleted.",
                model: model
            )

        case .failed(let message, let suggestsUpgrade, _):
            VStack(alignment: .leading, spacing: RRSpace.m) {
                if suggestsUpgrade {
                    ErrorNote("\(message) Open ReplyRight to see plans.", actionTitle: "Back") {
                        model.backToStart()
                    }
                } else {
                    ErrorNote(message) {
                        model.retry()
                    }
                    Button("Back") {
                        model.backToStart()
                    }
                    .buttonStyle(.rrQuiet)
                }
            }
            .padding(.top, RRSpace.s)
        }
    }
}

// MARK: - Screens

/// What was shared, the goal for the reply, and the three things the user can do with it.
private struct StartScreen: View {
    @Bindable var model: ShareModel

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            EditorialTitle("What should this reply ", emphasis: "do?", style: .title)

            preview

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("I'd like to")
                FlowLayout {
                    ForEach(Intent.quickChoices) { intent in
                        RRChip(
                            intent.title,
                            systemImage: intent.symbol,
                            isSelected: model.intent == intent,
                            isLocked: model.isLocked(intent)
                        ) {
                            model.choose(intent)
                        }
                    }
                }
            }

            VStack(spacing: RRSpace.xs) {
                Button("Write replies") {
                    Haptics.tap()
                    model.writeReplies()
                }
                .buttonStyle(.rrPrimary)

                Button {
                    Haptics.tap()
                    model.sendToKeyboard()
                } label: {
                    Label("Send to my keyboard", systemImage: "keyboard")
                }
                .buttonStyle(.rrSecondaryWide)

                Button("Open in ReplyRight later") {
                    model.saveForLater()
                }
                .buttonStyle(.rrQuiet)
            }

            Label(
                "Nothing has been sent yet. Screenshots are read once, in memory, and never stored on our servers.",
                systemImage: "lock"
            )
            .rrText(.footnote)
            .foregroundStyle(Color.rrTextTertiary)
        }
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("You shared")
            if model.hasScreenshots {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: RRSpace.xs) {
                        ForEach(Array(model.shots.enumerated()), id: \.element.id) { index, shot in
                            Group {
                                if let thumbnail = shot.thumbnail {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Color.rrSurfaceRaised
                                }
                            }
                            .frame(width: 84, height: 136)
                            .clipShape(RoundedRectangle(cornerRadius: RRRadius.small, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: RRRadius.small, style: .continuous)
                                    .strokeBorder(Color.rrLine, lineWidth: 1)
                            }
                            .accessibilityLabel("Screenshot \(index + 1)")
                        }
                    }
                }
            }
            if !model.textPreview.isEmpty {
                MessageBubble(model.textPreview, side: .theirs)
                    .lineLimit(6)
            }
        }
    }
}

/// Three replies, each with a reason and a copy button. The user pastes and sends it themselves.
private struct RepliesScreen: View {
    @Bindable var model: ShareModel

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow(model.intent.title)
                Text(model.note.isEmpty ? "Here are a few ways to say it." : model.note)
                    .rrText(.title)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.isDemo {
                DemoBadge(detailed: true)
            }
            if let headsUp = model.headsUp, !headsUp.isEmpty {
                HeadsUpNote(headsUp)
            }

            if model.options.isEmpty {
                Text("No suggestions this time. Sometimes the kindest move isn't another message.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(model.options) { option in
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    Text(option.style)
                        .rrText(.eyebrow)
                        .foregroundStyle(Color.rrAccent)
                    MessageBubble(option.text, side: .mine)
                        .padding(.leading, -44)
                    if !option.why.isEmpty {
                        MarginNote(option.why)
                    }
                    Button {
                        model.copy(option)
                    } label: {
                        Label(
                            model.copiedID == option.id ? "Copied" : "Copy",
                            systemImage: model.copiedID == option.id ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(RRPrimaryButtonStyle(fullWidth: false))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rrCard()
            }

            HStack(spacing: RRSpace.xs) {
                Button {
                    Haptics.tap()
                    model.writeReplies(regenerate: true)
                } label: {
                    Label("Three more", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.rrSecondaryCompact)

                Button("Change the goal") {
                    model.backToStart()
                }
                .buttonStyle(.rrQuiet)
            }

            Text("Copy one, go back to the chat, and paste. Edit anything that doesn't sound like you.")
                .rrText(.note)
                .foregroundStyle(Color.rrTextTertiary)

            Button("Done") {
                model.close()
            }
            .buttonStyle(.rrSecondaryWide)
        }
    }
}

/// A short message with a single way out.
private struct MessageScreen: View {
    let lead: String
    let emphasis: String
    let detail: String
    let model: ShareModel

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.l) {
            EditorialTitle(lead, emphasis: emphasis, style: .display)
            Text(detail)
                .rrText(.body)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") {
                model.close()
            }
            .buttonStyle(.rrPrimary)
        }
        .padding(.top, RRSpace.l)
    }
}
