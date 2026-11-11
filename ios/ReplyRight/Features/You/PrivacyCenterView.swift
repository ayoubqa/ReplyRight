import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// The Privacy Center: what is sent, what is stored, and controls to delete any of it.
struct PrivacyCenterView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var pendingErase: SharedStore.Category?
    @State private var confirmsEraseAll = false

    var body: some View {
        @Bindable var app = app

        ScreenScroll {
            ScreenHeader(
                lead: "Your conversations ",
                emphasis: "stay yours.",
                subtitle: "These are some of the most personal messages you have. Here's exactly what happens to them."
            )

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("What leaves your iPhone")
                Fact("Only what you ask for help with, at the moment you tap a button.")
                Fact("Screenshots are resized and stripped of metadata on your iPhone first.")
                Fact("Our server reads them in memory, writes your replies, and discards them. Nothing is saved to a database or written to logs.")
                Fact("Your voice profile travels with each request and isn't stored on our servers.")
                Fact("A random install ID counts daily usage. It isn't tied to you or your Apple Account.")
            }
            .rrCard()

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("What never happens")
                Fact("No reading your other apps. ReplyRight only sees what you share.")
                Fact("No background monitoring, and no collecting what you type.")
                Fact("No sending messages for you. You always send them yourself.")
                Fact("No analytics on what your conversations say.")
            }
            .rrCard()

            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Toggle(isOn: $app.settings.learnFromEdits) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Learn from my edits")
                            .rrText(.headline)
                            .foregroundStyle(Color.rrText)
                        Text("Keeps replies you rework and copy as style examples in My Voice, on this iPhone. Off unless you turn it on.")
                            .rrText(.footnote)
                            .foregroundStyle(Color.rrTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.rrAccent)
            }
            .rrCard()

            VStack(alignment: .leading, spacing: RRSpace.s) {
                Eyebrow("Stored on this iPhone")
                Text("Everything you save lives here, not on our servers. Delete any of it whenever you like.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    DataRow(title: "Shared conversations", detail: sharedDetail, isEmpty: app.inbox == nil && app.keyboardContext == nil) {
                        pendingErase = .sharedContext
                    }
                    Divider().overlay(Color.rrLine)
                    DataRow(title: "Saved replies", detail: count(app.savedReplies.count), isEmpty: app.savedReplies.isEmpty) {
                        pendingErase = .savedReplies
                    }
                    Divider().overlay(Color.rrLine)
                    DataRow(title: "Saved sessions", detail: count(app.sessions.count), isEmpty: app.sessions.isEmpty) {
                        pendingErase = .sessions
                    }
                    Divider().overlay(Color.rrLine)
                    DataRow(title: "People", detail: count(app.people.count), isEmpty: app.people.isEmpty) {
                        pendingErase = .people
                    }
                    Divider().overlay(Color.rrLine)
                    DataRow(title: "Favourite styles", detail: count(app.styles.count), isEmpty: app.styles.isEmpty) {
                        pendingErase = .styles
                    }
                    Divider().overlay(Color.rrLine)
                    DataRow(title: "My Voice", detail: "Preferences and \(app.voice.samples.count) examples", isEmpty: app.voice == .standard) {
                        pendingErase = .voice
                    }
                }
            }
            .rrCard()

            Button("Erase everything", role: .destructive) {
                confirmsEraseAll = true
            }
            .buttonStyle(.rrSecondaryWide)
            .accessibilityIdentifier("privacy-erase-all")

            Button {
                openURL(AppConfig.privacyURL(base: app.apiBaseURL))
            } label: {
                Label("Read the full Privacy Policy", systemImage: "arrow.up.right")
            }
            .buttonStyle(.rrQuiet)
        }
        .navigationTitle("Privacy Center")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            app.reloadSharedState()
        }
        .confirmationDialog(
            eraseTitle,
            isPresented: Binding(
                get: { pendingErase != nil },
                set: { if !$0 { pendingErase = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let category = pendingErase {
                    app.erase(category)
                }
                pendingErase = nil
            }
            Button("Cancel", role: .cancel) {
                pendingErase = nil
            }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog(
            "Erase everything on this iPhone?",
            isPresented: $confirmsEraseAll,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) {
                app.eraseEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your voice, people, saved replies and sessions will be deleted and ReplyRight will start fresh. Your subscription isn't affected.")
        }
    }

    private var sharedDetail: String {
        var parts: [String] = []
        if app.inbox != nil { parts.append("1 waiting from the share sheet") }
        if app.keyboardContext != nil { parts.append("1 shared with the keyboard") }
        return parts.isEmpty ? "Nothing right now" : parts.joined(separator: ", ")
    }

    private func count(_ value: Int) -> String {
        value == 0 ? "None" : "\(value)"
    }

    private var eraseTitle: String {
        switch pendingErase {
        case .sharedContext: return "Delete shared conversations?"
        case .savedReplies: return "Delete all saved replies?"
        case .sessions: return "Delete all saved sessions?"
        case .people: return "Delete everyone under People?"
        case .styles: return "Delete your favourite styles?"
        case .voice: return "Reset My Voice?"
        case .none: return "Delete?"
        }
    }
}

private struct DataRow: View {
    let title: String
    let detail: String
    let isEmpty: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .rrText(.headline)
                    .foregroundStyle(Color.rrText)
                Text(detail)
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextSecondary)
            }
            Spacer()
            Button("Delete", role: .destructive, action: onDelete)
                .rrText(.callout)
                .disabled(isEmpty)
                .accessibilityLabel("Delete \(title)")
        }
        .frame(minHeight: 56)
    }
}
