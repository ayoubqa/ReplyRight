import XCTest
@testable import ReplyRightCore

final class TypingEngineTests: XCTestCase {
    func testStartsCapitalisedAtTheBeginningOfAField() {
        var engine = TypingEngine()
        engine.reset(before: "")
        XCTAssertEqual(engine.shift, .once)

        XCTAssertEqual(engine.tap(.character("h"), before: "", now: 0), [.insert("H")])
        XCTAssertEqual(engine.shift, .off, "Shift applies to one letter only")
        XCTAssertEqual(engine.tap(.character("i"), before: "H", now: 0.2), [.insert("i")])
    }

    func testSentenceCapitalisationRules() {
        let capitalised = ["", "   ", "Hey. ", "Hey! ", "Hey? ", "Hey…  ", "Hey\n"]
        for text in capitalised {
            XCTAssertTrue(TypingEngine.shouldCapitalize(before: text, mode: .sentences), "after \(text.debugDescription)")
        }
        let lowercase = ["Hey", "Hey ", "Hey, ", "Hey.", "Hey: "]
        for text in lowercase {
            XCTAssertFalse(TypingEngine.shouldCapitalize(before: text, mode: .sentences), "after \(text.debugDescription)")
        }
    }

    func testOtherCapitalisationModes() {
        XCTAssertTrue(TypingEngine.shouldCapitalize(before: "", mode: .words))
        XCTAssertTrue(TypingEngine.shouldCapitalize(before: "hello ", mode: .words))
        XCTAssertFalse(TypingEngine.shouldCapitalize(before: "hello", mode: .words))
        XCTAssertFalse(TypingEngine.shouldCapitalize(before: "", mode: .none))
        XCTAssertTrue(TypingEngine.shouldCapitalize(before: "abc", mode: .allCharacters))
    }

    func testDoubleTapShiftLocksAndThirdTapUnlocks() {
        var engine = TypingEngine(capitalization: .none)
        _ = engine.tap(.shift, before: "", now: 10)
        XCTAssertEqual(engine.shift, .once)
        _ = engine.tap(.shift, before: "", now: 10.2)
        XCTAssertEqual(engine.shift, .locked)

        XCTAssertEqual(engine.tap(.character("a"), before: "", now: 11), [.insert("A")])
        XCTAssertEqual(engine.tap(.character("b"), before: "A", now: 11.2), [.insert("B")])
        XCTAssertEqual(engine.shift, .locked, "Caps lock survives typing")

        _ = engine.tap(.shift, before: "AB", now: 12)
        XCTAssertEqual(engine.shift, .off)
    }

    func testSlowSecondTapTurnsShiftOffInsteadOfLocking() {
        var engine = TypingEngine(capitalization: .none)
        _ = engine.tap(.shift, before: "", now: 10)
        _ = engine.tap(.shift, before: "", now: 11)
        XCTAssertEqual(engine.shift, .off)
    }

    func testDoubleSpaceInsertsFullStopAndCapitalisesNext() {
        var engine = TypingEngine()
        XCTAssertEqual(engine.tap(.space, before: "Hey", now: 1.0), [.insert(" ")])
        XCTAssertEqual(engine.tap(.space, before: "Hey ", now: 1.3), [.deleteBackward(1), .insert(". ")])
        XCTAssertEqual(engine.shift, .once)
        XCTAssertEqual(engine.tap(.space, before: "Hey. ", now: 1.5), [.insert(" ")], "A third space is just a space")
    }

    func testDoubleSpaceGuards() {
        var afterComma = TypingEngine()
        _ = afterComma.tap(.space, before: "Hey,", now: 1.0)
        XCTAssertEqual(afterComma.tap(.space, before: "Hey, ", now: 1.2), [.insert(" ")], "Not after punctuation")

        var tooSlow = TypingEngine()
        _ = tooSlow.tap(.space, before: "Hey", now: 1.0)
        XCTAssertEqual(tooSlow.tap(.space, before: "Hey ", now: 2.5), [.insert(" ")], "Not when the taps are far apart")

        var disabled = TypingEngine(doubleSpaceInsertsPeriod: false)
        _ = disabled.tap(.space, before: "Hey", now: 1.0)
        XCTAssertEqual(disabled.tap(.space, before: "Hey ", now: 1.2), [.insert(" ")], "Not in email or URL fields")

        var interrupted = TypingEngine()
        _ = interrupted.tap(.space, before: "Hey", now: 1.0)
        _ = interrupted.tap(.character("x"), before: "Hey ", now: 1.1)
        XCTAssertEqual(interrupted.tap(.space, before: "Hey x", now: 1.2), [.insert(" ")], "Typing between spaces resets it")
    }

    func testNumbersPageReturnsToLettersAfterSpaceApostropheAndReturn() {
        var engine = TypingEngine(capitalization: .none)

        _ = engine.tap(.page(.numbers), before: "", now: 0)
        XCTAssertEqual(engine.page, .numbers)
        XCTAssertEqual(engine.tap(.character("1"), before: "", now: 0.1), [.insert("1")])
        XCTAssertEqual(engine.page, .numbers, "Digits keep the numbers page open")
        _ = engine.tap(.space, before: "1", now: 5)
        XCTAssertEqual(engine.page, .letters)

        _ = engine.tap(.page(.numbers), before: "", now: 6)
        _ = engine.tap(.character("'"), before: "don", now: 6.1)
        XCTAssertEqual(engine.page, .letters)

        _ = engine.tap(.page(.symbols), before: "", now: 7)
        XCTAssertEqual(engine.tap(.returnKey, before: "", now: 7.1), [.insert("\n")])
        XCTAssertEqual(engine.page, .letters)
    }

    func testRenderedRespectsShiftPageAndAwkwardLetters() {
        var engine = TypingEngine(capitalization: .none)
        XCTAssertEqual(engine.rendered("a"), "a")
        _ = engine.tap(.shift, before: "", now: 0)
        XCTAssertEqual(engine.rendered("a"), "A")
        XCTAssertEqual(engine.rendered("ñ"), "Ñ")
        XCTAssertEqual(engine.rendered("ß"), "ß", "Uppercasing must not turn one letter into two")

        _ = engine.tap(.page(.numbers), before: "", now: 1)
        XCTAssertEqual(engine.rendered("a"), "a", "Shift does not apply off the letters page")
    }

    func testBackspaceReevaluatesCapitalisation() {
        var engine = TypingEngine()
        XCTAssertEqual(engine.tap(.backspace, before: "Hi. X", now: 0), [.deleteBackward(1)])
        XCTAssertEqual(engine.shift, .once, "Back at the start of a sentence")
    }

    func testInertAndGlobeKeysChangeNothing() {
        var engine = TypingEngine(capitalization: .none)
        XCTAssertEqual(engine.tap(.character(""), before: "", now: 0), [])
        XCTAssertEqual(engine.tap(.globe, before: "", now: 0), [])
    }

    func testResetReturnsToLettersAndClearsCapsLock() {
        var engine = TypingEngine(capitalization: .none)
        _ = engine.tap(.shift, before: "", now: 0)
        _ = engine.tap(.shift, before: "", now: 0.1)
        _ = engine.tap(.page(.symbols), before: "", now: 1)
        engine.reset(before: "abc")
        XCTAssertEqual(engine.page, .letters)
        XCTAssertEqual(engine.shift, .off)
    }

    func testApplyEdits() {
        XCTAssertEqual(TypingEngine.apply([.insert("ab"), .deleteBackward(1), .insert("c")], to: "x"), "xac")
        XCTAssertEqual(TypingEngine.apply([.deleteBackward(5)], to: "ab"), "")
    }
}

final class KeyboardLayoutTests: XCTestCase {
    private func fixedUnits(_ row: [KeyboardKey]) -> Double {
        row.filter { !$0.isFlexible }.reduce(0) { $0 + $1.width }
    }

    func testEveryRowFitsTheKeyboardWidth() {
        for page in [KeyboardPage.letters, .numbers, .symbols] {
            for language in KeyboardLanguage.allCases {
                for globe in [true, false] {
                    let layout = KeyboardLayout.make(page: page, kind: .standard, language: language, showsGlobe: globe)
                    XCTAssertEqual(layout.rows.count, 4)
                    XCTAssertEqual(layout.unitsPerRow, 10)
                    for row in layout.rows {
                        let hasFlexible = row.contains { $0.isFlexible }
                        if hasFlexible {
                            XCTAssertLessThan(fixedUnits(row), 10, "The space bar needs room")
                        } else {
                            XCTAssertLessThanOrEqual(fixedUnits(row), 10.0001)
                        }
                    }
                    XCTAssertEqual(fixedUnits(layout.rows[0]), 10, accuracy: 0.0001)
                    XCTAssertEqual(fixedUnits(layout.rows[2]), 10, accuracy: 0.0001)
                }
            }
        }
    }

    func testSpanishAddsEnye() {
        let english = KeyboardLayout.make(page: .letters, kind: .standard, language: .english, showsGlobe: true)
        let spanish = KeyboardLayout.make(page: .letters, kind: .standard, language: .spanish, showsGlobe: true)
        XCTAssertEqual(english.rows[1].count, 9)
        XCTAssertEqual(spanish.rows[1].count, 10)
        XCTAssertEqual(spanish.rows[1].last?.action, .character("ñ"))
        XCTAssertEqual(spanish.rows[3].first { $0.action == .space }?.label, "espacio")
    }

    func testGlobeKeyOnlyWhenTheSystemAsksForIt() {
        let with = KeyboardLayout.make(page: .letters, kind: .standard, language: .english, showsGlobe: true)
        let without = KeyboardLayout.make(page: .letters, kind: .standard, language: .english, showsGlobe: false)
        XCTAssertTrue(with.rows[3].contains { $0.action == .globe })
        XCTAssertFalse(without.rows[3].contains { $0.action == .globe })
        XCTAssertEqual(without.rows[3].first?.width, 2.5, "The page key grows to fill the gap")
    }

    func testFieldTypesAddTheirExtraKeys() {
        func characters(_ kind: KeyboardKind) -> [String] {
            KeyboardLayout.make(page: .letters, kind: kind, language: .english, showsGlobe: true).rows[3].compactMap { key in
                if case .character(let value) = key.action { return value }
                return nil
            }
        }
        XCTAssertEqual(characters(.email), ["@", "."])
        XCTAssertEqual(characters(.twitter), ["@", "#"])
        XCTAssertEqual(characters(.url), [".", "/", ".com"])
        XCTAssertEqual(characters(.standard), [])

        let url = KeyboardLayout.make(page: .letters, kind: .url, language: .english, showsGlobe: true)
        XCTAssertFalse(url.rows[3].contains { $0.action == .space }, "URLs have no spaces")
    }

    func testBottomRowAlwaysHasPageSwitchAndReturn() {
        let letters = KeyboardLayout.make(page: .letters, kind: .standard, language: .english, showsGlobe: true)
        XCTAssertEqual(letters.rows[3].first?.action, .page(.numbers))
        XCTAssertEqual(letters.rows[3].last?.action, .returnKey)

        let numbers = KeyboardLayout.make(page: .numbers, kind: .standard, language: .english, showsGlobe: true)
        XCTAssertEqual(numbers.rows[3].first?.action, .page(.letters))
        XCTAssertEqual(numbers.rows[2].first?.action, .page(.symbols))

        let symbols = KeyboardLayout.make(page: .symbols, kind: .standard, language: .english, showsGlobe: true)
        XCTAssertEqual(symbols.rows[2].first?.action, .page(.numbers))
    }

    func testNumberPads() {
        let plain = KeyboardLayout.make(page: .letters, kind: .numberPad, language: .english, showsGlobe: true)
        XCTAssertEqual(plain.unitsPerRow, 3)
        XCTAssertEqual(plain.rows.count, 4)
        XCTAssertTrue(plain.rows.allSatisfy { $0.count == 3 })
        XCTAssertEqual(plain.rows[3][0].action, .character(""), "The plain pad keeps an inert corner for alignment")
        XCTAssertEqual(plain.rows[3][1].action, .character("0"))
        XCTAssertEqual(plain.rows[3][2].action, .backspace)

        let decimal = KeyboardLayout.make(page: .letters, kind: .decimalPad, language: .english, showsGlobe: true)
        XCTAssertEqual(decimal.rows[3][0].action, .character("."))

        let phone = KeyboardLayout.make(page: .letters, kind: .phonePad, language: .english, showsGlobe: true)
        XCTAssertEqual(phone.rows[3][0].action, .character("+"))
        XCTAssertEqual(phone.rows[3][0].alternates, ["*", "#"])
    }

    func testLongPressAlternates() {
        let letters = KeyboardLayout.make(page: .letters, kind: .standard, language: .english, showsGlobe: true)
        let keys = letters.rows.flatMap { $0 }
        XCTAssertTrue(keys.first { $0.action == .character("e") }?.alternates.contains("é") ?? false)
        XCTAssertEqual(keys.first { $0.action == .character("n") }?.alternates, ["ñ"])
        XCTAssertEqual(keys.first { $0.action == .character("q") }?.alternates, [])

        let numbers = KeyboardLayout.make(page: .numbers, kind: .standard, language: .english, showsGlobe: true)
        let punctuation = numbers.rows.flatMap { $0 }
        XCTAssertEqual(punctuation.first { $0.action == .character("?") }?.alternates, ["¿"])
        XCTAssertEqual(punctuation.first { $0.action == .character("!") }?.alternates, ["¡"])
    }

    func testFunctionKeysAreMarked() {
        XCTAssertTrue(KeyboardKey(action: .shift, label: "shift").isFunction)
        XCTAssertTrue(KeyboardKey(action: .returnKey, label: "return").isFunction)
        XCTAssertFalse(KeyboardKey(action: .character("a"), label: "a").isFunction)
        XCTAssertFalse(KeyboardKey(action: .space, label: "space").isFunction)
    }

    func testKeyboardLanguageFollowsMyVoice() {
        XCTAssertEqual(KeyboardLanguage.preferred(for: VoiceProfile()), .english)
        XCTAssertEqual(KeyboardLanguage.preferred(for: VoiceProfile(replyLanguage: "es")), .spanish)
        XCTAssertEqual(KeyboardLanguage.preferred(for: VoiceProfile(replyLanguage: "match", languages: ["es", "en"])), .spanish)
        XCTAssertEqual(KeyboardLanguage.preferred(for: VoiceProfile(replyLanguage: "en", languages: ["es"])), .english)
    }
}

final class DraftAndSensitivityTests: XCTestCase {
    func testDraftContextCountsForCursorAndDeletion() {
        let draft = DraftContext(before: "ab", after: "😀!")
        XCTAssertEqual(draft.text, "ab😀!")
        XCTAssertEqual(draft.cursorOffsetToEnd, 3, "adjustTextPosition counts UTF-16 units, and the emoji is two")
        XCTAssertEqual(draft.deletionCount, 4, "deleteBackward removes one character at a time")
        XCTAssertFalse(draft.isEmpty)
    }

    func testDraftContextHandlesMissingText() {
        let empty = DraftContext(before: nil, after: nil)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.cursorOffsetToEnd, 0)
        XCTAssertEqual(empty.deletionCount, 0)
        XCTAssertTrue(DraftContext(before: "  \n", after: nil).isEmpty)
    }

    func testAIStaysOffInSensitiveFields() {
        XCTAssertTrue(FieldSensitivity.isSensitive(isSecure: true, contentType: nil, kind: .standard))
        for type in ["password", "new-password", "one-time-code", "cc-number", "username"] {
            XCTAssertTrue(FieldSensitivity.isSensitive(isSecure: false, contentType: type, kind: .standard), type)
        }
        for kind in [KeyboardKind.numberPad, .decimalPad, .phonePad] {
            XCTAssertTrue(FieldSensitivity.isSensitive(isSecure: false, contentType: nil, kind: kind))
        }
    }

    func testAIAvailableInOrdinaryFields() {
        XCTAssertFalse(FieldSensitivity.isSensitive(isSecure: false, contentType: nil, kind: .standard))
        XCTAssertFalse(FieldSensitivity.isSensitive(isSecure: false, contentType: "", kind: .standard))
        XCTAssertFalse(FieldSensitivity.isSensitive(isSecure: false, contentType: "name", kind: .twitter))
    }
}
