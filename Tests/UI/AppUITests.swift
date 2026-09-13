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

        XCTAssertTrue(app.tabBars.buttons["Log"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Trends"].exists)
        XCTAssertTrue(app.tabBars.buttons["Briefing"].exists)
        XCTAssertTrue(app.tabBars.buttons["Connections"].exists)
    }

    @MainActor
    func testRecordFlowWithMockSpeech() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoMode", "--mock-speech", "--mock-intelligence", "-listView"]
        app.launch()

        app.buttons["timeline.record"].tap()
        XCTAssertTrue(app.buttons["record.mic"].waitForExistence(timeout: 5))

        // Start mock recording; the canned script streams in ~2s and finishes.
        app.buttons["record.mic"].tap()
        XCTAssertTrue(app.staticTexts["Understood"].waitForExistence(timeout: 10))

        let save = app.buttons["record.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // The canned note mentions the inhaler without stating whether it
        // helped → the completeness check must ask exactly that follow-up.
        XCTAssertTrue(app.staticTexts["followup.question"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["followup.question"].label.contains("help"))
        app.buttons["followup.skip"].tap()

        // Skipping saves what we have; sheet dismisses back to the timeline.
        XCTAssertTrue(app.buttons["timeline.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chest Tightness"].firstMatch.exists)
    }
}
