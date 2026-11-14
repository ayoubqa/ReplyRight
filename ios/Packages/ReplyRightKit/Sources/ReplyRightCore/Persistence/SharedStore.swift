import Foundation

/// Everything ReplyRight stores on the device, in one place.
///
/// The files live in the App Group container so the keyboard and the share
/// sheet can read what the user set up in the app (voice profile, saved
/// replies) and hand context back. Nothing here is uploaded on its own; values
/// travel only inside requests the user starts.
///
/// Reads always go to disk, because three processes share these files.
public final class SharedStore: @unchecked Sendable {
    public static let shared = SharedStore()

    private enum File {
        static let voice = "voice.json"
        static let savedReplies = "saved-replies.json"
        static let sessions = "sessions.json"
        static let people = "people.json"
        static let peopleFolder = "people"
        static let styles = "styles.json"
        static let settings = "settings.json"
        static let keyboardContext = "keyboard-context.json"
        static let keyboardCheckIn = "keyboard-checkin.json"
        static let keyboardSetup = "keyboard-setup.json"
        static let activity = "activity.json"
        static let inbox = "inbox.json"
        static let inboxFolder = "inbox"
        static let entitlement = "entitlement.json"
        static let service = "service.json"
        static let installID = "install-id"
    }

    public let files: JSONFileStore

    public init(directory: URL = AppGroup.storageDirectory()) {
        self.files = JSONFileStore(directory: directory)
    }

    // MARK: My Voice

    public func loadVoice() -> VoiceProfile {
        files.read(VoiceProfile.self, name: File.voice) ?? .standard
    }

    @discardableResult
    public func saveVoice(_ voice: VoiceProfile) -> Bool {
        files.write(voice, name: File.voice)
    }

    // MARK: Library

    public func loadSavedReplies() -> [SavedReply] {
        files.read([SavedReply].self, name: File.savedReplies) ?? []
    }

    @discardableResult
    public func saveSavedReplies(_ replies: [SavedReply]) -> Bool {
        files.write(replies, name: File.savedReplies)
    }

    public func loadSessions() -> [SavedSession] {
        files.read([SavedSession].self, name: File.sessions) ?? []
    }

    @discardableResult
    public func saveSessions(_ sessions: [SavedSession]) -> Bool {
        files.write(sessions, name: File.sessions)
    }

    public func loadPeople() -> [CrushProfile] {
        files.read([CrushProfile].self, name: File.people) ?? []
    }

    @discardableResult
    public func savePeople(_ people: [CrushProfile]) -> Bool {
        files.write(people, name: File.people)
    }

    // MARK: Profiles

    private func photoName(for id: UUID) -> String {
        "\(File.peopleFolder)/\(id.uuidString.lowercased()).jpg"
    }

    /// The photo the user picked for a profile, as JPEG data.
    public func loadPersonPhoto(_ id: UUID) -> Data? {
        files.readData(name: photoName(for: id))
    }

    @discardableResult
    public func savePersonPhoto(_ data: Data, for id: UUID) -> Bool {
        files.writeData(data, name: photoName(for: id))
    }

    public func deletePersonPhoto(_ id: UUID) {
        files.delete(name: photoName(for: id))
    }

    /// Everything stored about one person, as pretty-printed JSON the user can keep.
    public func exportPerson(_ id: UUID) -> Data? {
        guard let profile = loadPeople().first(where: { $0.id == id }) else { return nil }
        let export = ProfileExport(
            profile: profile,
            savedReplies: loadSavedReplies().filter { $0.crushID == id },
            conversations: loadSessions().filter { $0.crushID == id },
            photoJPEGBase64: loadPersonPhoto(id)?.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(export)
    }

    /// Permanently removes a profile and everything attached to it: the photo,
    /// the replies and conversations saved for that person, and any context
    /// about them that was handed to the keyboard.
    public func deletePerson(_ id: UUID) {
        savePeople(loadPeople().filter { $0.id != id })
        deletePersonPhoto(id)
        saveSavedReplies(loadSavedReplies().filter { $0.crushID != id })
        saveSessions(loadSessions().filter { $0.crushID != id })
        if let context = files.read(KeyboardContext.self, name: File.keyboardContext), context.crushID == id {
            clearKeyboardContext()
        }
        var settings = loadSettings()
        var changed = false
        if settings.lastCrushID == id {
            settings.lastCrushID = nil
            changed = true
        }
        if settings.keyboardCrushID == id {
            settings.keyboardCrushID = nil
            changed = true
        }
        if changed {
            saveSettings(settings)
        }
    }

    public func loadStyles() -> [FavouriteStyle] {
        files.read([FavouriteStyle].self, name: File.styles) ?? []
    }

    @discardableResult
    public func saveStyles(_ styles: [FavouriteStyle]) -> Bool {
        files.write(styles, name: File.styles)
    }

    // MARK: Settings

    public func loadSettings() -> AppSettings {
        files.read(AppSettings.self, name: File.settings) ?? AppSettings()
    }

    @discardableResult
    public func saveSettings(_ settings: AppSettings) -> Bool {
        files.write(settings, name: File.settings)
    }

    // MARK: Keyboard context

    /// Conversation text the user handed to the keyboard. Expired context is deleted on read.
    public func loadKeyboardContext(now: Date = Date()) -> KeyboardContext? {
        guard let context = files.read(KeyboardContext.self, name: File.keyboardContext) else { return nil }
        if context.isExpired(now: now) || context.text.trimmed.isEmpty {
            files.delete(name: File.keyboardContext)
            return nil
        }
        return context
    }

    @discardableResult
    public func saveKeyboardContext(_ context: KeyboardContext) -> Bool {
        files.write(context, name: File.keyboardContext)
    }

    public func clearKeyboardContext() {
        files.delete(name: File.keyboardContext)
    }

    // MARK: Keyboard status

    /// The keyboard's most recent check-in. Only a keyboard with Full Access
    /// can write it, so its absence says nothing about whether the keyboard is on.
    public func loadKeyboardCheckIn() -> KeyboardCheckIn? {
        files.read(KeyboardCheckIn.self, name: File.keyboardCheckIn)
    }

    @discardableResult
    public func saveKeyboardCheckIn(_ checkIn: KeyboardCheckIn) -> Bool {
        files.write(checkIn, name: File.keyboardCheckIn)
    }

    /// What the app remembers about keyboard setup (confirmations and tests).
    public func loadKeyboardSetup() -> KeyboardSetupRecord {
        files.read(KeyboardSetupRecord.self, name: File.keyboardSetup) ?? KeyboardSetupRecord()
    }

    @discardableResult
    public func saveKeyboardSetup(_ record: KeyboardSetupRecord) -> Bool {
        files.write(record, name: File.keyboardSetup)
    }

    // MARK: Activity counts

    /// Daily counts of suggestions shown and used. Numbers only, never text.
    public func loadActivity() -> ProductActivity {
        files.read(ProductActivity.self, name: File.activity) ?? ProductActivity()
    }

    /// Adds one event to today's counts. The app and the keyboard both call
    /// this; each reads the file fresh, so the window for a lost count is one
    /// write.
    @discardableResult
    public func recordActivity(_ event: ProductActivity.Event, at date: Date = Date()) -> ProductActivity {
        var activity = loadActivity()
        activity.record(event, at: date)
        files.write(activity, name: File.activity)
        return activity
    }

    // MARK: Share inbox

    /// Stores something shared from another app until ReplyRight is opened.
    /// Screenshots are written as temporary files and removed by `clearInbox`.
    @discardableResult
    public func saveInbox(text: String, images: [Data]) -> SharedInboxItem? {
        clearInbox()
        var names: [String] = []
        for (index, data) in images.prefix(RequestLimits.maxImages).enumerated() {
            let name = "\(File.inboxFolder)/shot-\(index + 1).jpg"
            if files.writeData(data, name: name) {
                names.append(name)
            }
        }
        let item = SharedInboxItem(text: text.trimmed, imageFiles: names)
        guard !item.text.isEmpty || !names.isEmpty else { return nil }
        return files.write(item, name: File.inbox) ? item : nil
    }

    /// The pending shared item, if any. Expired items are deleted on read.
    public func loadInbox(now: Date = Date()) -> SharedInboxItem? {
        guard let item = files.read(SharedInboxItem.self, name: File.inbox) else { return nil }
        if item.isExpired(now: now) {
            clearInbox()
            return nil
        }
        return item
    }

    public func inboxImages(for item: SharedInboxItem) -> [Data] {
        item.imageFiles.compactMap { files.readData(name: $0) }
    }

    public func clearInbox() {
        files.delete(name: File.inbox)
        files.delete(name: File.inboxFolder)
    }

    // MARK: Subscription and service state

    public func loadEntitlement() -> EntitlementSnapshot? {
        files.read(EntitlementSnapshot.self, name: File.entitlement)
    }

    public func saveEntitlement(_ snapshot: EntitlementSnapshot?) {
        if let snapshot {
            files.write(snapshot, name: File.entitlement)
        } else {
            files.delete(name: File.entitlement)
        }
    }

    public func loadService() -> ServiceSnapshot {
        files.read(ServiceSnapshot.self, name: File.service) ?? ServiceSnapshot()
    }

    @discardableResult
    public func saveService(_ snapshot: ServiceSnapshot) -> Bool {
        files.write(snapshot, name: File.service)
    }

    // MARK: Install identity mirror

    func loadInstallID() -> String? {
        guard let data = files.readData(name: File.installID), let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let clean = value.trimmed
        return UUID(uuidString: clean) != nil ? clean : nil
    }

    func saveInstallID(_ id: String) {
        files.writeData(Data(id.utf8), name: File.installID)
    }

    // MARK: Erasing

    /// What `erase` can remove. The user picks from these in the Privacy Center.
    public enum Category: String, CaseIterable, Identifiable, Sendable {
        case sharedContext
        case savedReplies
        case sessions
        case people
        case voice
        case styles

        public var id: String { rawValue }
    }

    public func erase(_ category: Category) {
        switch category {
        case .sharedContext:
            clearKeyboardContext()
            clearInbox()
        case .savedReplies:
            files.delete(name: File.savedReplies)
        case .sessions:
            files.delete(name: File.sessions)
        case .people:
            files.delete(name: File.people)
            files.delete(name: File.peopleFolder)
        case .voice:
            files.delete(name: File.voice)
        case .styles:
            files.delete(name: File.styles)
        }
    }

    /// Removes everything the user created. Keeps the anonymous install id (so
    /// daily limits keep working) and the subscription snapshot (so Pro is not lost).
    public func eraseEverything() {
        files.deleteAll(except: [File.installID, File.entitlement])
    }
}
