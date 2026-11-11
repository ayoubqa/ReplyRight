import ReplyRightCore
import ReplyRightUI
import SwiftUI

struct LibraryTab: View {
    var body: some View {
        NavigationStack {
            LibraryView()
        }
    }
}

/// Replies and sessions the user chose to keep. Nothing lands here automatically.
struct LibraryView: View {
    @Environment(AppModel.self) private var app

    enum Shelf: String, CaseIterable, Identifiable {
        case replies = "Replies"
        case sessions = "Sessions"
        var id: String { rawValue }
    }

    @State private var section: Shelf = .replies

    var body: some View {
        ScreenScroll {
            ScreenHeader(
                lead: "Worth ",
                emphasis: "keeping.",
                subtitle: "Lines you liked and conversations you saved. Saved replies are in your ReplyRight keyboard too."
            )

            Picker("Show", selection: $section) {
                ForEach(Shelf.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            switch section {
            case .replies:
                replies
            case .sessions:
                sessions
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var replies: some View {
        if app.savedReplies.isEmpty {
            EmptyLibrary(
                title: "Nothing saved yet.",
                detail: "When a suggestion sounds exactly right, tap the bookmark and it'll wait for you here.",
                actionTitle: "Write a reply"
            ) {
                app.startCompose()
            }
        } else {
            ForEach(app.savedReplies) { reply in
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    HStack {
                        Text(reply.style)
                            .rrText(.eyebrow)
                            .foregroundStyle(Color.rrAccent)
                        Spacer()
                        Text(reply.createdAt, format: .dateTime.day().month(.abbreviated))
                            .rrText(.caption)
                            .foregroundStyle(Color.rrTextTertiary)
                    }
                    MessageBubble(reply.text, side: .mine)
                        .padding(.leading, -44)
                    HStack(spacing: RRSpace.xs) {
                        Button {
                            app.copy(reply.text)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.rrSecondaryCompact)
                        Spacer()
                        Button {
                            withAnimation(.rrSnappy) {
                                app.savedReplies.removeAll { $0.id == reply.id }
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.rrTextTertiary)
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel("Delete saved reply")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rrCard()
            }
        }
    }

    @ViewBuilder
    private var sessions: some View {
        if app.sessions.isEmpty {
            EmptyLibrary(
                title: "No saved sessions.",
                detail: "Conversations are never kept unless you save one with the bookmark on the replies screen. Saved sessions hold text only, never screenshots.",
                actionTitle: "Start one"
            ) {
                app.startCompose()
            }
        } else {
            ForEach(app.sessions) { session in
                NavigationLink {
                    SessionDetailView(sessionID: session.id)
                } label: {
                    VStack(alignment: .leading, spacing: RRSpace.xs) {
                        HStack {
                            Text(session.intent.title)
                                .rrText(.eyebrow)
                                .foregroundStyle(Color.rrAccent)
                            Spacer()
                            Text(session.createdAt, format: .dateTime.day().month(.abbreviated))
                                .rrText(.caption)
                                .foregroundStyle(Color.rrTextTertiary)
                        }
                        Text(session.title)
                            .rrText(.titleSmall)
                            .foregroundStyle(Color.rrText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text("\(session.options.count) replies saved")
                            .rrText(.footnote)
                            .foregroundStyle(Color.rrTextSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rrCard()
                }
                .buttonStyle(.rrPress)
            }
        }
    }
}

private struct EmptyLibrary: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Text(title)
                .rrText(.titleSmall)
                .foregroundStyle(Color.rrText)
            Text(detail)
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.rrSecondaryCompact)
                .padding(.top, RRSpace.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .rrCard(padding: RRSpace.l)
    }
}

/// A saved session: the conversation as text, the read, and the replies that were kept.
struct SessionDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID

    var body: some View {
        ScreenScroll {
            if let session = app.sessions.first(where: { $0.id == sessionID }) {
                ScreenHeader(
                    eyebrow: session.intent.title,
                    lead: session.title,
                    emphasis: "",
                    style: .title
                )

                if let person = app.person(session.crushID) {
                    Label("With \(person.alias)", systemImage: "person")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextSecondary)
                }

                if !session.read.isEmpty {
                    MarginNote(session.read)
                }

                VStack(alignment: .leading, spacing: RRSpace.s) {
                    Eyebrow("The conversation")
                    Text(session.conversation)
                        .rrText(.callout)
                        .foregroundStyle(Color.rrTextSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rrCard()

                Eyebrow("Replies")
                ForEach(session.options) { option in
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
                            app.copy(option.text)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.rrSecondaryCompact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rrCard()
                }

                Button("Write new replies for this") {
                    app.reopen(session)
                }
                .buttonStyle(.rrPrimary)

                Button("Delete this session", role: .destructive) {
                    app.sessions.removeAll { $0.id == sessionID }
                    dismiss()
                }
                .buttonStyle(.rrQuiet)
            } else {
                Text("This session is no longer saved.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
