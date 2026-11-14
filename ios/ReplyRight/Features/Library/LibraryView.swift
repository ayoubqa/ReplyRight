import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// The People tab: who the user is talking to, saved lines and saved conversations.
struct PeopleTab: View {
    var body: some View {
        NavigationStack {
            NotebookView()
        }
    }
}

/// The people the user is talking to, the lines worth keeping and the
/// conversations they chose to save.
///
/// Nothing lands here automatically, and nothing here leaves the iPhone
/// unless the user picks it as context for a reply.
struct NotebookView: View {
    @Environment(AppModel.self) private var app
    @State private var isAdding = false

    var body: some View {
        ScreenScroll(spacing: RRSpace.l) {
            HStack {
                Spacer()
                ProfileButton()
            }

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                EditorialTitle("People", style: .display)
                Text("Who you're talking to, lines worth keeping, and conversations you saved. It all stays on this iPhone.")
                    .rrText(.body)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            people

            VStack(alignment: .leading, spacing: 0) {
                NavigationLink {
                    SavedRepliesView()
                } label: {
                    MenuRow(
                        "Saved lines",
                        detail: app.savedReplies.isEmpty
                            ? "Bookmark a reply and it waits for you here, and in your keyboard."
                            : (app.keyboardStatus.isReady ? "Ready in your keyboard too." : "Copy one, or use it from your keyboard."),
                        trailing: app.savedReplies.isEmpty ? nil : "\(app.savedReplies.count)"
                    )
                }
                .buttonStyle(.rrPress)
                .accessibilityIdentifier("notebook-replies")

                NavigationLink {
                    SessionsView()
                } label: {
                    MenuRow(
                        "Saved conversations",
                        detail: "Text only, never screenshots. Kept only when you save one.",
                        trailing: app.sessions.isEmpty ? nil : "\(app.sessions.count)"
                    )
                }
                .buttonStyle(.rrPress)
                .accessibilityIdentifier("notebook-sessions")
                Rule()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isAdding) {
            PersonEditor(person: nil) { created in
                app.savePerson(created)
            }
            .environment(app)
            .preferredColorScheme(app.colorScheme)
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Who you're talking to")
                Button("Add someone") {
                    isAdding = true
                }
                .buttonStyle(.rrQuiet)
                .fixedSize()
                .accessibilityIdentifier("notebook-add-person")
            }

            if app.people.isEmpty {
                EmptyNote(
                    "No one here yet",
                    message: "Add someone you're talking to and keep what matters in one place: where you met, what they're into, the thing they told you about Friday. You choose what ReplyRight may use."
                )
            } else {
                PeopleList()
            }
        }
    }
}

/// The people in the notebook, each opening its own page.
struct PeopleList: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(app.people) { person in
                NavigationLink {
                    PersonDetailView(personID: person.id)
                } label: {
                    PersonRow(person: person)
                }
                .buttonStyle(.rrPress)
                .accessibilityIdentifier("person-\(person.alias)")
            }
            Rule()
        }
    }
}

struct PersonRow: View {
    let person: CrushProfile

    var body: some View {
        HStack(alignment: .center, spacing: RRSpace.s) {
            PersonAvatar(person: person, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.alias)
                    .rrText(.menu)
                    .foregroundStyle(Color.rrText)
                    .lineLimit(1)
                Text(person.subtitle)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: RRSpace.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.rrTextTertiary)
        }
        .padding(.vertical, RRSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule() }
        .contentShape(Rectangle())
    }
}

// MARK: - Saved replies

/// Replies the user bookmarked. Pass a person to see only the ones written for them.
struct SavedRepliesView: View {
    @Environment(AppModel.self) private var app
    var personID: UUID? = nil

    private var replies: [SavedReply] {
        guard let personID else { return app.savedReplies }
        return app.savedReplies(for: personID)
    }

    var body: some View {
        ScreenScroll(spacing: RRSpace.m) {
            if replies.isEmpty {
                EmptyNote(
                    "Nothing saved yet",
                    message: "When a suggestion sounds exactly right, tap the bookmark. It waits for you here and in your ReplyRight keyboard."
                )
                Button("Write a reply") {
                    app.startCompose()
                }
                .buttonStyle(.rrSecondaryCompact)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(replies) { reply in
                        SavedReplyRow(reply: reply, showsPerson: personID == nil)
                    }
                    Rule()
                }
            }
        }
        .navigationTitle("Saved lines")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SavedReplyRow: View {
    @Environment(AppModel.self) private var app
    let reply: SavedReply
    var showsPerson = true

    var body: some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(caption)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                Spacer()
                Text(reply.createdAt, format: .dateTime.day().month(.abbreviated))
                    .rrText(.caption)
                    .foregroundStyle(Color.rrTextTertiary)
            }
            MessageBubble(reply.text, side: .mine)
            HStack(spacing: RRSpace.s) {
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
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.rrTextTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Delete saved reply")
            }
        }
        .padding(.vertical, RRSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule() }
    }

    private var caption: String {
        if showsPerson, let person = app.person(reply.crushID) {
            return "\(reply.style), for \(person.alias)"
        }
        return reply.style
    }
}

// MARK: - Saved conversations

struct SessionsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScreenScroll(spacing: RRSpace.m) {
            if app.sessions.isEmpty {
                EmptyNote(
                    "No saved conversations",
                    message: "A conversation is kept only when you save it with the bookmark on the replies screen. Saved conversations hold text, never screenshots."
                )
                Button("Start one") {
                    app.startCompose()
                }
                .buttonStyle(.rrSecondaryCompact)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(app.sessions) { session in
                        NavigationLink {
                            SessionDetailView(sessionID: session.id)
                        } label: {
                            SessionRow(session: session)
                        }
                        .buttonStyle(.rrPress)
                    }
                    Rule()
                }
            }
        }
        .navigationTitle("Saved conversations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SessionRow: View {
    @Environment(AppModel.self) private var app
    let session: SavedSession
    var showsPerson = true

    var body: some View {
        HStack(alignment: .center, spacing: RRSpace.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(caption)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: RRSpace.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.rrTextTertiary)
        }
        .padding(.vertical, RRSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule() }
        .contentShape(Rectangle())
    }

    private var caption: String {
        let date = session.createdAt.formatted(.dateTime.day().month(.abbreviated))
        let count = session.options.count == 1 ? "1 reply" : "\(session.options.count) replies"
        if showsPerson, let person = app.person(session.crushID) {
            return "\(date), with \(person.alias), \(count)"
        }
        return "\(date), \(count)"
    }
}

/// A saved conversation: the text, the read, and the replies that were kept.
struct SessionDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let sessionID: UUID

    var body: some View {
        ScreenScroll {
            if let session = app.sessions.first(where: { $0.id == sessionID }) {
                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Eyebrow(session.intent.title)
                    EditorialTitle(session.title, style: .title)
                    if let person = app.person(session.crushID) {
                        Text("With \(person.alias)")
                            .rrText(.footnote)
                            .foregroundStyle(Color.rrTextSecondary)
                    }
                }

                if !session.read.isEmpty {
                    MarginNote(session.read)
                }

                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Eyebrow("The conversation")
                    Text(session.conversation)
                        .rrText(.callout)
                        .foregroundStyle(Color.rrTextSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .rrCard()

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(session.options) { option in
                        VStack(alignment: .leading, spacing: RRSpace.xs) {
                            Text(option.style)
                                .rrText(.headline)
                                .foregroundStyle(Color.rrAccent)
                            MessageBubble(option.text, side: .mine)
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
                        .rrCard(padding: RRSpace.m)
                    }
                    Rule()
                }

                Button("Write new replies for this") {
                    app.reopen(session)
                }
                .buttonStyle(.rrPrimary)

                Button("Delete this conversation", role: .destructive) {
                    app.sessions.removeAll { $0.id == sessionID }
                    dismiss()
                }
                .buttonStyle(.rrQuiet)
            } else {
                Text("This conversation is no longer saved.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
