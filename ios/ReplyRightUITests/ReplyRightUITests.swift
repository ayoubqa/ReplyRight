import XCTest

/// Smoke tests for the main paths through the app.
///
/// `-rr-reset` wipes local data at launch and `-rr-skip-onboarding` marks setup as done,
/// so every test starts from a known state.
///
/// The tests that ask for an answer need the backend running locally
/// (`npm run dev` in backend/). Demo mode is enough: they check that an answer
/// arrives and is labelled, not what it says. A fresh install gets three coaching
/// turns a day on the free plan, so keep `USAGE_LIMITS=off` in backend/.env.local
/// when running the suite repeatedly.
final class ReplyRightUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(skippingOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-rr-reset"] + (skippingOnboarding ? ["-rr-skip-onboarding"] : [])
        app.launch()
        return app
    }

    func testOnboardingRequiresAdultConfirmationAndLeadsHome() throws {
        let app = launch(skippingOnboarding: false)
        let next = app.buttons["onboarding-continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))

        // Welcome: nothing moves until the user confirms they are an adult.
        XCTAssertFalse(next.isEnabled, "Continue must stay disabled until the user confirms they are an adult")
        app.buttons["onboarding-adult"].tap()
        XCTAssertTrue(next.isEnabled)

        next.tap() // welcome -> communication style
        next.tap() // style -> first result

        // The example is the default first result. It makes no request: its
        // replies are written in advance and say so. This works with no server.
        XCTAssertTrue(app.descendants(matching: .any)["onboarding-example"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding-skip"].exists)
        next.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["example-label"].firstMatch.waitForExistence(timeout: 3),
            "The example should appear at once, labelled as written in advance, without waiting for the server"
        )
        app.buttons["example-try-real"].tap()
        XCTAssertTrue(app.buttons["home-read"].waitForExistence(timeout: 10), "Finishing onboarding should land on Home")

        // The keyboard is introduced on Home, after onboarding, not forced into it.
        XCTAssertTrue(app.buttons["home-keyboard"].waitForExistence(timeout: 5), "Home should invite the user to set up the keyboard")
    }

    func testTheHomeExampleMakesNoRequest() throws {
        let app = launch(skippingOnboarding: true)
        let example = app.buttons["home-example"]
        XCTAssertTrue(example.waitForExistence(timeout: 10))
        example.tap()
        // Appears at once and is labelled. There is no loading state, because nothing is asked of the server.
        XCTAssertTrue(app.descendants(matching: .any)["example-label"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["reply-copy"].exists, "The example is not an AI result and cannot be passed off as one")
    }

    func testTheFourTabsAndSettingsBehindTheProfileButton() throws {
        let app = launch(skippingOnboarding: true)
        let tabs = app.tabBars
        XCTAssertTrue(tabs.buttons["Reply"].waitForExistence(timeout: 10))
        for name in ["Reply", "Coach", "Keyboard", "People"] {
            XCTAssertTrue(tabs.buttons[name].exists, "Missing tab \(name)")
        }
        XCTAssertFalse(tabs.buttons["You"].exists, "Settings is not a tab any more")

        app.buttons["profile-button"].firstMatch.tap()
        XCTAssertTrue(app.buttons["settings-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["you-voice"].exists)
        app.buttons["settings-done"].tap()

        // Saved lines stay one tap from Home.
        XCTAssertTrue(app.buttons["home-saved"].waitForExistence(timeout: 5))
    }

    func testKeyboardStatusOnlyReflectsWhatTheKeyboardReported() throws {
        let app = launch(skippingOnboarding: true)
        XCTAssertTrue(app.tabBars.buttons["Keyboard"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Keyboard"].tap()

        // A fresh install has no evidence, so the app must not claim anything.
        let badge = app.descendants(matching: .any)["keyboard-status-badge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(badge, "Keyboard status: Not set up"))

        // The setup journey records the user's word, not proof.
        app.buttons["keyboard-setup"].tap()
        let confirm = app.buttons["setup-confirm-enabled"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        app.buttons["setup-close"].tap()
        XCTAssertTrue(waitForLabel(badge, "Keyboard status: Turned on, not tested yet"), "The user's word is shown as not tested")

        // The test field recognises the sentence the ReplyRight keyboard types.
        // Here the system keyboard types it, which exercises the app's side only.
        let field = textInput(app, "keyboard-practice")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("ReplyRight Keyboard \u{2713} Full Access off")
        XCTAssertTrue(waitForLabel(badge, "Keyboard status: Typing only"), "A test without Full Access is limited, not ready")
    }

    /// A text field or text view by identifier. SwiftUI may draw a multi-line
    /// `TextField` as either, depending on the iOS version.
    private func textInput(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let types = [XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue]
        let predicate = NSPredicate(format: "identifier == %@ AND elementType IN %@", identifier, types)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func testPastedConversationProducesReadAndThreeLabelledReplies() throws {
        let app = launch(skippingOnboarding: true)
        let read = app.buttons["home-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 10))
        XCTAssertFalse(read.isEnabled, "Nothing can be sent until there is something to read")

        let field = app.textViews["home-message"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Them: are we still on for friday?")
        XCTAssertTrue(read.isEnabled)
        read.tap()

        XCTAssertTrue(
            app.staticTexts["understanding-read"].waitForExistence(timeout: 30),
            "The read should appear. Is the backend running on localhost:3000? Open Connection on the Home screen to check."
        )
        app.buttons["understanding-write"].tap()
        XCTAssertTrue(app.buttons["reply-copy"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons.matching(identifier: "reply-copy").count, 3, "There should be exactly three options")

        // Every answer says where it came from: live AI or a demo sample.
        let live = app.staticTexts["Written by live AI"]
        let demo = app.staticTexts["Demo sample, not written for you"]
        XCTAssertTrue(live.exists || demo.exists, "Replies must be labelled as live AI or as demo samples")

        // The adjustments are there for each reply.
        app.buttons["reply-tweak"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tweak-more_direct"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tweak-ask_question"].exists)
    }

    func testConnectionScreenShowsWhereTheAppIsPointed() throws {
        let app = launch(skippingOnboarding: true)
        let pill = app.buttons["home-connection"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()

        XCTAssertTrue(app.buttons["connection-check"].waitForExistence(timeout: 5))
        // The address is on screen whether or not the server answers.
        XCTAssertTrue(app.staticTexts["Address"].exists)
        // A debug build can be pointed at another server.
        XCTAssertTrue(app.textFields["connection-address"].waitForExistence(timeout: 5))
    }

    func testTheCoachChecksAMessage() throws {
        let app = launch(skippingOnboarding: true)
        XCTAssertTrue(app.tabBars.buttons["Coach"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Coach"].tap()

        app.buttons["coach-review"].tap()
        let draft = app.textViews["review-draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        draft.tap()
        draft.typeText("hey!! I had the BEST time, let me know if you want to do it again!!")
        app.buttons["review-submit"].tap()

        XCTAssertTrue(
            app.buttons["review-copy"].waitForExistence(timeout: 30),
            "The review should arrive with a suggested alternative. Is the backend running?"
        )
        XCTAssertTrue(app.staticTexts["What you're going for"].exists)
        XCTAssertTrue(app.staticTexts["How it reads right now"].exists)
    }

    func testAPersonCanBeAddedAndDeleted() throws {
        let app = launch(skippingOnboarding: true)
        XCTAssertTrue(app.tabBars.buttons["People"].waitForExistence(timeout: 10))
        app.tabBars.buttons["People"].tap()

        app.buttons["notebook-add-person"].tap()
        let name = textInput(app, "person-alias")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Sam")
        app.buttons["person-save"].tap()

        let row = app.buttons["person-Sam"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let delete = app.buttons["person-delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["person-export"].exists)
        delete.tap()
        app.buttons["Delete everything about them"].tap()
        XCTAssertFalse(app.buttons["person-Sam"].waitForExistence(timeout: 2), "The person should be gone")
    }

    func testPrivacyCenterAndPaywallAreReachable() throws {
        let app = launch(skippingOnboarding: true)
        let profile = app.buttons["profile-button"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()

        // The paywall opens on top of Settings, not behind it.
        XCTAssertTrue(app.buttons["you-see-pro"].waitForExistence(timeout: 5))
        app.buttons["you-see-pro"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 5))
        app.buttons["paywall-close"].tap()

        app.buttons["you-privacy"].tap()
        XCTAssertTrue(app.buttons["privacy-erase-all"].waitForExistence(timeout: 5))
    }
}
