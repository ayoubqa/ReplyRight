import ReplyRightCore
import ReplyRightUI
import SwiftUI

/// Optional notes about the people the user is talking to, under nicknames.
/// Stored on the device; sent only with a request where that person is selected.
struct PeopleView: View {
    @Environment(AppModel.self) private var app
    @State private var editing: CrushProfile?
    @State private var isAdding = false

    var body: some View {
        ScreenScroll {
            ScreenHeader(
                lead: "The people ",
                emphasis: "on your mind.",
                subtitle: "A little context makes replies more specific. Use a nickname, and only add what you're comfortable with."
            )

            if app.people.isEmpty {
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    Text("No one here yet.")
                        .rrText(.headline)
                        .foregroundStyle(Color.rrText)
                    Text("Add someone and I'll remember the running jokes, where things stand, and what they're into.")
                        .rrText(.callout)
                        .foregroundStyle(Color.rrTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .rrCard()
            } else {
                ForEach(app.people) { person in
                    Button {
                        editing = person
                    } label: {
                        HStack(alignment: .top, spacing: RRSpace.m) {
                            Text(person.initial)
                                .rrText(.titleSmall)
                                .foregroundStyle(Color.rrAccent)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.rrAccentSoft))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(person.alias)
                                    .rrText(.headline)
                                    .foregroundStyle(Color.rrText)
                                Text(person.stage.title)
                                    .rrText(.footnote)
                                    .foregroundStyle(Color.rrTextSecondary)
                                if !person.notes.isEmpty {
                                    Text(person.notes)
                                        .rrText(.footnote)
                                        .foregroundStyle(Color.rrTextTertiary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .rrCard()
                    }
                    .buttonStyle(.rrPress)
                }
            }

            Button {
                isAdding = true
            } label: {
                Label("Add someone", systemImage: "plus")
            }
            .buttonStyle(.rrSecondaryWide)
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAdding) {
            PersonEditor(person: nil) { created in
                app.people.insert(created, at: 0)
            }
            .preferredColorScheme(app.colorScheme)
        }
        .sheet(item: $editing) { person in
            PersonEditor(
                person: person,
                onSave: { updated in
                    if let index = app.people.firstIndex(where: { $0.id == updated.id }) {
                        app.people[index] = updated
                    }
                },
                onDelete: {
                    app.people.removeAll { $0.id == person.id }
                    if app.settings.lastCrushID == person.id {
                        app.settings.lastCrushID = nil
                    }
                }
            )
            .preferredColorScheme(app.colorScheme)
        }
    }
}

/// Add or edit a person. Pass nil to create one.
struct PersonEditor: View {
    @Environment(\.dismiss) private var dismiss
    private let existing: CrushProfile?
    private let onSave: (CrushProfile) -> Void
    private let onDelete: (() -> Void)?

    @State private var alias: String
    @State private var stage: CrushProfile.Stage
    @State private var notes: String

    init(person: CrushProfile?, onSave: @escaping (CrushProfile) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = person
        self.onSave = onSave
        self.onDelete = onDelete
        _alias = State(initialValue: person?.alias ?? "")
        _stage = State(initialValue: person?.stage ?? .talking)
        _notes = State(initialValue: person?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                VStack(alignment: .leading, spacing: RRSpace.s) {
                    Eyebrow("What do you call them?")
                    RRField("A nickname is perfect", text: $alias)
                        .accessibilityIdentifier("person-alias")
                }

                ChoiceGroup(
                    title: "Where things stand",
                    options: CrushProfile.Stage.allCases,
                    label: { $0.title },
                    selection: $stage
                )

                VStack(alignment: .leading, spacing: RRSpace.s) {
                    Eyebrow("Worth remembering")
                    RRTextArea(
                        text: $notes,
                        placeholder: "Met at a climbing gym. Loves ramen, hates mornings. We joke about my terrible playlists.",
                        minHeight: 110
                    )
                    LimitLabel(count: notes.count, limit: CrushProfile.maxNotesLength)
                }

                Label("Kept on this iPhone. Sent only when you pick this person for a reply.", systemImage: "lock")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)

                if let onDelete {
                    Button("Remove this person", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .buttonStyle(.rrQuiet)
                }
            }
            .navigationTitle(existing == nil ? "Add someone" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(alias.trimmed.isEmpty)
                }
            }
        }
    }

    private func save() {
        var person = existing ?? CrushProfile(alias: "")
        person.alias = String(alias.trimmed.prefix(CrushProfile.maxAliasLength))
        person.stage = stage
        person.notes = String(notes.trimmed.prefix(CrushProfile.maxNotesLength))
        onSave(person)
        Haptics.success()
        dismiss()
    }
}
