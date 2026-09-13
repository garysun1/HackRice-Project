import XCTest

final class AppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Grants the HealthKit authorization sheet when it appears.
    ///
    /// Two things make this non-obvious:
    /// 1. The sheet is a remote view hosted *inside the app's own process*, so it is
    ///    reachable via `XCUIApplication()` — not `XCUIApplication(bundleIdentifier:
    ///    "com.apple.Health")`, which reports an empty tree.
    /// 2. "Turn On All" is a Cell, not a Button, and "Allow" starts out disabled.
    ///
    /// HealthKit records its decision per bundle id and that decision **survives app
    /// uninstall** — only `simctl erase` resets it, and it never re-prompts once decided.
    /// So a missing sheet is not a failure here; it means access was already decided.
    @MainActor
    private func grantHealthAccessIfPrompted() {
        let app = XCUIApplication()
        let turnOnAll = app.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        guard turnOnAll.waitForExistence(timeout: 10) else { return }
        turnOnAll.tap()

        let allow = app.buttons["UIA.Health.Allow.Button"]
        guard allow.waitForExistence(timeout: 5) else { return }
        XCTAssertTrue(allow.isEnabled, "'Turn On All' did not enable the Allow button.")
        allow.tap()
    }

    /// Exercises the real HealthKit read path end-to-end: seed the persona in,
    /// query it back out, and confirm the Connections screen renders a source.
    @MainActor
    func testHealthKitSeedAndReadBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-healthkit", "-seedHealthKit", "--mock-speech", "-openTab", "trends"]
        app.launch()

        grantHealthAccessIfPrompted()

        XCTAssertTrue(app.tabBars.buttons["Trends"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Trends"].tap()

        // Assert on the day count, not on a source chip: HKSourceQuery reports this app
        // as a "source" merely for holding authorization, so a chip can appear even when
        // the write silently failed and there is nothing to read back.
        let probe = app.descendants(matching: .any)["trends.stats"]
        XCTAssertTrue(probe.waitForExistence(timeout: 25))
        let value = (probe.value as? String) ?? ""
        let days = Int(value.replacingOccurrences(of: "metricDays:", with: "")) ?? 0
        XCTAssertGreaterThan(
            days, 0,
            "HealthKit returned no daily metrics — seeding or read authorization failed."
        )
    }

    /// Walks all three levels of the Connections drill-down. Uses the mock provider
    /// (`-demoMode` without `-healthkit`), so no HealthKit permission is involved and the
    /// test is repeatable on any simulator.
    @MainActor
    func testConnectionsDrillDownToImportedData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoMode", "--mock-speech", "-openTab", "connections"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Connections"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Connections"].tap()

        // Level 1 — the three categories.
        for category in ["general", "sleep", "fitness"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["connections.category.\(category)"].waitForExistence(timeout: 5),
                "Missing category row for \(category)"
            )
        }

        // Level 2 — Fitness is supplied by Strava and Fitbit in the seeded persona.
        app.descendants(matching: .any)["connections.category.fitness"].tap()
        let strava = app.descendants(matching: .any)["connections.source.Strava"]
        XCTAssertTrue(strava.waitForExistence(timeout: 5), "Strava should supply fitness data")

        // Level 3 — Strava contributes workouts, and nothing else.
        strava.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["connections.detail.workoutMinutes"].waitForExistence(timeout: 5),
            "Strava detail should list its workout contribution"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["connections.detail.sleepHours"].exists,
            "Strava must not claim data it never supplied"
        )
    }

    @MainActor
    func testAppLaunchesWithAllTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoMode", "--mock-speech"]
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Timeline"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Trends"].exists)
        XCTAssertTrue(app.tabBars.buttons["Briefing"].exists)
        XCTAssertTrue(app.tabBars.buttons["Connections"].exists)
    }

    @MainActor
    func testRecordFlowWithMockSpeech() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoMode", "--mock-speech"]
        app.launch()

        app.buttons["timeline.record"].tap()
        XCTAssertTrue(app.buttons["record.mic"].waitForExistence(timeout: 5))

        // Start mock recording; the canned script streams in ~2s and finishes.
        app.buttons["record.mic"].tap()
        XCTAssertTrue(app.staticTexts["Understood"].waitForExistence(timeout: 10))

        let save = app.buttons["record.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Sheet dismisses back to the timeline with the new entry present.
        XCTAssertTrue(app.buttons["timeline.record"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chest Tightness"].firstMatch.exists)
    }

    @MainActor
    func testTrendsTileGridExpands() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoMode", "--mock-speech", "-openTab", "trends"]
        app.launch()
        let tile = app.descendants(matching: .any)["trends.tile.airQuality"]
        XCTAssertTrue(tile.waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["trends.range"].exists)

        let gridScreenshot = XCTAttachment(screenshot: app.screenshot())
        gridScreenshot.name = "trends-grid-30D"
        gridScreenshot.lifetime = .keepAlways
        add(gridScreenshot)

        for label in ["7D", "90D"] {
            let segment = app.buttons[label]
            XCTAssertTrue(segment.waitForExistence(timeout: 5))
            segment.tap()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "trends-grid-\(label)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app.buttons["30D"].tap()

        tile.tap()
        XCTAssertTrue(app.descendants(matching: .any)["trends.detail.rug"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Air quality"].waitForExistence(timeout: 5))

        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "trends-air-quality-detail"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }
}
