import PhotosUI
import ReplyRightCore
import ReplyRightUI
import SwiftUI
import UIKit

// MARK: - One person

/// A file handed to the system share sheet.
private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// Everything about one person: what the user wrote down, private notes,
/// summaries of earlier conversations, and the replies and conversations saved
/// for them. From here the user can start a reply with this person as context,
/// change what ReplyRight may use, export it all, or delete it for good.
struct PersonDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let personID: UUID

    @State private var isEditing = false
    @State private var newSummary = ""
    @State private var exportFile: ExportFile?
    @State private var confirmsDelete = false

    var body: some View {
        ScreenScroll(spacing: RRSpace.l) {
            if let person = app.person(personID) {
                header(person)
                actions(person)
                about(person)
                notes(person)
                summaries(person)
                saved(person)
                sharing(person)
                dataControls(person)
            } else {
                Text("This person is no longer in People.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if app.person(personID) != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { isEditing = true }
                        .accessibilityIdentifier("person-edit")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            if let person = app.person(personID) {
                PersonEditor(person: person) { updated in
                    app.savePerson(updated)
                }
                .environment(app)
                .preferredColorScheme(app.colorScheme)
            }
        }
        .sheet(item: $exportFile) { file in
            ActivitySheet(url: file.url)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Delete \(app.person(personID)?.alias ?? "this person") for good?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete everything about them", role: .destructive) {
                app.deletePerson(personID)
                dismiss()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    private var deleteMessage: String {
        let replies = app.savedReplies(for: personID).count
        let conversations = app.sessions(for: personID).count
        return "This removes the profile, the photo, \(replies) saved \(replies == 1 ? "reply" : "replies") and \(conversations) saved \(conversations == 1 ? "conversation" : "conversations") from this iPhone. It can't be undone."
    }

    // MARK: Header and actions

    private func header(_ person: CrushProfile) -> some View {
        HStack(alignment: .center, spacing: RRSpace.m) {
            PersonAvatar(person: person, size: 76)
            VStack(alignment: .leading, spacing: RRSpace.xxs) {
                EditorialTitle(person.alias, style: .display)
                Text(person.subtitle)
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, RRSpace.s)
    }

    private func actions(_ person: CrushProfile) -> some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Button("Reply to something from \(person.alias)") {
                Haptics.tap()
                app.startCompose()
                app.compose.crush = person
                app.settings.lastCrushID = person.id
            }
            .buttonStyle(.rrPrimary)
            .accessibilityIdentifier("person-reply")

            HStack(spacing: RRSpace.m) {
                Button("Ask the coach") {
                    app.askCoach(question: nil, conversation: "", draft: "", crushID: person.id)
                }
                .buttonStyle(.rrQuiet)
                Button("Use in my keyboard") {
                    var settings = app.settings
                    settings.keyboardCrushID = person.id
                    app.settings = settings
                    Haptics.success()
                    app.toast = "\(person.alias) is selected in your keyboard."
                }
                .buttonStyle(.rrQuiet)
            }
        }
    }

    // MARK: About

    @ViewBuilder
    private func about(_ person: CrushProfile) -> some View {
        let hasAnything = !person.languageName.isEmpty || !person.cleanInterests.isEmpty
            || !person.background.trimmed.isEmpty || !person.preferences.trimmed.isEmpty || !person.details.trimmed.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("About \(person.alias)")
                .padding(.bottom, RRSpace.xs)
            if hasAnything {
                if !person.languageName.isEmpty {
                    field("Prefers to text in", person.languageName)
                }
                if !person.cleanInterests.isEmpty {
                    VStack(alignment: .leading, spacing: RRSpace.xs) {
                        Text("Into")
                            .rrText(.footnote)
                            .foregroundStyle(Color.rrTextSecondary)
                        FlowLayout {
                            ForEach(person.cleanInterests, id: \.self) { interest in
                                Text(interest)
                                    .rrText(.callout)
                                    .foregroundStyle(Color.rrText)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .overlay {
                                        Capsule().strokeBorder(Color.rrLineStrong, lineWidth: 1)
                                    }
                            }
                        }
                    }
                    .padding(.vertical, RRSpace.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rule() }
                }
                if !person.background.trimmed.isEmpty {
                    field("Background", person.background)
                }
                if !person.preferences.trimmed.isEmpty {
                    field("How they like to talk", person.preferences)
                }
                if !person.details.trimmed.isEmpty {
                    field("Worth remembering", person.details)
                }
                Rule()
            } else {
                Text("Nothing written down yet. Tap Edit to add what you know: interests, where they're from, the things worth remembering.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextSecondary)
            Text(value.trimmed)
                .rrText(.body)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, RRSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rule() }
    }

    // MARK: Notes and summaries

    @ViewBuilder
    private func notes(_ person: CrushProfile) -> some View {
        if !person.notes.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: RRSpace.xs) {
                Eyebrow(person.sharing.notes ? "Your notes" : "Your private notes")
                Text(person.notes.trimmed)
                    .rrText(.body)
                    .foregroundStyle(Color.rrText)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !person.sharing.notes {
                    Text("Only for you. ReplyRight doesn't use these.")
                        .rrText(.footnote)
                        .foregroundStyle(Color.rrTextTertiary)
                }
            }
        }
    }

    private func summaries(_ person: CrushProfile) -> some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("How it's been going")
            if person.summaries.isEmpty {
                Text("A line or two after a good conversation helps you pick up where you left off. You write these, or keep ReplyRight's read from the replies screen.")
                    .rrText(.callout)
                    .foregroundStyle(Color.rrTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(person.summaries) { summary in
                        HStack(alignment: .top, spacing: RRSpace.s) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(summary.date.formatted(.dateTime.day().month(.abbreviated)))
                                    .rrText(.footnote)
                                    .foregroundStyle(Color.rrTextSecondary)
                                Text(summary.text)
                                    .rrText(.body)
                                    .foregroundStyle(Color.rrText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Button {
                                removeSummary(summary.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.rrTextTertiary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Delete this summary")
                        }
                        .padding(.vertical, RRSpace.xs)
                        .overlay(alignment: .top) { Rule() }
                    }
                    Rule()
                }
            }

            RRField("Add a line about how it's going", text: $newSummary, lineLimit: 3)
                .accessibilityIdentifier("person-summary")
            if !newSummary.trimmed.isEmpty {
                Button("Add this note") {
                    addSummary()
                }
                .buttonStyle(.rrSecondaryCompact)
            }
        }
    }

    private func addSummary() {
        guard var person = app.person(personID) else { return }
        person.addSummary(newSummary, source: .written)
        app.savePerson(person)
        newSummary = ""
        Haptics.success()
    }

    private func removeSummary(_ id: UUID) {
        guard var person = app.person(personID) else { return }
        person.summaries.removeAll { $0.id == id }
        app.savePerson(person)
    }

    // MARK: Saved for this person

    @ViewBuilder
    private func saved(_ person: CrushProfile) -> some View {
        let replies = app.savedReplies(for: person.id)
        let conversations = app.sessions(for: person.id)

        if !replies.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Lines you kept for \(person.alias)")
                    .padding(.bottom, RRSpace.xs)
                ForEach(replies.prefix(3)) { reply in
                    SavedReplyRow(reply: reply, showsPerson: false)
                }
                Rule()
                if replies.count > 3 {
                    NavigationLink("See all \(replies.count)") {
                        SavedRepliesView(personID: person.id)
                    }
                    .buttonStyle(.rrQuiet)
                }
            }
        }

        if !conversations.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow("Conversations you saved")
                    .padding(.bottom, RRSpace.xs)
                ForEach(conversations) { session in
                    NavigationLink {
                        SessionDetailView(sessionID: session.id)
                    } label: {
                        SessionRow(session: session, showsPerson: false)
                    }
                    .buttonStyle(.rrPress)
                }
                Rule()
            }
        }
    }

    // MARK: Consent and data

    private func sharing(_ person: CrushProfile) -> some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            Eyebrow("What ReplyRight may use")
            Text(sharingText(person))
                .rrText(.callout)
                .foregroundStyle(Color.rrText)
                .fixedSize(horizontal: false, vertical: true)
            Text("It travels with a request only when you pick \(person.alias) for that reply. The photo, your saved replies and anything switched off never leave this iPhone.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Change what's shared") {
                isEditing = true
            }
            .buttonStyle(.rrQuiet)
        }
    }

    private func sharingText(_ person: CrushProfile) -> String {
        let names = person.sharedFieldNames
        guard !names.isEmpty else { return "Nothing yet." }
        return names.joined(separator: ", ") + "."
    }

    private func dataControls(_ person: CrushProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rule()
            Button {
                if let url = app.exportPerson(person.id) {
                    exportFile = ExportFile(url: url)
                } else {
                    app.toast = "The export couldn't be prepared."
                }
            } label: {
                NavigationRow(
                    title: "Export everything about \(person.alias)",
                    subtitle: "A file with the profile, notes, saved replies and conversations.",
                    systemImage: "square.and.arrow.up"
                )
            }
            .buttonStyle(.rrPress)
            .accessibilityIdentifier("person-export")
            Rule()
            Button {
                confirmsDelete = true
            } label: {
                HStack(spacing: RRSpace.s) {
                    Image(systemName: "trash")
                        .font(.system(size: 17))
                        .frame(width: 28, alignment: .leading)
                    Text("Delete \(person.alias) and everything attached")
                        .rrText(.headline)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.rrDanger)
                .padding(.vertical, RRSpace.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.rrPress)
            .accessibilityIdentifier("person-delete")
            Rule()
        }
    }
}

/// The system share sheet for an exported file. The temporary file is removed when the sheet closes.
private struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let file = url
        controller.completionWithItemsHandler = { _, _, _, _ in
            try? FileManager.default.removeItem(at: file)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Editor

/// Add or edit a person. Pass nil to create one.
///
/// Every field is optional except the name, every field is something the user
/// types, and the last section is the consent model: one switch per kind of
/// information, saying whether ReplyRight may use it.
struct PersonEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    private let existing: CrushProfile?
    private let onSave: (CrushProfile) -> Void
    private let onDelete: (() -> Void)?

    @State private var draft: CrushProfile
    @State private var newInterest = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoData: Data?
    @State private var removesPhoto = false

    init(person: CrushProfile?, onSave: @escaping (CrushProfile) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = person
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: person ?? CrushProfile(alias: ""))
    }

    var body: some View {
        NavigationStack {
            ScreenScroll(spacing: RRSpace.l) {
                photoSection

                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Eyebrow("What do you call them?")
                    RRField("A name or a nickname", text: $draft.alias)
                        .accessibilityIdentifier("person-alias")
                }

                ChoiceGroup(
                    title: "Where things stand",
                    options: CrushProfile.Stage.allCases,
                    label: { $0.title },
                    selection: $draft.stage
                )

                VStack(alignment: .leading, spacing: RRSpace.xs) {
                    Eyebrow("Where did you meet?")
                    RRField("A climbing gym, a friend's birthday, an app", text: $draft.metAt)
                        .accessibilityIdentifier("person-met")
                }

                languageSection
                interestsSection

                textSection(
                    "Background",
                    hint: "Where they're from, what they do. Only what they've told you.",
                    text: $draft.background,
                    limit: CrushProfile.maxBackgroundLength
                )
                textSection(
                    "How they like to talk",
                    hint: "Voice notes over texts. Slow to reply on weekdays. Loves a good meme.",
                    text: $draft.preferences,
                    limit: CrushProfile.maxPreferencesLength
                )
                textSection(
                    "Worth remembering",
                    hint: "Exam on Friday. Dog called Miso. Owes me a rematch at pool.",
                    text: $draft.details,
                    limit: CrushProfile.maxDetailsLength
                )
                textSection(
                    "Your notes",
                    hint: "Anything you want to remember for yourself.",
                    text: $draft.notes,
                    limit: CrushProfile.maxNotesLength
                )

                sharingSection

                Text("ReplyRight never fills in or guesses anything about a person. What's here is what you wrote.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)

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
                    .disabled(draft.alias.trimmed.isEmpty)
                    .accessibilityIdentifier("person-save")
                }
            }
            .task {
                if let existing, existing.hasPhoto, let data = app.store.loadPersonPhoto(existing.id) {
                    photo = UIImage(data: data)
                }
            }
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task { await loadPhoto(item) }
            }
        }
    }

    // MARK: Photo

    private var photoSection: some View {
        HStack(alignment: .center, spacing: RRSpace.m) {
            ZStack {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Color.rrAccentSoft)
                    Image(systemName: "person")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.rrAccent)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: RRSpace.xxs) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(photo == nil ? "Add a photo" : "Change photo")
                }
                .buttonStyle(.rrQuiet)
                if photo != nil {
                    Button("Remove photo") {
                        photo = nil
                        photoData = nil
                        removesPhoto = true
                    }
                    .buttonStyle(.rrQuiet)
                }
                Text("Optional. It stays on this iPhone and is never sent anywhere.")
                    .rrText(.footnote)
                    .foregroundStyle(Color.rrTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let prepared = await Task.detached(priority: .userInitiated) {
            ProfilePhoto.prepare(data)
        }.value
        guard let prepared, let image = UIImage(data: prepared) else {
            app.toast = "That photo couldn't be used."
            return
        }
        photoData = prepared
        photo = image
        removesPhoto = false
    }

    // MARK: Language and interests

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("What language do they prefer to text in?")
            FlowLayout {
                RRChip("Not sure", isSelected: draft.language.isEmpty) {
                    draft.language = ""
                    Haptics.select()
                }
                ForEach(ReplyLanguage.all) { language in
                    RRChip(language.name, isSelected: draft.language == language.id) {
                        draft.language = language.id
                        Haptics.select()
                    }
                }
            }
        }
    }

    private var interestsSection: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            Eyebrow("Interests and hobbies")
            if !draft.interests.isEmpty {
                FlowLayout {
                    ForEach(draft.interests, id: \.self) { interest in
                        Button {
                            draft.interests.removeAll { $0 == interest }
                        } label: {
                            HStack(spacing: 6) {
                                Text(interest)
                                    .rrText(.callout)
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .opacity(0.7)
                            }
                            .foregroundStyle(Color.rrText)
                            .padding(.horizontal, 13)
                            .frame(minHeight: 44)
                            .overlay {
                                Capsule().strokeBorder(Color.rrLineStrong, lineWidth: 1)
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.rrPress)
                        .accessibilityLabel("Remove \(interest)")
                    }
                }
            }
            if draft.interests.count < CrushProfile.maxInterests {
                HStack(alignment: .bottom, spacing: RRSpace.s) {
                    RRField("Climbing, ramen, bad horror films", text: $newInterest)
                        .submitLabel(.done)
                        .onSubmit { addInterest() }
                        .accessibilityIdentifier("person-interest")
                    Button("Add") {
                        addInterest()
                    }
                    .buttonStyle(.rrSecondaryCompact)
                    .disabled(newInterest.trimmed.isEmpty)
                }
            }
        }
    }

    /// Adds what was typed. Several interests can be entered at once, separated by commas.
    private func addInterest() {
        let pieces = newInterest.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return }
        var updated = draft
        updated.interests.append(contentsOf: pieces)
        updated.interests = updated.cleanInterests
        draft = updated
        newInterest = ""
        Haptics.select()
    }

    private func textSection(_ title: String, hint: String, text: Binding<String>, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: RRSpace.xs) {
            Eyebrow(title)
            RRTextArea(text: text, placeholder: hint, minHeight: 72)
            LimitLabel(count: text.wrappedValue.count, limit: limit)
        }
    }

    // MARK: Consent

    private var sharingSection: some View {
        VStack(alignment: .leading, spacing: RRSpace.s) {
            EditorialTitle("What may ReplyRight use?", style: .titleSmall)
            Text("When you pick this person for a reply, ReplyRight sends their name, where things stand, and whatever is switched on here, with that one request. Nothing is sent at any other time.")
                .rrText(.callout)
                .foregroundStyle(Color.rrTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                sharingToggle("Where you met and their language", isOn: $draft.sharing.basics)
                sharingToggle("Interests and hobbies", isOn: $draft.sharing.interests)
                sharingToggle("Background", isOn: $draft.sharing.background)
                sharingToggle("How they like to talk", isOn: $draft.sharing.preferences)
                sharingToggle("Things worth remembering", isOn: $draft.sharing.details)
                sharingToggle("Summaries of earlier conversations", isOn: $draft.sharing.history)
                sharingToggle("Your notes", isOn: $draft.sharing.notes)
                Rule()
            }

            Text("The photo, saved replies and saved conversations are never sent, whatever is switched on.")
                .rrText(.footnote)
                .foregroundStyle(Color.rrTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sharingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .rrText(.body)
                .foregroundStyle(Color.rrText)
        }
        .tint(Color.rrAccent)
        .padding(.vertical, RRSpace.xs)
        .frame(minHeight: 48)
        .overlay(alignment: .top) { Rule() }
    }

    // MARK: Saving

    private func save() {
        var person = draft
        person.alias = String(person.alias.trimmed.prefix(CrushProfile.maxAliasLength))
        person.metAt = String(person.metAt.trimmed.prefix(CrushProfile.maxMetAtLength))
        person.interests = person.cleanInterests
        person.background = String(person.background.trimmed.prefix(CrushProfile.maxBackgroundLength))
        person.preferences = String(person.preferences.trimmed.prefix(CrushProfile.maxPreferencesLength))
        person.details = String(person.details.trimmed.prefix(CrushProfile.maxDetailsLength))
        person.notes = String(person.notes.trimmed.prefix(CrushProfile.maxNotesLength))

        if let photoData {
            person.hasPhoto = app.store.savePersonPhoto(photoData, for: person.id)
        } else if removesPhoto {
            app.store.deletePersonPhoto(person.id)
            person.hasPhoto = false
        }
        person.updatedAt = Date()

        onSave(person)
        Haptics.success()
        dismiss()
    }
}

/// Prepares a picked image for use as a profile photo: a small square JPEG with its metadata removed.
enum ProfilePhoto {
    static let side: CGFloat = 480

    static func prepare(_ data: Data) -> Data? {
        // Reuses the screenshot pipeline to decode safely at a reduced size and strip metadata.
        guard let reduced = ScreenshotPreparer.prepare(data), let image = UIImage(data: reduced) else { return nil }
        let shortest = min(image.size.width, image.size.height)
        guard shortest >= 1 else { return nil }
        let scale = side / shortest
        let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (side - scaled.width) / 2, y: (side - scaled.height) / 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: scaled))
        }
        return square.jpegData(compressionQuality: 0.82)
    }
}
