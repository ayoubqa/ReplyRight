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

        next.tap() // welcome -> age
        XCTAssertFalse(next.isEnabled, "Continue must stay disabled until the user confirms they are an adult")
        app.buttons["onboarding-adult"].tap()
        XCTAssertTrue(next.isEnabled)

        // age, goals, personality, texting, languages, tone, ready
        for _ in 0..<7 {
            next.tap()
        }
        XCTAssertTrue(app.buttons["home-read"].waitForExistence(timeout: 10), "Finishing onboarding should land on Home")
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

    func testAPersonCanBeAddedToTheNotebookAndDeleted() throws {
        let app = launch(skippingOnboarding: true)
        XCTAssertTrue(app.tabBars.buttons["Notebook"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Notebook"].tap()

        app.buttons["notebook-add-person"].tap()
        let name = app.textFields["person-alias"]
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
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 10))
        app.tabBars.buttons["You"].tap()

        app.buttons["you-see-pro"].tap()
        XCTAssertTrue(app.buttons["paywall-close"].waitForExistence(timeout: 5))
        app.buttons["paywall-close"].tap()

        app.buttons["you-privacy"].tap()
        XCTAssertTrue(app.buttons["privacy-erase-all"].waitForExistence(timeout: 5))
    }
}
