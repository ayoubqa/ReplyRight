import XCTest
@testable import ReplyRightCore

/// Profiles: what is stored, what is allowed to leave the device, and how it is removed.
final class ProfileTests: XCTestCase {
    private func fullProfile() -> CrushProfile {
        CrushProfile(
            alias: "Sam",
            stage: .beenOnDates,
            notes: "felt nervous before the second date",
            metAt: "climbing gym",
            language: "es",
            interests: ["climbing", "ramen"],
            background: "from Valencia, works in film",
            preferences: "voice notes over texts",
            details: "exam on Friday",
            summaries: [CrushProfile.Summary(text: "planned a ramen night")]
        )
    }

    func testANewProfileSharesWhatWasWrittenButNotPrivateNotes() throws {
        let payload = try XCTUnwrap(fullProfile().payload)
        XCTAssertEqual(payload.alias, "Sam")
        XCTAssertEqual(payload.stage, .beenOnDates)
        XCTAssertEqual(payload.metAt, "climbing gym")
        XCTAssertEqual(payload.language, "Spanish")
        XCTAssertEqual(payload.interests, ["climbing", "ramen"])
        XCTAssertEqual(payload.background, "from Valencia, works in film")
        XCTAssertEqual(payload.preferences, "voice notes over texts")
        XCTAssertEqual(payload.details, "exam on Friday")
        XCTAssertEqual(payload.history, "planned a ramen night")
        XCTAssertEqual(payload.notes, "", "Notes are private unless the user switches them on")
    }

    func testEachSwitchRemovesItsPartOfThePayload() throws {
        var profile = fullProfile()
        profile.sharing = .nothing
        var payload = try XCTUnwrap(profile.payload)
        XCTAssertEqual(payload, CrushPayload(alias: "Sam", stage: .beenOnDates), "Only the name and where things stand")
        XCTAssertEqual(profile.sharedFieldNames, ["Name", "Where things stand"])

        profile.sharing.interests = true
        payload = try XCTUnwrap(profile.payload)
        XCTAssertEqual(payload.interests, ["climbing", "ramen"])
        XCTAssertEqual(payload.background, "")
        XCTAssertEqual(payload.metAt, "")

        profile.sharing.notes = true
        XCTAssertEqual(profile.payload?.notes, "felt nervous before the second date")
        XCTAssertEqual(profile.sharedFieldNames, ["Name", "Where things stand", "Interests", "Private notes"])
    }

    func testThePayloadNeverCarriesThePhotoOrIdentifiers() throws {
        var profile = fullProfile()
        profile.hasPhoto = true
        let data = try JSONEncoder().encode(XCTUnwrap(profile.payload))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            Set(object.keys),
            ["alias", "stage", "notes", "metAt", "language", "interests", "background", "preferences", "details", "history"]
        )
    }

    func testInterestsAreCleanedAndCapped() {
        var profile = CrushProfile(alias: "Sam")
        profile.interests = ["  Climbing ", "climbing", "", "Ramen"] + (1...20).map { "thing \($0)" }
        XCTAssertEqual(profile.cleanInterests.prefix(2), ["Climbing", "Ramen"])
        XCTAssertEqual(profile.cleanInterests.count, CrushProfile.maxInterests)
        profile.interests = [String(repeating: "x", count: 90)]
        XCTAssertEqual(profile.cleanInterests.first?.count, CrushProfile.maxInterestLength)
    }

    func testSummariesAreNewestFirstAndCapped() {
        var profile = CrushProfile(alias: "Sam")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<(CrushProfile.maxSummaries + 5) {
            profile.addSummary("talk \(index)", date: start.addingTimeInterval(Double(index) * 60))
        }
        XCTAssertEqual(profile.summaries.count, CrushProfile.maxSummaries)
        XCTAssertEqual(profile.summaries.first?.text, "talk \(CrushProfile.maxSummaries + 4)")
        XCTAssertTrue(profile.historyText.hasPrefix("talk \(CrushProfile.maxSummaries + 4)"))
        XCTAssertLessThanOrEqual(profile.historyText.count, CrushProfile.maxHistoryLength)

        profile.addSummary("   ")
        XCTAssertEqual(profile.summaries.count, CrushProfile.maxSummaries, "An empty summary is not kept")
    }

    func testAProfileSavedByTheFirstVersionKeepsWorking() throws {
        let old = #"{"id":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","alias":"Sam","stage":"talking","notes":"loves climbing","createdAt":700000000}"#
        let profile = try JSONDecoder().decode(CrushProfile.self, from: Data(old.utf8))
        XCTAssertEqual(profile.alias, "Sam")
        XCTAssertEqual(profile.interests, [])
        XCTAssertFalse(profile.hasPhoto)
        XCTAssertTrue(profile.sharing.notes, "Notes were the shared context in that version, so they stay shared")
        XCTAssertEqual(profile.payload?.notes, "loves climbing")
        XCTAssertEqual(profile.updatedAt, profile.createdAt)
    }

    func testKeyboardContextFromTheFirstVersionStillDecodes() throws {
        let old = #"{"text":"Them: hi","source":"app","createdAt":700000000,"crush":{"alias":"Sam","stage":"talking","notes":"n"}}"#
        let context = try JSONDecoder().decode(KeyboardContext.self, from: Data(old.utf8))
        XCTAssertEqual(context.crush?.alias, "Sam")
        XCTAssertEqual(context.crush?.interests, [])
        XCTAssertNil(context.crushID)
    }

    func testSubtitleAndInitial() {
        XCTAssertEqual(CrushProfile(alias: "sam", metAt: " a wedding ").subtitle, "A wedding, talking for a while")
        XCTAssertEqual(CrushProfile(alias: "sam").subtitle, "Talking for a while")
        XCTAssertEqual(CrushProfile(alias: "  ").initial, "?")
    }
}

/// Profile storage: photos, export and permanent deletion.
final class ProfileStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SharedStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("replyright-profile-tests-\(UUID().uuidString)", isDirectory: true)
        store = SharedStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func seed() -> (sam: CrushProfile, alex: CrushProfile) {
        var sam = CrushProfile(alias: "Sam", interests: ["ramen"])
        sam.hasPhoto = true
        let alex = CrushProfile(alias: "Alex")
        store.savePeople([sam, alex])
        store.savePersonPhoto(Data([0xFF, 0xD8, 0x01]), for: sam.id)
        store.saveSavedReplies([
            SavedReply(text: "for sam", style: "Playful", crushID: sam.id),
            SavedReply(text: "for alex", style: "Warm", crushID: alex.id),
            SavedReply(text: "for no one", style: "Natural"),
        ])
        store.saveSessions([
            SavedSession(title: "sam chat", conversation: "c", read: "r", intent: .natural, instruction: "", options: [], crushID: sam.id),
            SavedSession(title: "other chat", conversation: "c", read: "r", intent: .natural, instruction: "", options: [], crushID: nil),
        ])
        store.saveKeyboardContext(KeyboardContext(text: "Them: hi", source: .app, crush: sam.payload, crushID: sam.id))
        var settings = AppSettings()
        settings.lastCrushID = sam.id
        settings.keyboardCrushID = sam.id
        store.saveSettings(settings)
        return (sam, alex)
    }

    func testPhotosAreStoredPerPerson() {
        let people = seed()
        XCTAssertEqual(store.loadPersonPhoto(people.sam.id), Data([0xFF, 0xD8, 0x01]))
        XCTAssertNil(store.loadPersonPhoto(people.alex.id))
        store.deletePersonPhoto(people.sam.id)
        XCTAssertNil(store.loadPersonPhoto(people.sam.id))
    }

    func testExportHoldsEverythingAboutOnePersonAndNothingAboutAnyoneElse() throws {
        let people = seed()
        let data = try XCTUnwrap(store.exportPerson(people.sam.id))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("for sam"))
        XCTAssertTrue(text.contains("sam chat"))
        XCTAssertTrue(text.contains("ramen"))
        XCTAssertFalse(text.contains("for alex"))
        XCTAssertFalse(text.contains("for no one"))
        XCTAssertFalse(text.contains("other chat"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(ProfileExport.self, from: data)
        XCTAssertEqual(export.profile.alias, "Sam")
        XCTAssertEqual(export.savedReplies.count, 1)
        XCTAssertEqual(export.conversations.count, 1)
        XCTAssertEqual(export.photoJPEGBase64, Data([0xFF, 0xD8, 0x01]).base64EncodedString())

        XCTAssertNil(store.exportPerson(UUID()), "There is nothing to export for someone who is not in the notebook")
    }

    func testDeletingAPersonRemovesEverythingAttachedToThem() {
        let people = seed()
        store.deletePerson(people.sam.id)

        XCTAssertEqual(store.loadPeople().map(\.alias), ["Alex"])
        XCTAssertNil(store.loadPersonPhoto(people.sam.id))
        XCTAssertEqual(store.loadSavedReplies().map(\.text), ["for alex", "for no one"])
        XCTAssertEqual(store.loadSessions().map(\.title), ["other chat"])
        XCTAssertNil(store.loadKeyboardContext(), "Context about them that was handed to the keyboard goes too")
        XCTAssertNil(store.loadSettings().lastCrushID)
        XCTAssertNil(store.loadSettings().keyboardCrushID)
    }

    func testDeletingOnePersonLeavesContextAboutAnotherAlone() {
        let people = seed()
        store.saveKeyboardContext(KeyboardContext(text: "Them: hey", source: .app, crush: people.alex.payload, crushID: people.alex.id))
        store.deletePerson(people.sam.id)
        XCTAssertEqual(store.loadKeyboardContext()?.crushID, people.alex.id)
    }

    func testErasingPeopleAlsoRemovesTheirPhotos() {
        let people = seed()
        store.erase(.people)
        XCTAssertTrue(store.loadPeople().isEmpty)
        XCTAssertNil(store.loadPersonPhoto(people.sam.id))
    }
}

/// Which server a build talks to, and what the app says about the connection.
final class ConnectionTests: XCTestCase {
    private let plans = #"{"free":{"dailyGenerations":10,"dailyCoachMessages":3,"intents":["natural"],"voiceSamples":false},"pro":{"dailyGenerations":400,"dailyCoachMessages":200,"intents":["natural"],"voiceSamples":true}}"#
    private let usage = #"{"tier":"free","generations":{"used":1,"limit":10,"remaining":9},"coach":{"used":0,"limit":3,"remaining":3},"resetsAt":"2026-11-11T00:00:00.000Z"}"#

    private func status(mode: String, extra: String = "") throws -> StatusResponse {
        let json = #"{"apiVersion":2,"mode":"\#(mode)","provider":"p","supportsImages":true,"plans":\#(plans),"usage":\#(usage)\#(extra)}"#
        return try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
    }

    func testAddressesMustBeCompleteHTTPAddresses() {
        XCTAssertNotNil(AppConfig.parseURL("https://api.example.com"))
        XCTAssertNotNil(AppConfig.parseURL("  http://192.168.1.20:3000 "))
        XCTAssertNil(AppConfig.parseURL("https://"), "An environment with no host is not configured")
        XCTAssertNil(AppConfig.parseURL("api.example.com"))
        XCTAssertNil(AppConfig.parseURL("ftp://example.com"))
        XCTAssertNil(AppConfig.parseURL(nil))
        XCTAssertNil(AppConfig.parseURL(""))
    }

    func testAnEnvironmentWithoutAnAddressFallsBackToTheBuild() {
        // The test bundle carries no addresses, so staging and production are not configured.
        let target = AppConfig.backend(environment: "staging", customURL: nil, allowSwitching: true)
        XCTAssertEqual(target.url, AppConfig.defaultAPIBaseURL)
        XCTAssertEqual(target.source, .build)

        let custom = AppConfig.backend(environment: "staging", customURL: "https://staging.example.com", allowSwitching: true)
        XCTAssertEqual(custom.source, .custom)
        XCTAssertNil(custom.environment)
        XCTAssertEqual(custom.url.host, "staging.example.com")
    }

    func testDemoModeIsNeverMistakenForLiveAI() throws {
        let demo = ConnectionState(status: try status(mode: "demo"))
        XCTAssertEqual(demo, .demo)
        XCTAssertTrue(demo.isDemo)
        XCTAssertEqual(demo.title, "Demo mode")
        XCTAssertTrue(demo.summary.contains("sample"))
        XCTAssertFalse(demo.isProblem)
        XCTAssertTrue(demo.canAnswer)
    }

    func testLiveModeReportsTheModelAndWhetherItIsAnswering() throws {
        let healthy = try status(
            mode: "live",
            extra: #","environment":"staging","ai":{"state":"ok","lastFailureReason":null,"models":{"analyze":"m-small","replies":"m-large"}}"#
        )
        XCTAssertEqual(healthy.environment, "staging")
        XCTAssertEqual(ConnectionState(status: healthy), .live(model: "m-large"))

        let failing = try status(mode: "live", extra: #","ai":{"state":"failing","lastFailureReason":"credentials","models":null}"#)
        let state = ConnectionState(status: failing)
        XCTAssertEqual(state, .liveFailing(reason: "credentials"))
        XCTAssertTrue(state.isProblem)
        XCTAssertTrue(state.summary.contains("ANTHROPIC_API_KEY"))

        let older = ConnectionState(status: try status(mode: "live"))
        XCTAssertEqual(older, .live(model: nil), "A server that says nothing about health is taken at its word")
    }

    func testAnUnreachableServerSaysSoPlainly() {
        let state = ConnectionState.unreachable(.serverUnreachable(.refused))
        XCTAssertEqual(state.title, "Can't reach ReplyRight")
        XCTAssertFalse(state.canAnswer)
        XCTAssertTrue(state.isProblem)
        XCTAssertEqual(ConnectionState.unreachable(.offline).title, "You're offline")
    }

    func testEveryFailureReasonHasAnExplanation() {
        for reason in ["credentials", "billing", "model", "request", "overloaded", "timeout", "network", "rate_limit", "not_configured", nil, "something-new"] {
            XCTAssertFalse(ServerFailure.explain(reason).isEmpty)
        }
        XCTAssertFalse(ServerFailure.explain("credentials").contains("sk-"), "Explanations name the setting, never a key")
    }
}

/// The coach's three modes on the wire.
final class CoachContractTests: XCTestCase {
    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testAQuestionIsSentInAskMode() throws {
        let object = try jsonObject(CoachRequest(topic: .askingOut, messages: [CoachTurn(role: .user, text: "too soon?")]))
        XCTAssertEqual(object["mode"] as? String, "ask")
        XCTAssertEqual(object["topic"] as? String, "asking_out")
        XCTAssertNil(object["scenario"])
        XCTAssertEqual((object["messages"] as? [[String: Any]])?.count, 1)
    }

    func testAReviewCarriesTheDraftAndTheGoal() throws {
        let request = CoachRequest(mode: .review, draft: "  hey you  ", goal: String(repeating: "g", count: 400))
        let object = try jsonObject(request)
        XCTAssertEqual(object["mode"] as? String, "review")
        XCTAssertEqual(object["draft"] as? String, "hey you")
        XCTAssertEqual((object["goal"] as? String)?.count, RequestLimits.instructionChars)
        XCTAssertEqual((object["messages"] as? [Any])?.count, 0)
    }

    func testPracticeMayOpenWithTheOtherPersonAndNeverCarriesAProfile() throws {
        let turns = [CoachTurn(role: .coach, text: "hey! how was the gig?"), CoachTurn(role: .user, text: "loud. in a good way")]
        let request = CoachRequest(mode: .practice, messages: turns, scenario: PracticeSetup(id: .keepItGoing))
        XCTAssertEqual(request.messages.map(\.role), [.coach, .user], "A rehearsal keeps the other person's opening line")
        let object = try jsonObject(request)
        XCTAssertEqual((object["scenario"] as? [String: Any])?["id"] as? String, "keep_it_going")
        XCTAssertNil(object["crush"])

        let outsidePractice = CoachRequest(mode: .ask, messages: turns, scenario: PracticeSetup(id: .keepItGoing))
        XCTAssertNil(outsidePractice.scenario, "A scenario is only sent in practice mode")
        XCTAssertEqual(outsidePractice.messages.first?.role, .user)
    }

    func testAReviewResultDecodesWithAllSixParts() throws {
        let json = #"""
        {"message":"Good start.","suggestions":[],"followUps":["Is it too long?"],"lesson":"Say one thing.","headsUp":null,"practice":null,
         "review":{"intent":"Show interest.","comesAcross":"Reads as keen.","improvements":["Drop one exclamation mark."],
                   "alternative":"had a great time last night","whyItWorks":"Calmer.","lesson":"Say one thing.",
                   "checks":[{"aspect":"natural","verdict":"good","note":"Sounds like you."},
                             {"aspect":"intensity","verdict":"rework","note":"Three exclamation marks."},
                             {"aspect":"mystery","verdict":"sideways","note":"A newer server."}]}}
        """#
        let result = try JSONDecoder().decode(CoachResult.self, from: Data(json.utf8))
        let review = try XCTUnwrap(result.review)
        XCTAssertEqual(review.intent, "Show interest.")
        XCTAssertEqual(review.comesAcross, "Reads as keen.")
        XCTAssertEqual(review.improvements, ["Drop one exclamation mark."])
        XCTAssertEqual(review.alternative, "had a great time last night")
        XCTAssertEqual(review.whyItWorks, "Calmer.")
        XCTAssertEqual(review.lesson, "Say one thing.")
        XCTAssertNil(result.practice)

        XCTAssertEqual(review.checks[0].level, .good)
        XCTAssertEqual(review.checks[0].question, "Does it sound natural?")
        XCTAssertEqual(review.checks[0].answer, "Yes")
        XCTAssertEqual(review.checks[1].answer, "Yes", "Too intense: yes")
        XCTAssertEqual(review.checks[1].level, .rework)
        XCTAssertEqual(review.checks[2].level, .watch, "An unknown verdict is shown as worth a look, not as a failure to decode")
        XCTAssertFalse(review.checks[2].question.isEmpty)
    }

    func testAPracticeResultAndAnOlderServerBothDecode() throws {
        let practice = #"{"message":"","suggestions":[],"followUps":[],"lesson":null,"review":null,"headsUp":null,"practice":{"partnerReply":"haha ok fair","feedback":"Good: you asked something easy.","tryThis":null,"finished":false}}"#
        let result = try JSONDecoder().decode(CoachResult.self, from: Data(practice.utf8))
        XCTAssertEqual(result.practice?.partnerReply, "haha ok fair")
        XCTAssertEqual(result.practice?.finished, false)
        XCTAssertNil(result.review)

        let older = #"{"message":"Send it.","suggestions":[{"label":"Short","text":"see you at 8"}],"followUps":[],"headsUp":null}"#
        let old = try JSONDecoder().decode(CoachResult.self, from: Data(older.utf8))
        XCTAssertEqual(old.message, "Send it.")
        XCTAssertEqual(old.suggestions.first?.text, "see you at 8")
        XCTAssertNil(old.lesson)
        XCTAssertNil(old.review)
        XCTAssertNil(old.practice)
    }

    func testAdjustmentsOfferedOnAReply() {
        XCTAssertEqual(
            RefineAction.cardActions.prefix(9).map(\.tweakTitle),
            ["More natural", "More playful", "More confident", "More romantic", "Less intense", "Shorter", "More direct", "Ask a question", "Keep it going"]
        )
        XCTAssertTrue(Set(RefineAction.keyboardActions).isSubset(of: Set(RefineAction.allCases)))
    }

    func testTheKeyboardLanguageSwitchCyclesThroughEveryLanguage() {
        var language = KeyboardLanguage.english
        var seen: [KeyboardLanguage] = []
        for _ in KeyboardLanguage.allCases {
            seen.append(language)
            language = language.next
        }
        XCTAssertEqual(Set(seen), Set(KeyboardLanguage.allCases))
        XCTAssertEqual(language, .english, "The switch comes back round")
        XCTAssertEqual(KeyboardLanguage.spanish.shortCode, "ES")
    }
}
