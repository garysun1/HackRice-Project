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
        app.launchArguments = ["-seedHealthKit", "-inMemoryStore", "-offline", "--mock-speech", "-openTab", "connections"]
        app.launch()

        let connect = app.descendants(matching: .any)["connections.appleHealth.connect"]
        if connect.waitForExistence(timeout: 15) {
            connect.tap()
            grantHealthAccessIfPrompted()
        } else {
            XCTAssertTrue(app.staticTexts["Apple Health"].firstMatch.exists)
        }

        XCTAssertTrue(app.buttons["tab.trends"].waitForExistence(timeout: 15))
        app.buttons["tab.trends"].tap()

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

        XCTAssertTrue(app.buttons["tab.connections"].waitForExistence(timeout: 10))
        app.buttons["tab.connections"].tap()

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

    @MainActor
    func testRealModeStartsEmpty() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-offline", "-ignoreHealthKitData", "--mock-speech"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Your healthspan record starts here"].waitForExistence(timeout: 10)
        )

        app.buttons["tab.trends"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["trends.empty"].waitForExistence(timeout: 5)
        )
        let airQualityTile = app.descendants(matching: .any)["trends.tile.airQuality"]
        XCTAssertFalse(airQualityTile.waitForExistence(timeout: 3))

        app.buttons["tab.connections"].tap()
        let connect = app.descendants(matching: .any)["connections.appleHealth.connect"]
        let hasConnectButton = connect.waitForExistence(timeout: 5)
        let hasAppleHealthRow = app.staticTexts["Apple Health"].firstMatch.exists
        XCTAssertTrue(hasConnectButton || hasAppleHealthRow)
    }

    @MainActor
    func testManualMetricsShowInTrends() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-offline", "--mock-speech", "-openTab", "connections"]
        app.launch()

        let manualEntry = app.descendants(matching: .any)["connections.manualEntry"]
        XCTAssertTrue(manualEntry.waitForExistence(timeout: 10))
        manualEntry.tap()

        let sleep = app.textFields["manual.metric.sleepHours"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 5))
        sleep.tap()
        sleep.typeText("5.5")

        let metricsScreenshot = XCTAttachment(screenshot: app.screenshot())
        metricsScreenshot.name = "phase34-manual-metrics-values"
        metricsScreenshot.lifetime = .keepAlways
        add(metricsScreenshot)

        app.buttons["manual.save"].tap()

        app.buttons["tab.trends"].tap()
        let tile = app.descendants(matching: .any)["trends.tile.sleepHours"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        XCTAssertTrue(tile.label.contains("5.5"), "Sleep tile should expose the manually entered value")

        let trendsScreenshot = XCTAttachment(screenshot: app.screenshot())
        trendsScreenshot.name = "phase34-trends-manual-sleep"
        trendsScreenshot.lifetime = .keepAlways
        add(trendsScreenshot)
    }

    @MainActor
    func testEpisodeEditAndDelete() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-inMemoryStore", "-offline", "--mock-speech", "--mock-intelligence", "-listView"]
        app.launch()

        let emptyState = app.staticTexts["Your healthspan record starts here"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10))

        // Create the entry the way users do: voice (mock-scripted here).
        app.buttons["tab.record"].tap()
        XCTAssertTrue(app.buttons["record.mic"].waitForExistence(timeout: 5))
        app.buttons["record.mic"].tap()
        XCTAssertTrue(app.staticTexts["Review and save"].waitForExistence(timeout: 10))
        app.buttons["record.save"].tap()
        // Skip both follow-ups (severity, medication effect).
        XCTAssertTrue(app.staticTexts["followup.question"].waitForExistence(timeout: 10))
        app.buttons["followup.submit"].tap()
        let medQuestion = app.staticTexts.matching(
            NSPredicate(format: "identifier == 'followup.question' AND label CONTAINS 'help'")
        ).firstMatch
        XCTAssertTrue(medQuestion.waitForExistence(timeout: 10))
        app.buttons["followup.submit"].tap()

        // Tap the row to open the editor and rate the skipped severity.
        let row = app.staticTexts["Chest Tightness"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let severity = app.sliders["episode.severity"]
        XCTAssertTrue(severity.waitForExistence(timeout: 5))

        let editorScreenshot = XCTAttachment(screenshot: app.screenshot())
        editorScreenshot.name = "episode-editor"
        editorScreenshot.lifetime = .keepAlways
        add(editorScreenshot)

        severity.adjust(toNormalizedSliderPosition: 0.7)
        app.buttons["episode.save"].tap()

        // Swipe-delete brings back the empty state.
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
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
