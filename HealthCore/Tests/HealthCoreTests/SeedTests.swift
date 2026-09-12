import Foundation
import Testing
@testable import HealthCore

@Suite struct SeedTests {
    let reference = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func deterministicAcrossRuns() {
        let a = AsthmaPersona.generate(reference: reference)
        let b = AsthmaPersona.generate(reference: reference)
        #expect(a.metrics.map(\.date) == b.metrics.map(\.date))
        #expect(a.events.map(\.transcript) == b.events.map(\.transcript))
        #expect(a.events.map(\.severity) == b.events.map(\.severity))
    }

    @Test func generatesFullPeriod() {
        let out = AsthmaPersona.generate(days: 92, reference: reference)
        #expect(out.metrics.count == 92)
        // Enough episodes for a compelling timeline, not so many it's implausible.
        #expect(out.events.count >= 12 && out.events.count <= 45)
    }

    @Test func episodesClusterOnHighAQIDays() {
        let out = AsthmaPersona.generate(reference: reference)
        let insights = Insights(events: out.events, metrics: out.metrics)
        let corr = try! #require(insights.highAQICorrelation)
        // The demo's core claim: episodes concentrate on high-AQI days far above base rate.
        let episodeShare = Double(corr.onHighAQIDays) / Double(corr.total) * 100
        #expect(episodeShare > Double(corr.highAQIDayShare) * 1.8)
        #expect(episodeShare > 50)
    }

    @Test func metricsCarrySourceAttribution() {
        let out = AsthmaPersona.generate(reference: reference)
        let sources = Set(out.metrics.compactMap { $0.steps?.sourceName })
        #expect(sources == ["Fitbit (Google Health)"])
        let workoutSources = Set(out.metrics.compactMap { $0.workoutMinutes?.sourceName })
        #expect(workoutSources.isSubset(of: ["Strava"]))
    }

    @Test func mockHealthProviderListsSources() async throws {
        let out = AsthmaPersona.generate(reference: reference)
        let provider = MockHealthProvider(metrics: out.metrics)
        let sources = try await provider.contributingSources()
        #expect(sources.contains("Fitbit (Google Health)"))
        #expect(sources.contains("Apple Watch"))
        #expect(sources.contains("Strava"))
        #expect(sources.contains("MyFitnessPal"))
    }
}
