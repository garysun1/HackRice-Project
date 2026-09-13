import XCTest

final class AppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesWithAllTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoMode", "--mock-speech", "--mock-intelligence"]
        app.launch()

        XCTAssertTrue(app.buttons["tab.timeline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab.trends"].exists)
        XCTAssertTrue(app.buttons["tab.briefing"].exists)
        XCTAssertTrue(app.buttons["tab.connections"].exists)
        XCTAssertTrue(app.buttons["tab.record"].exists)
    }

    @MainActor
    func testRecordFlowWithMockSpeech() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoMode", "--mock-speech", "--mock-intelligence", "-listView"]
        app.launch()

        app.buttons["tab.record"].tap()
        XCTAssertTrue(app.buttons["record.mic"].waitForExistence(timeout: 5))

        // Start mock recording; the canned script streams in ~2s and finishes.
        // Wait for the stream to END (status flips to "Review and save") so we
        // save the full transcript — saving a partial would legitimately
        // trigger a second (duration) follow-up.
        app.buttons["record.mic"].tap()
        XCTAssertTrue(app.staticTexts["Understood"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Review and save"].waitForExistence(timeout: 10))

        let save = app.buttons["record.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Severity is never inferred, so the first follow-up asks for the
        // patient's own rating; the second asks about the inhaler's effect.
        XCTAssertTrue(app.staticTexts["followup.question"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["followup.question"].label.contains("1 to 10"))
        // Submitting with no answer skips the question. The question element
        // persists across both questions, so match the second by its label.
        app.buttons["followup.submit"].tap()
        let medQuestion = app.staticTexts.matching(
            NSPredicate(format: "identifier == 'followup.question' AND label CONTAINS 'help'")
        ).firstMatch
        XCTAssertTrue(medQuestion.waitForExistence(timeout: 10))
        app.buttons["followup.submit"].tap()

        // The note saves with what we have; sheet dismisses back to the timeline.
        XCTAssertTrue(app.buttons["tab.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chest Tightness"].firstMatch.exists)
    }
}
