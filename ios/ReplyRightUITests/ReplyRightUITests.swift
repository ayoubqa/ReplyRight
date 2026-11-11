import XCTest

/// Smoke tests for the main paths through the app.
///
/// `-rr-reset` wipes local data at launch and `-rr-skip-onboarding` marks setup as done,
/// so every test starts from a known state. The reply-flow test needs the backend running
/// locally (`npm run dev` in backend/); demo mode is enough.
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
        XCTAssertTrue(app.buttons["home-paste"].waitForExistence(timeout: 10), "Finishing onboarding should land on Home")
    }

    func testPastedConversationProducesReadAndReplies() throws {
        let app = launch(skippingOnboarding: true)
        let paste = app.buttons["home-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        paste.tap()

        let read = app.buttons["input-read"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        XCTAssertFalse(read.isEnabled, "Nothing can be sent until there is something to read")

        let field = app.textViews["input-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Them: are we still on for friday?")
        XCTAssertTrue(read.isEnabled)
        read.tap()

        XCTAssertTrue(
            app.staticTexts["understanding-read"].waitForExistence(timeout: 30),
            "The read should appear. Is the backend running on localhost:3000?"
        )
        app.buttons["understanding-write"].tap()
        XCTAssertTrue(app.buttons["reply-copy"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(app.buttons.matching(identifier: "reply-copy").count, 3, "There should be exactly three options")
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
