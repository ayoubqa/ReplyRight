import XCTest
@testable import ReplyRightCore

/// Storage tests run against a throwaway directory, never the real App Group container.
final class SharedStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SharedStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("replyright-tests-\(UUID().uuidString)", isDirectory: true)
        store = SharedStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func usage(tier: Tier = .free, used: Int = 2) -> Usage {
        Usage(
            tier: tier,
            generations: Usage.Counter(used: used, limit: 10, remaining: 10 - used),
            coach: Usage.Counter(used: 0, limit: 3, remaining: 3),
            resetsAt: "2026-11-11T00:00:00.000Z"
        )
    }

    // MARK: Defaults and round trips

    func testEmptyStoreReturnsDefaults() {
        XCTAssertEqual(store.loadVoice(), .standard)
        XCTAssertEqual(store.loadSettings(), AppSettings())
        XCTAssertTrue(store.loadSavedReplies().isEmpty)
        XCTAssertTrue(store.loadSessions().isEmpty)
        XCTAssertTrue(store.loadPeople().isEmpty)
        XCTAssertTrue(store.loadStyles().isEmpty)
        XCTAssertNil(store.loadKeyboardContext())
        XCTAssertNil(store.loadInbox())
        XCTAssertNil(store.loadEntitlement())
        XCTAssertEqual(store.loadService().plans, .fallback)
        XCTAssertEqual(store.lastKnownTier(), .free)
    }

    func testEverythingRoundTrips() {
        var voice = VoiceProfile(defaultTone: .charming, emoji: .none)
        voice.addSample("ok wait that's perfect", source: .added, now: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(store.saveVoice(voice))
        XCTAssertEqual(store.loadVoice(), voice)

        var settings = AppSettings()
        settings.hasOnboarded = true
        settings.confirmedAdult = true
        settings.appearance = .daylight
        settings.learnFromEdits = true
        settings.apiBaseURLOverride = "http://my-mac.local:3000"
        store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings(), settings)

        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let replies = [SavedReply(text: "bold of you", style: "Playful", intent: .laugh, createdAt: created)]
        store.saveSavedReplies(replies)
        XCTAssertEqual(store.loadSavedReplies(), replies)

        let people = [CrushProfile(alias: "Sam", stage: .beenOnDates, notes: "climbs", createdAt: created)]
        store.savePeople(people)
        XCTAssertEqual(store.loadPeople(), people)

        let styles = [FavouriteStyle(name: "Calm", instruction: "confident but not arrogant")]
        store.saveStyles(styles)
        XCTAssertEqual(store.loadStyles(), styles)

        let option = ReplyOption(suggestion: Suggestion(style: "Most natural", text: "haha fair", why: "Easy."))
        let sessions = [
            SavedSession(
                title: "are we still on?",
                createdAt: created,
                conversation: "Them: are we still on?",
                read: "They're checking in.",
                intent: .keepGoing,
                instruction: "",
                options: [option],
                crushID: people[0].id
            ),
        ]
        store.saveSessions(sessions)
        XCTAssertEqual(store.loadSessions(), sessions)
    }

    func testSettingsFromAnOlderVersionStillLoad() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = Data(#"{"hasOnboarded":true,"confirmedAdult":true}"#.utf8)
        try old.write(to: directory.appendingPathComponent("settings.json"))

        let settings = store.loadSettings()
        XCTAssertTrue(settings.hasOnboarded)
        XCTAssertEqual(settings.appearance, .evening)
        XCTAssertFalse(settings.learnFromEdits, "Learning from edits is opt-in")
        XCTAssertTrue(settings.hapticsEnabled)
    }

    func testCorruptFilesFallBackToDefaults() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("voice.json"))
        XCTAssertEqual(store.loadVoice(), .standard)
    }

    // MARK: Keyboard context

    func testKeyboardContextIsReturnedWhileFreshAndDeletedOnceExpired() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let context = KeyboardContext(text: "Them: free on friday?", source: .clipboard, createdAt: created)
        XCTAssertTrue(store.saveKeyboardContext(context))

        XCTAssertEqual(store.loadKeyboardContext(now: created.addingTimeInterval(3600)), context)
        XCTAssertNil(store.loadKeyboardContext(now: created.addingTimeInterval(25 * 3600)))
        XCTAssertFalse(store.files.exists(name: "keyboard-context.json"), "Expired context is removed from disk, not just hidden")
    }

    func testKeyboardContextCanBeCleared() {
        store.saveKeyboardContext(KeyboardContext(text: "Them: hi", source: .app))
        store.clearKeyboardContext()
        XCTAssertNil(store.loadKeyboardContext())
    }

    // MARK: Share inbox

    func testInboxHoldsTextAndScreenshotsUntilCleared() throws {
        let first = Data([0xFF, 0xD8, 0x01])
        let second = Data([0xFF, 0xD8, 0x02])
        let saved = try XCTUnwrap(store.saveInbox(text: "  what they said  ", images: [first, second]))
        XCTAssertEqual(saved.text, "what they said")
        XCTAssertEqual(saved.imageFiles.count, 2)

        let loaded = try XCTUnwrap(store.loadInbox())
        XCTAssertEqual(loaded, saved)
        XCTAssertEqual(store.inboxImages(for: loaded), [first, second])

        store.clearInbox()
        XCTAssertNil(store.loadInbox())
        XCTAssertTrue(store.inboxImages(for: loaded).isEmpty, "Screenshot files are deleted with the inbox item")
    }

    func testInboxExpiresAndRefusesNothing() throws {
        XCTAssertNil(store.saveInbox(text: "   ", images: []), "There is nothing to keep")

        let saved = try XCTUnwrap(store.saveInbox(text: "hello", images: [Data([1, 2, 3])]))
        let later = saved.createdAt.addingTimeInterval(SharedInboxItem.lifetime + 60)
        XCTAssertNil(store.loadInbox(now: later))
        XCTAssertTrue(store.inboxImages(for: saved).isEmpty, "Expired screenshots are removed from disk")
    }

    func testInboxKeepsAtMostFourScreenshotsAndReplacesTheOldItem() throws {
        let images = (0..<6).map { Data([UInt8($0)]) }
        let saved = try XCTUnwrap(store.saveInbox(text: "", images: images))
        XCTAssertEqual(saved.imageFiles.count, RequestLimits.maxImages)

        let replacement = try XCTUnwrap(store.saveInbox(text: "newer", images: []))
        XCTAssertEqual(store.loadInbox(), replacement)
        XCTAssertTrue(store.inboxImages(for: saved).isEmpty)
    }

    // MARK: Subscription and service state

    func testEntitlementSnapshot() {
        let snapshot = EntitlementSnapshot(
            jws: "header.payload.signature",
            productID: AppConfig.annualProductID,
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        store.saveEntitlement(snapshot)
        XCTAssertEqual(store.loadEntitlement(), snapshot)
        XCTAssertTrue(snapshot.isActive(now: Date(timeIntervalSince1970: 1_900_000_000)))
        XCTAssertFalse(snapshot.isActive(now: Date(timeIntervalSince1970: 2_100_000_000)))

        store.saveEntitlement(nil)
        XCTAssertNil(store.loadEntitlement())
    }

    func testRecordingUsageKeepsModeUnlessANewOneIsGiven() {
        store.record(usage: usage(tier: .pro, used: 4), mode: .live)
        XCTAssertEqual(store.loadService().usage?.generations.used, 4)
        XCTAssertEqual(store.loadService().mode, .live)
        XCTAssertEqual(store.lastKnownTier(), .pro)

        store.record(usage: usage(tier: .free, used: 5), mode: nil)
        XCTAssertEqual(store.loadService().mode, .live, "A nil mode leaves the last known mode in place")
        XCTAssertEqual(store.lastKnownTier(), .free)
    }

    // MARK: Erasing

    func testEraseByCategory() {
        store.saveSavedReplies([SavedReply(text: "hey", style: "Natural")])
        store.savePeople([CrushProfile(alias: "Sam")])
        store.saveKeyboardContext(KeyboardContext(text: "Them: hi", source: .app))
        store.saveInbox(text: "shared", images: [])

        store.erase(.savedReplies)
        XCTAssertTrue(store.loadSavedReplies().isEmpty)
        XCTAssertEqual(store.loadPeople().count, 1, "Other categories are untouched")

        store.erase(.sharedContext)
        XCTAssertNil(store.loadKeyboardContext())
        XCTAssertNil(store.loadInbox())

        store.erase(.people)
        XCTAssertTrue(store.loadPeople().isEmpty)
    }

    func testEraseEverythingKeepsOnlyInstallIdentityAndSubscription() {
        let installID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"
        store.saveInstallID(installID)
        store.saveEntitlement(EntitlementSnapshot(jws: "a.b.c", productID: AppConfig.monthlyProductID, expiresAt: nil))
        store.saveVoice(VoiceProfile(defaultTone: .confident))
        store.saveSavedReplies([SavedReply(text: "hey", style: "Natural")])
        store.saveSessions([
            SavedSession(title: "t", conversation: "c", read: "r", intent: .natural, instruction: "", options: [], crushID: nil),
        ])
        store.saveInbox(text: "shared", images: [Data([1])])
        var settings = AppSettings()
        settings.hasOnboarded = true
        store.saveSettings(settings)

        store.eraseEverything()

        XCTAssertEqual(store.loadVoice(), .standard)
        XCTAssertTrue(store.loadSavedReplies().isEmpty)
        XCTAssertTrue(store.loadSessions().isEmpty)
        XCTAssertNil(store.loadInbox())
        XCTAssertFalse(store.loadSettings().hasOnboarded, "The app returns to first run")
        XCTAssertEqual(store.loadInstallID(), installID, "Daily limits must not reset by erasing data")
        XCTAssertEqual(store.loadEntitlement()?.jws, "a.b.c", "Erasing data must not lose a subscription")
    }

    func testInstallIDMirrorRejectsAnythingThatIsNotAUUID() {
        store.saveInstallID("not-a-uuid")
        XCTAssertNil(store.loadInstallID())
    }

    func testWritesFailQuietlyWhenTheContainerIsReadOnly() {
        // A keyboard without Full Access cannot write to the shared container.
        let unwritable = SharedStore(directory: URL(fileURLWithPath: "/dev/null/replyright"))
        XCTAssertFalse(unwritable.saveVoice(.standard))
        XCTAssertEqual(unwritable.loadVoice(), .standard)
    }
}
