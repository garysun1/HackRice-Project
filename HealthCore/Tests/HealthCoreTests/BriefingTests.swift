import Foundation
import Testing
@testable import HealthCore

@Suite struct BriefingTests {
    let reference = Date(timeIntervalSince1970: 1_760_000_000)

    var persona: AsthmaPersona.Output { AsthmaPersona.generate(reference: reference) }

    @Test func generatesBothViews() {
        let out = persona
        let briefing = MockIntelligence().generateBriefing(events: out.events, metrics: out.metrics, now: reference)

        #expect(briefing.clinicianNote.chiefConcerns.contains("episodes"))
        #expect(!briefing.clinicianNote.episodeTimeline.isEmpty)
        #expect(briefing.clinicianNote.episodeTimeline.count <= 15)
        #expect(!briefing.clinicianNote.correlations.isEmpty)
        #expect(!briefing.patientView.talkingPoints.isEmpty)
        #expect(briefing.patientView.questions.count == 3)
        #expect(briefing.periodStart <= briefing.periodEnd)
    }

    @Test func surfacesAQICorrelation() {
        let out = persona
        let briefing = MockIntelligence().generateBriefing(events: out.events, metrics: out.metrics, now: reference)
        let mentionsAQI = briefing.clinicianNote.correlations.contains { $0.contains("AQI") }
        #expect(mentionsAQI)
    }

    @Test func emptyTimelineDoesNotCrash() {
        let briefing = MockIntelligence().generateBriefing(events: [], metrics: [], now: reference)
        #expect(briefing.clinicianNote.episodeTimeline.isEmpty)
        #expect(briefing.patientView.summary.contains("0"))
    }

    @Test func insightsStatistics() {
        let out = persona
        let insights = Insights(events: out.events, metrics: out.metrics)
        #expect(insights.meanSeverity > 1 && insights.meanSeverity < 10)
        #expect(insights.periodDays > 30)
        #expect(insights.episodesPerWeek > 0)
        #expect(!insights.symptomCounts.isEmpty)
    }

    @Test func mockTranscriberStreamsScript() async throws {
        let transcriber = MockTranscriber(interval: 0.01)
        var partials: [String] = []
        for try await partial in transcriber.transcribe() {
            partials.append(partial)
        }
        #expect(partials == MockTranscriber.defaultScript)
        #expect(partials.last?.contains("rescue inhaler") == true)
    }

    @Test func aqiBaseRateOmittedWhenNoDailyAirQuality() {
        // A HealthKit-only timeline: events carry their own AQI snapshot, but the
        // daily metric series has none, so there is no honest base rate to quote.
        let events = (0..<3).map { i in
            HealthEvent(
                timestamp: reference.addingTimeInterval(Double(i) * 86_400),
                symptom: "wheezing",
                severity: 6,
                transcript: "test",
                source: .seeded,
                environment: EnvironmentSnapshot(aqi: 140, capturedAt: reference)
            )
        }
        let metrics = (0..<3).map { i in
            DailyMetrics(
                date: reference.addingTimeInterval(Double(i) * 86_400),
                sleepHours: .init(7.0, via: "Apple Watch")
            )
        }
        let corr = Insights(events: events, metrics: metrics).highAQICorrelation
        #expect(corr?.onHighAQIDays == 3)
        #expect(corr?.highAQIDayShare == nil)

        let briefing = MockIntelligence().generateBriefing(events: events, metrics: metrics, now: reference)
        let aqiLine = briefing.clinicianNote.correlations.first { $0.contains("AQI") }
        #expect(aqiLine != nil)
        #expect(aqiLine?.contains("0%") == false)
        #expect(aqiLine?.contains("of days were high-AQI") == false)
    }

    @Test func aqiBaseRatePresentWhenDailySeriesExists() {
        let out = AsthmaPersona.generate(reference: reference)
        let corr = Insights(events: out.events, metrics: out.metrics).highAQICorrelation
        #expect(corr?.highAQIDayShare != nil)
    }
}
