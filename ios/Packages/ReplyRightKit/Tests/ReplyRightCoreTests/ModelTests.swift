import XCTest
@testable import ReplyRightCore

private func jsonObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

final class VoiceProfileTests: XCTestCase {
    func testPayloadClampsAndFiltersWhatIsSent() {
        var voice = VoiceProfile()
        voice.writingStyle = String(repeating: "a", count: 400)
        voice.aboutMe = "  climbs, cooks  "
        voice.personality = [.funny, .shy, .confident, .romantic, .reserved]
        voice.replyLanguage = "klingon"
        voice.languages = ["en", "xx", "match", "es"]
        voice.samples = (1...10).map { VoiceProfile.Sample(text: "message \($0)") } + [VoiceProfile.Sample(text: "   ")]

        let payload = voice.payload
        XCTAssertEqual(payload.writingStyle.count, VoiceProfile.maxNoteLength)
        XCTAssertEqual(payload.aboutMe, "climbs, cooks")
        XCTAssertEqual(payload.personality.count, 3)
        XCTAssertEqual(payload.replyLanguage, "match", "Unknown languages fall back to matching the conversation")
        XCTAssertEqual(payload.languages, ["en", "es"])
        XCTAssertEqual(payload.samples.count, VoiceProfile.maxSamples)
        XCTAssertEqual(payload.samples.first, "message 1")
    }

    func testDecodingToleratesMissingAndInvalidFields() throws {
        let partial = Data(#"{"defaultTone":"confident","emoji":"none","somethingNew":true}"#.utf8)
        let voice = try JSONDecoder().decode(VoiceProfile.self, from: partial)
        XCTAssertEqual(voice.defaultTone, .confident)
        XCTAssertEqual(voice.emoji, .none)
        XCTAssertEqual(voice.length, .short, "Missing fields take their defaults")
        XCTAssertEqual(voice.languages, ["en"])

        let invalid = Data(#"{"defaultTone":"sassy","humour":42}"#.utf8)
        let recovered = try JSONDecoder().decode(VoiceProfile.self, from: invalid)
        XCTAssertEqual(recovered.defaultTone, .playful)
        XCTAssertEqual(recovered.humour, .light)
    }

    func testRoundTrip() throws {
        var voice = VoiceProfile(defaultTone: .warm, personality: [.shy], humour: .dry, emoji: .often, replyLanguage: "es", languages: ["es", "en"])
        voice.addSample("jajaja no puede ser", source: .added, now: Date(timeIntervalSince1970: 1_700_000_000))
        voice.goals = [.askOut, .reply]
        let decoded = try JSONDecoder().decode(VoiceProfile.self, from: JSONEncoder().encode(voice))
        XCTAssertEqual(decoded, voice)
    }

    func testAddSampleDeduplicatesAndPutsNewestFirst() {
        var voice = VoiceProfile()
        voice.addSample("lol ok fair", source: .added)
        voice.addSample("wait that's so funny", source: .added)
        voice.addSample("LOL OK FAIR", source: .added)
        XCTAssertEqual(voice.samples.map(\.text), ["LOL OK FAIR", "wait that's so funny"])

        voice.addSample("    ", source: .added)
        XCTAssertEqual(voice.samples.count, 2, "Blank samples are ignored")

        voice.addSample(String(repeating: "x", count: 400), source: .added)
        XCTAssertEqual(voice.samples.first?.text.count, VoiceProfile.maxSampleLength)
    }

    func testSamplesAreCappedAndLearnedOnesAreEvictedFirst() {
        var voice = VoiceProfile()
        voice.addSample("learned from an edit", source: .learned)
        for index in 1...7 {
            voice.addSample("typed by hand \(index)", source: .added)
        }
        XCTAssertEqual(voice.samples.count, 8)

        voice.addSample("one more by hand", source: .added)
        XCTAssertEqual(voice.samples.count, VoiceProfile.maxSamples)
        XCTAssertFalse(voice.samples.contains { $0.source == .learned }, "Samples the user typed are kept over learned ones")
        XCTAssertEqual(voice.samples.first?.text, "one more by hand")
    }

    func testPayloadUsesTheBackendKeyNames() throws {
        let object = try jsonObject(VoiceProfile(defaultTone: .subtle).payload)
        XCTAssertEqual(object["defaultTone"] as? String, "subtle")
        for key in ["personality", "humour", "emoji", "length", "vocabulary", "directness", "romance", "replyLanguage", "languages", "writingStyle", "aboutMe", "samples"] {
            XCTAssertNotNil(object[key], "missing \(key)")
        }
        XCTAssertNil(object["goals"], "Goals stay on the device")
    }

    func testReplyLanguages() {
        XCTAssertTrue(ReplyLanguage.isSupported("match"))
        XCTAssertTrue(ReplyLanguage.isSupported("es"))
        XCTAssertFalse(ReplyLanguage.isSupported("xx"))
        XCTAssertEqual(ReplyLanguage.available.map(\.id), ["en", "es"])
        XCTAssertEqual(ReplyLanguage.name(for: "match"), "Match the conversation")
        XCTAssertEqual(ReplyLanguage.name(for: "es"), "Spanish")
    }
}

final class RequestTests: XCTestCase {
    func testConversationKeepsTheMostRecentPart() {
        let long = "START\n" + String(repeating: "x", count: 7000) + "\nEND"
        let request = RepliesRequest(conversation: long)
        XCTAssertLessThanOrEqual(request.conversation.count, RequestLimits.conversationChars)
        XCTAssertTrue(request.conversation.hasSuffix("END"))
        XCTAssertFalse(request.conversation.contains("START"))
    }

    func testTranscriptIsCleanedAndCapped() {
        var lines = (1...100).map { TranscriptLine(speaker: .them, text: "line \($0)") }
        lines.append(TranscriptLine(speaker: .me, text: "   "))
        lines.append(TranscriptLine(speaker: .me, text: String(repeating: "y", count: 1500)))
        let request = RepliesRequest(transcript: lines)

        XCTAssertEqual(request.transcript.count, RequestLimits.transcriptLines)
        XCTAssertEqual(request.transcript.last?.text.count, RequestLimits.transcriptLineChars)
        XCTAssertFalse(request.transcript.contains { $0.text.isEmpty })
        XCTAssertEqual(request.transcript.first?.text, "line 22", "The oldest lines are dropped first")
    }

    func testFieldsAreClippedToServerLimits() {
        let request = RepliesRequest(
            situation: String(repeating: "s", count: 900),
            instruction: String(repeating: "i", count: 300),
            draft: String(repeating: "d", count: 1200),
            avoid: (1...12).map { "option \($0)" }
        )
        XCTAssertEqual(request.situation.count, RequestLimits.situationChars)
        XCTAssertEqual(request.instruction.count, RequestLimits.instructionChars)
        XCTAssertEqual(request.draft.count, RequestLimits.draftChars)
        XCTAssertEqual(request.avoid.count, RequestLimits.avoidReplies)
        XCTAssertEqual(request.avoid.last, "option 12")
    }

    func testRefineCountIsOneOrThree() {
        XCTAssertEqual(RefineRequest(text: "hey", action: .shorter).count, 1)
        XCTAssertEqual(RefineRequest(text: "hey", action: .shorter, count: 2).count, 1)
        XCTAssertEqual(RefineRequest(text: "hey", action: .shorter, count: 3).count, 3)
    }

    func testCoachRequestStartsWithAUserTurnAndIsCapped() {
        let turns = [
            CoachTurn(role: .coach, text: "earlier answer"),
            CoachTurn(role: .user, text: "first question"),
            CoachTurn(role: .coach, text: "answer"),
            CoachTurn(role: .user, text: "  "),
            CoachTurn(role: .user, text: "second question"),
        ]
        let request = CoachRequest(messages: turns)
        XCTAssertEqual(request.messages.first?.role, .user)
        XCTAssertEqual(request.messages.map(\.text), ["first question", "answer", "second question"])

        let many = (1...40).map { CoachTurn(role: $0 % 2 == 1 ? .user : .coach, text: "turn \($0)") }
        let capped = CoachRequest(messages: many)
        XCTAssertLessThanOrEqual(capped.messages.count, RequestLimits.coachMessages)
        XCTAssertEqual(capped.messages.first?.role, .user)
        XCTAssertEqual(capped.messages.last?.text, "turn 40")
    }

    func testRepliesRequestJSONMatchesTheBackendContract() throws {
        let request = RepliesRequest(
            kind: .starter,
            transcript: [TranscriptLine(speaker: .them, text: "hi")],
            intent: .keepGoing,
            crush: CrushProfile(alias: " Sam ", stage: .beenOnDates, notes: "loves climbing").payload
        )
        let object = try jsonObject(request)
        XCTAssertEqual(object["kind"] as? String, "starter")
        XCTAssertEqual(object["intent"] as? String, "keep_going")
        XCTAssertEqual(object["locale"] as? String, "en")
        XCTAssertNil(object["voice"], "Optional context is left out, not sent as null")

        let crush = try XCTUnwrap(object["crush"] as? [String: Any])
        XCTAssertEqual(crush["alias"] as? String, "Sam")
        XCTAssertEqual(crush["stage"] as? String, "been_on_dates")

        let line = try XCTUnwrap((object["transcript"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(line.keys), ["speaker", "text"], "The local id is not part of the wire format")
        XCTAssertEqual(line["speaker"] as? String, "them")
    }

    func testEnumRawValuesMatchTheBackend() throws {
        XCTAssertEqual(try jsonObject(RefineRequest(text: "hey", action: .moreLikeMe))["action"] as? String, "more_like_me")
        XCTAssertEqual(Intent.allCases.map(\.rawValue), [
            "natural", "flirt", "laugh", "interest", "confident", "keep_going",
            "mysterious", "charming", "ask_out", "dry_reply", "feelings", "boundary",
        ])
        XCTAssertEqual(RefineAction.allCases.map(\.rawValue), [
            "shorter", "funnier", "more_romantic", "more_confident", "less_intense", "more_natural",
            "more_like_me", "flirty", "playful", "charming", "subtle", "warm",
            "more_direct", "ask_question", "keep_going",
        ])
        XCTAssertEqual(CoachMode.allCases.map(\.rawValue), ["ask", "review", "practice"])
        XCTAssertEqual(CoachTopic.allCases.map(\.rawValue), ["general", "flirting", "conversation", "asking_out", "confidence"])
        XCTAssertEqual(PracticeScenario.allCases.map(\.rawValue), [
            "first_message", "keep_it_going", "flirting", "asking_out", "reconnecting", "boundary", "custom",
        ])
        XCTAssertEqual(CrushProfile.Stage.allCases.map(\.rawValue), [
            "new_match", "talking", "been_on_dates", "seeing_each_other", "reconnecting",
        ])
        XCTAssertEqual(Set(Intent.selectorOrder), Set(Intent.allCases), "Every intent appears in the selector")
    }

    func testCrushPayloadNeedsANickname() {
        XCTAssertNil(CrushProfile(alias: "   ").payload)
        XCTAssertEqual(CrushProfile(alias: "Sam").payload?.alias, "Sam")
        XCTAssertEqual(CrushProfile(alias: String(repeating: "n", count: 80)).payload?.alias.count, CrushProfile.maxAliasLength)
        XCTAssertEqual(CrushProfile(alias: "sam").initial, "S")
    }
}

final class DecodingTests: XCTestCase {
    private let usageJSON = #"{"tier":"free","generations":{"used":1,"limit":10,"remaining":9},"coach":{"used":0,"limit":3,"remaining":3},"resetsAt":"2026-11-11T00:00:00.000Z"}"#

    func testRepliesEnvelopeFromTheServer() throws {
        let json = #"{"mode":"demo","provider":"demo","model":null,"usage":\#(usageJSON),"result":{"note":"Okay, this is a good one.","replies":[{"style":"Most natural","text":"haha fair","why":"Easy to answer."}],"headsUp":null}}"#
        let envelope = try JSONDecoder().decode(Envelope<RepliesResult>.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.mode, .demo)
        XCTAssertNil(envelope.model)
        XCTAssertEqual(envelope.usage.generations.remaining, 9)
        XCTAssertEqual(envelope.result.replies, [Suggestion(style: "Most natural", text: "haha fair", why: "Easy to answer.")])
        XCTAssertNil(envelope.result.headsUp)
    }

    func testAnalysisSkipsUnknownIntentsAndDefaultsMissingFields() throws {
        let json = #"{"canReply":true,"read":"They're teasing you.","transcript":[{"speaker":"them","text":"ok bold"}],"suggestedIntents":["laugh","teleport","flirt"]}"#
        let analysis = try JSONDecoder().decode(Analysis.self, from: Data(json.utf8))
        XCTAssertEqual(analysis.suggestedIntents, [.laugh, .flirt])
        XCTAssertEqual(analysis.transcript.first?.speaker, .them)
        XCTAssertEqual(analysis.observations, [])
        XCTAssertFalse(analysis.latestFromMe)
        XCTAssertNil(analysis.latestMessage)
    }

    func testAnalysisSaysWhetherTheScreenshotCouldBeRead() throws {
        let unreadable = #"{"canReply":false,"read":"Too blurry to read.","transcript":[],"problem":"unreadable"}"#
        let analysis = try JSONDecoder().decode(Analysis.self, from: Data(unreadable.utf8))
        XCTAssertEqual(analysis.problem, .unreadable)
        XCTAssertTrue(analysis.problem.asksForBetterInput)
        XCTAssertTrue(analysis.problem.cannotReplyMessage.contains("paste"))

        let older = #"{"canReply":true,"read":"ok"}"#
        XCTAssertEqual(try JSONDecoder().decode(Analysis.self, from: Data(older.utf8)).problem, AnalysisProblem.none, "Older servers send no problem")

        let newer = #"{"canReply":true,"read":"ok","problem":"something_new"}"#
        XCTAssertEqual(try JSONDecoder().decode(Analysis.self, from: Data(newer.utf8)).problem, AnalysisProblem.none)

        XCTAssertEqual(AnalysisProblem.notAConversation.rawValue, "not_a_conversation")
        XCTAssertEqual(AnalysisProblem.partlyReadable.rawValue, "partly_readable")
    }

    func testStatusResponse() throws {
        let json = #"{"apiVersion":1,"mode":"live","provider":"anthropic","supportsImages":true,"plans":{"free":{"dailyGenerations":10,"dailyCoachMessages":3,"intents":["natural","flirt"],"voiceSamples":false},"pro":{"dailyGenerations":400,"dailyCoachMessages":200,"intents":["natural","flirt","ask_out"],"voiceSamples":true}},"usage":\#(usageJSON),"extraField":[1,2,3]}"#
        let status = try JSONDecoder().decode(StatusResponse.self, from: Data(json.utf8))
        XCTAssertEqual(status.mode, .live)
        XCTAssertTrue(status.plans.plan(for: .pro).includes(.askOut))
        XCTAssertFalse(status.plans.plan(for: .free).includes(.askOut))
    }

    func testUsageResetDateAcceptsBothTimestampForms() throws {
        let usage = try JSONDecoder().decode(Usage.self, from: Data(usageJSON.utf8))
        XCTAssertEqual(usage.resetDate, Date(timeIntervalSince1970: 1_794_355_200))

        var plain = usage
        plain.resetsAt = "2026-11-11T00:00:00Z"
        XCTAssertEqual(plain.resetDate, Date(timeIntervalSince1970: 1_794_355_200))

        plain.resetsAt = "not a date"
        XCTAssertNil(plain.resetDate)
    }

    func testFallbackPlansMatchTheServerDefaults() {
        let plans = PlanCatalog.fallback
        XCTAssertEqual(plans.free.dailyGenerations, 10)
        XCTAssertTrue(plans.free.includes(.boundary), "Setting a boundary is never behind the paywall")
        XCTAssertFalse(plans.free.includes(.askOut))
        XCTAssertFalse(plans.free.voiceSamples)
        for intent in Intent.allCases {
            XCTAssertTrue(plans.pro.includes(intent))
        }
    }
}

final class ConversationTests: XCTestCase {
    func testReplyOptionTracksEditsAndUndo() {
        var option = ReplyOption(suggestion: Suggestion(style: "Playful", text: "bold of you", why: "Teases gently."))
        XCTAssertFalse(option.isEdited)

        option.text = "bold of you honestly"
        XCTAssertTrue(option.isEdited)

        option.apply(Suggestion(style: "Shorter", text: "bold", why: "Trimmed."))
        XCTAssertEqual(option.text, "bold")
        XCTAssertEqual(option.style, "Shorter")
        XCTAssertFalse(option.isEdited, "A refined version becomes the new baseline")

        XCTAssertTrue(option.undo())
        XCTAssertEqual(option.text, "bold of you honestly", "Undo returns to what was on screen before the tweak")
        XCTAssertFalse(option.undo(), "Nothing left to undo")
    }

    func testRenderLabelsSpeakers() {
        let transcript = [
            TranscriptLine(speaker: .them, text: "beach or mountains?"),
            TranscriptLine(speaker: .me, text: "mountains"),
            TranscriptLine(speaker: .unknown, text: "ok bold"),
        ]
        XCTAssertEqual(ConversationText.render(transcript), "Them: beach or mountains?\nMe: mountains\nok bold")
    }

    func testSpeakerCyclesWhenCorrected() {
        XCTAssertEqual(Speaker.them.next, .me)
        XCTAssertEqual(Speaker.me.next, .unknown)
        XCTAssertEqual(Speaker.unknown.next, .them)
    }

    func testClampRecentPrefersALineBreak() {
        XCTAssertEqual(ConversationText.clampRecent("  short  ", limit: 100), "short")
        let text = "aaaa\nbbbbbbbbbb\ncccccccccc\ndddddddddd"
        let clamped = ConversationText.clampRecent(text, limit: 24)
        XCTAssertEqual(clamped, "cccccccccc\ndddddddddd", "A partial first line is dropped when the break is near the start")
    }

    func testSessionTitle() {
        XCTAssertEqual(ConversationText.title(latestMessage: "are we still on?", fallback: "x"), "are we still on?")
        XCTAssertEqual(ConversationText.title(latestMessage: nil, fallback: "Them: hi\nMe: hey"), "Them: hi")
        let long = ConversationText.title(latestMessage: String(repeating: "w", count: 90), fallback: "")
        XCTAssertEqual(long.count, 60)
        XCTAssertTrue(long.hasSuffix("..."))
    }

    func testTranscriptLinesAreEqualByContentOnDecode() throws {
        let data = Data(#"[{"speaker":"me","text":"hey"}]"#.utf8)
        let lines = try JSONDecoder().decode([TranscriptLine].self, from: data)
        XCTAssertEqual(lines.first?.speaker, .me)
        XCTAssertEqual(lines.first?.text, "hey")
    }
}

final class SupportTests: XCTestCase {
    func testMicrocopyPickIsStableAndSafe() {
        let lines = ["a", "b", "c"]
        XCTAssertEqual(Microcopy.pick(lines, seed: 0), "a")
        XCTAssertEqual(Microcopy.pick(lines, seed: 4), "b")
        XCTAssertEqual(Microcopy.pick(lines, seed: -1), "c")
        XCTAssertEqual(Microcopy.pick([], seed: 3), "")
    }

    func testAllowanceWording() {
        XCTAssertEqual(Microcopy.allowance(remaining: 5, isPro: false), "5 replies left today")
        XCTAssertEqual(Microcopy.allowance(remaining: 1, isPro: false), "1 reply left today")
        XCTAssertEqual(Microcopy.allowance(remaining: 0, isPro: false), "Back tomorrow")
        XCTAssertEqual(Microcopy.allowance(remaining: 0, isPro: true), "Pro")
    }

    func testGreetingByHour() {
        XCTAssertEqual(Microcopy.greeting(hour: 8), "Good morning")
        XCTAssertEqual(Microcopy.greeting(hour: 14), "Good afternoon")
        XCTAssertEqual(Microcopy.greeting(hour: 19), "Good evening")
        XCTAssertEqual(Microcopy.greeting(hour: 2), "Up late?")
    }

    func testVoiceLearningOnlyKeepsRealEdits() {
        let original = "That sounds wonderful, I would love to."
        XCTAssertNil(VoiceLearning.candidate(original: original, edited: original), "Unchanged text teaches nothing")
        XCTAssertNil(VoiceLearning.candidate(original: original, edited: "ok"), "Too short to be a useful example")
        XCTAssertEqual(
            VoiceLearning.candidate(original: original, edited: "  yesss i'm so down  "),
            "yesss i'm so down"
        )
        XCTAssertEqual(
            VoiceLearning.candidate(original: original, edited: original.lowercased()),
            original.lowercased(),
            "Changing only the casing still shows how someone texts"
        )
    }

    func testKeyboardContextExpiresAndPreviews() {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let context = KeyboardContext(text: "Them: hi\nThem: are you free on friday?", source: .shareSheet, createdAt: created)
        XCTAssertEqual(context.preview, "Them: are you free on friday?")
        XCTAssertFalse(context.isExpired(now: created.addingTimeInterval(23 * 3600)))
        XCTAssertTrue(context.isExpired(now: created.addingTimeInterval(25 * 3600)))
    }

    func testATypedServerAddressIsUsedOnlyWhenTheBuildAllowsIt() {
        let fallback = AppConfig.defaultAPIBaseURL
        func url(_ custom: String?, allow: Bool = true) -> URL {
            AppConfig.backend(environment: nil, customURL: custom, allowSwitching: allow).url
        }
        XCTAssertEqual(url(nil), fallback)
        XCTAssertEqual(url("   "), fallback)
        XCTAssertEqual(url("ftp://example.com"), fallback, "Only http and https are accepted")
        XCTAssertEqual(url("my-mac.local:3000"), fallback, "An address needs a scheme")
        XCTAssertEqual(url("http://my-mac.local:3000").absoluteString, "http://my-mac.local:3000")
        XCTAssertEqual(url("http://my-mac.local:3000", allow: false), fallback, "A release build ignores a leftover address")
        XCTAssertEqual(AppConfig.privacyURL(base: URL(string: "https://api.example.com")!).absoluteString, "https://api.example.com/privacy")
    }

    func testPaletteHexAndOpacity() {
        let bone = RGBA(0xF4EEE6)
        XCTAssertEqual(bone.red, 244.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(bone.green, 238.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(bone.blue, 230.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(bone.opacity(0.5).alpha, 0.5, accuracy: 0.0001)
        XCTAssertNotEqual(Palette.background.dark, Palette.background.light)
        XCTAssertEqual(Palette.background.dark, RGBA(0x0F231D), "The ground is bottle green, the same as the app icon")
        XCTAssertEqual(Palette.bubbleMineStart, Palette.bubbleMineEnd, "Bubbles are solid colours, not gradients")
    }
}
