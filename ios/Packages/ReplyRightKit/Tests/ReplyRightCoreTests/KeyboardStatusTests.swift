import XCTest
@testable import ReplyRightCore

/// The keyboard status must only ever claim what the evidence shows.
final class KeyboardStatusTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Deriving the status

    func testNoEvidenceMeansNotSetUp() {
        XCTAssertEqual(KeyboardSetupStatus.derive(checkIn: nil, record: KeyboardSetupRecord()), .notSetUp)
    }

    func testTheUsersWordAloneIsNotReady() {
        let record = KeyboardSetupRecord(userConfirmedEnabledAt: start)
        let status = KeyboardSetupStatus.derive(checkIn: nil, record: record)
        XCTAssertEqual(status, .enabledNotTested(confirmedAt: start))
        XCTAssertFalse(status.isReady, "Saying it is on is not proof that it works")
    }

    func testACheckInWithFullAccessIsReady() {
        let checkIn = KeyboardCheckIn(lastSeen: start, hasFullAccess: true, keyboardVersion: "1.0")
        XCTAssertEqual(KeyboardSetupStatus.derive(checkIn: checkIn, record: KeyboardSetupRecord()), .ready(lastConfirmed: start))
    }

    func testACheckInWithoutFullAccessIsIgnored() {
        // A keyboard without Full Access cannot write a check-in, so one that
        // claims it has none is not evidence of anything.
        let checkIn = KeyboardCheckIn(lastSeen: start, hasFullAccess: false, keyboardVersion: "1.0")
        XCTAssertEqual(KeyboardSetupStatus.derive(checkIn: checkIn, record: KeyboardSetupRecord()), .notSetUp)
    }

    func testATestWithoutFullAccessIsLimited() {
        let record = KeyboardSetupRecord(userConfirmedEnabledAt: start, lastTestAt: start.addingTimeInterval(60), lastTestHadFullAccess: false)
        XCTAssertEqual(KeyboardSetupStatus.derive(checkIn: nil, record: record), .limitedAccess(testedAt: start.addingTimeInterval(60)))
    }

    func testATestWithFullAccessIsReady() {
        let record = KeyboardSetupRecord(lastTestAt: start, lastTestHadFullAccess: true)
        XCTAssertEqual(KeyboardSetupStatus.derive(checkIn: nil, record: record), .ready(lastConfirmed: start))
    }

    func testALaterLimitedTestOverridesAnOlderCheckIn() {
        let checkIn = KeyboardCheckIn(lastSeen: start, hasFullAccess: true, keyboardVersion: "1.0")
        let record = KeyboardSetupRecord(lastTestAt: start.addingTimeInterval(day), lastTestHadFullAccess: false)
        XCTAssertEqual(
            KeyboardSetupStatus.derive(checkIn: checkIn, record: record),
            .limitedAccess(testedAt: start.addingTimeInterval(day)),
            "Turning Full Access off and testing again must show up"
        )
    }

    func testALaterCheckInOverridesAnOlderLimitedTest() {
        let record = KeyboardSetupRecord(lastTestAt: start, lastTestHadFullAccess: false)
        let checkIn = KeyboardCheckIn(lastSeen: start.addingTimeInterval(day), hasFullAccess: true, keyboardVersion: "1.0")
        XCTAssertEqual(KeyboardSetupStatus.derive(checkIn: checkIn, record: record), .ready(lastConfirmed: start.addingTimeInterval(day)))
    }

    func testEveryStatusExplainsItself() {
        let all: [KeyboardSetupStatus] = [.notSetUp, .enabledNotTested(confirmedAt: start), .limitedAccess(testedAt: start), .ready(lastConfirmed: start)]
        for status in all {
            XCTAssertFalse(status.title.isEmpty)
            XCTAssertFalse(status.explanation.isEmpty)
        }
        XCTAssertNil(KeyboardSetupStatus.notSetUp.evidenceDate)
        XCTAssertEqual(KeyboardSetupStatus.ready(lastConfirmed: start).evidenceDate, start)
    }

    func testTheHomeCardComesBackAfterAWeek() {
        let record = KeyboardSetupRecord(homeCardSnoozedAt: start)
        XCTAssertTrue(record.isHomeCardSnoozed(now: start.addingTimeInterval(6 * day)))
        XCTAssertFalse(record.isHomeCardSnoozed(now: start.addingTimeInterval(8 * day)))
        XCTAssertFalse(KeyboardSetupRecord().isHomeCardSnoozed(now: start))
    }

    func testOlderSetupRecordsStillLoad() throws {
        let data = Data(#"{"userConfirmedEnabledAt": 700000000, "somethingNew": true}"#.utf8)
        let record = try JSONDecoder().decode(KeyboardSetupRecord.self, from: data)
        XCTAssertEqual(record.userConfirmedEnabledAt, Date(timeIntervalSinceReferenceDate: 700_000_000))
        XCTAssertNil(record.lastTestAt)
    }

    // MARK: The test phrase

    func testThePhraseIsDetectedWithItsAccessLevel() {
        XCTAssertEqual(KeyboardHandshake.detect(in: KeyboardHandshake.phrase(hasFullAccess: true)), .init(hasFullAccess: true))
        XCTAssertEqual(KeyboardHandshake.detect(in: KeyboardHandshake.phrase(hasFullAccess: false)), .init(hasFullAccess: false))
    }

    func testTheLatestPhraseInTheFieldWins() {
        let text = "hello " + KeyboardHandshake.phrase(hasFullAccess: false) + " " + KeyboardHandshake.phrase(hasFullAccess: true)
        XCTAssertEqual(KeyboardHandshake.detect(in: text), .init(hasFullAccess: true))
    }

    func testOrdinaryTypingIsNotMistakenForTheKeyboard() {
        XCTAssertNil(KeyboardHandshake.detect(in: "ReplyRight Keyboard is great"))
        XCTAssertNil(KeyboardHandshake.detect(in: "Full Access on"))
        XCTAssertNil(KeyboardHandshake.detect(in: KeyboardHandshake.marker))
        XCTAssertNil(KeyboardHandshake.detect(in: ""))
    }

    // MARK: Storage

    func testStatusFilesRoundTripAndAreErasedWithEverything() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("replyright-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedStore(directory: directory)

        XCTAssertNil(store.loadKeyboardCheckIn())
        XCTAssertEqual(store.loadKeyboardSetup(), KeyboardSetupRecord())

        let checkIn = KeyboardCheckIn(lastSeen: start, hasFullAccess: true, keyboardVersion: "1.2")
        let record = KeyboardSetupRecord(userConfirmedEnabledAt: start, lastTestAt: start, lastTestHadFullAccess: true)
        XCTAssertTrue(store.saveKeyboardCheckIn(checkIn))
        XCTAssertTrue(store.saveKeyboardSetup(record))
        XCTAssertEqual(store.loadKeyboardCheckIn(), checkIn)
        XCTAssertEqual(store.loadKeyboardSetup(), record)

        store.recordActivity(.suggestionUsed(.keyboard), at: start)
        XCTAssertEqual(store.loadActivity().totalKeyboardInsertions, 1)

        store.eraseEverything()
        XCTAssertNil(store.loadKeyboardCheckIn())
        XCTAssertEqual(store.loadKeyboardSetup(), KeyboardSetupRecord())
        XCTAssertEqual(store.loadActivity(), ProductActivity())
    }
}

/// Activity is counted per day, as numbers only, and summarised per week.
final class ProductActivityTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60
    // 2026-11-14 12:00 UTC
    private let today = Date(timeIntervalSince1970: 1_794_657_600)

    func testAWeekIsSuccessfulOnlyWhenASuggestionWasGeneratedAndUsed() {
        var activity = ProductActivity()
        activity.record(.suggestionsShown(.app), at: today)
        XCTAssertFalse(activity.lastSevenDays(endingAt: today).isSuccessful, "Seeing suggestions is not using one")

        activity.record(.suggestionUsed(.app), at: today)
        XCTAssertTrue(activity.lastSevenDays(endingAt: today).isSuccessful)
        XCTAssertTrue(activity.hasUsedSuggestion)
    }

    func testKeyboardInsertionsAreCountedSeparately() {
        var activity = ProductActivity()
        activity.record(.suggestionsShown(.keyboard), at: today)
        activity.record(.suggestionUsed(.keyboard), at: today)
        activity.record(.suggestionUsed(.app), at: today)
        activity.record(.suggestionUsed(.share), at: today)

        let week = activity.lastSevenDays(endingAt: today)
        XCTAssertEqual(week.suggestionsShown, 1)
        XCTAssertEqual(week.keyboardSuggestionsShown, 1)
        XCTAssertEqual(week.suggestionsUsed, 3)
        XCTAssertEqual(week.keyboardInsertions, 1)
    }

    func testTheWeekCoversSevenDaysAndNoMore() {
        var activity = ProductActivity()
        activity.record(.suggestionUsed(.app), at: today.addingTimeInterval(-6 * day))
        activity.record(.suggestionUsed(.app), at: today.addingTimeInterval(-7 * day))
        XCTAssertEqual(activity.lastSevenDays(endingAt: today).suggestionsUsed, 1)
    }

    func testHistoryOlderThanTwelveWeeksIsDropped() {
        var activity = ProductActivity()
        activity.record(.suggestionUsed(.app), at: today.addingTimeInterval(-100 * day))
        activity.record(.suggestionUsed(.app), at: today)
        XCTAssertEqual(activity.days.count, 1)
        XCTAssertEqual(activity.days.keys.first, "2026-11-14")
    }

    func testDaysAreKeyedInUTC() {
        XCTAssertEqual(ProductActivity.key(for: today), "2026-11-14")
        XCTAssertEqual(ProductActivity.key(for: Date(timeIntervalSince1970: 0)), "1970-01-01")
    }

    func testOnlyCountsAreStored() throws {
        var activity = ProductActivity()
        activity.record(.suggestionsShown(.app), at: today)
        activity.record(.suggestionUsed(.keyboard), at: today)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = try XCTUnwrap(String(data: encoder.encode(activity), encoding: .utf8))
        XCTAssertEqual(
            json,
            #"{"days":{"2026-11-14":{"keyboardInsertions":1,"keyboardSuggestionsShown":0,"suggestionsShown":1,"suggestionsUsed":1}}}"#
        )
        for word in ["text", "name", "message", "reply"] {
            XCTAssertFalse(json.lowercased().contains("\"\(word)"), "Activity must not hold \(word)")
        }
    }

    func testNewInstallsFollowTheIPhoneAppearance() {
        XCTAssertEqual(AppSettings().appearance, .system)
    }
}

/// The worked example shown on Home and in onboarding. It is written in
/// advance, so it must stand on its own without any request.
final class SampleConversationTests: XCTestCase {
    func testTheExampleHasAConversationAndThreeDistinctReplies() {
        XCTAssertEqual(SampleConversation.lines.first?.speaker, .them)
        XCTAssertEqual(SampleConversation.lastMessage, "someone deciding whether we can be friends")
        XCTAssertTrue(SampleConversation.text.hasPrefix("Them: "))

        let replies = SampleConversation.exampleReplies
        XCTAssertEqual(replies.count, 3)
        XCTAssertEqual(Set(replies.map(\.style)).count, 3, "Three different approaches, as a real result has")
        for reply in replies {
            XCTAssertFalse(reply.text.isEmpty)
            XCTAssertFalse(reply.why.isEmpty, "Each example reply explains why it could work")
        }
    }
}
