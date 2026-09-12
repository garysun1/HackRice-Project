import Foundation
import Testing
@testable import HealthCore

@Suite struct ExtractionTests {
    let intelligence = MockIntelligence()
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func extractsInhalerEpisode() {
        let event = intelligence.extractEvent(
            from: "Used my rescue inhaler twice this morning, chest tightness after walking outside for about an hour.",
            at: now
        )
        #expect(event.symptom == "chest tightness")
        #expect(event.medications == ["albuterol (rescue inhaler)"])
        #expect(event.tags.contains("outdoors"))
        #expect(event.tags.contains("morning"))
        #expect(event.duration == 3600)
        // med mention bumps to ≥5, "twice" adds 1
        #expect(event.severity >= 6)
        #expect(event.source == .voice)
    }

    @Test func extractsWheezingWithSeverityCue() {
        let event = intelligence.extractEvent(
            from: "Really bad wheezing during my run, had to stop for 20 minutes.",
            at: now
        )
        #expect(event.symptom == "wheezing")
        #expect(event.severity >= 8)
        #expect(event.duration == 1200)
        #expect(event.tags.contains("during/after activity"))
    }

    @Test func mildSymptomGetsLowSeverity() {
        let event = intelligence.extractEvent(from: "A slight cough tonight, nothing major.", at: now)
        #expect(event.symptom == "coughing")
        #expect(event.severity <= 4)
        #expect(event.medications.isEmpty)
    }

    @Test func unknownSymptomFallsBack() {
        let event = intelligence.extractEvent(from: "Just feeling off today.", at: now)
        #expect(event.symptom == "general discomfort")
        #expect(event.severity >= 1 && event.severity <= 10)
    }

    @Test func parsesDurations() {
        #expect(MockIntelligence.parseDuration(from: "lasted about 2 hours") == 7200)
        #expect(MockIntelligence.parseDuration(from: "for 45 minutes or so") == 2700)
        #expect(MockIntelligence.parseDuration(from: "half an hour roughly") == 1800)
        #expect(MockIntelligence.parseDuration(from: "it went on all day") == 28800.0)
        #expect(MockIntelligence.parseDuration(from: "no time mentioned") == nil)
    }
}
