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
        // The persona always supplies daily AQI, so a base rate must be present.
        let baseRate = try! #require(corr.highAQIDayShare)
        #expect(episodeShare > Double(baseRate) * 1.8)
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
        #expect(sources.contains("Cronometer"))
    }

    @Test func nutritionDetailIsAttributed() {
        let out = AsthmaPersona.generate(reference: reference)
        let withFood = out.metrics.filter { $0.dietaryEnergyKcal != nil }
        #expect(!withFood.isEmpty)
        // Caffeine/sodium/water are logged on exactly the days food was logged.
        for day in withFood {
            #expect(day.caffeineMg != nil)
            #expect(day.sodiumMg != nil)
            #expect(day.waterML != nil)
        }
        for day in out.metrics where day.dietaryEnergyKcal == nil {
            #expect(day.caffeineMg == nil)
        }
        #expect(Set(withFood.compactMap { $0.caffeineMg?.sourceName }) == ["MyFitnessPal"])
        #expect(Set(withFood.compactMap { $0.waterML?.sourceName }) == ["Cronometer"])
    }

    @Test func attributedMetricsCoversEveryPopulatedField() {
        let day = DailyMetrics(
            date: reference,
            steps: .init(1000, via: "Fitbit"),
            sleepHours: .init(7.5, via: "Oura"),
            workoutMinutes: .init(30, via: "Strava"),
            caffeineMg: .init(95, via: "Cronometer")
        )
        let labels = day.attributedMetrics
        #expect(labels.count == 4)
        #expect(Set(labels.map(\.sourceName)) == ["Fitbit", "Oura", "Strava", "Cronometer"])
        // Unset metrics must not appear.
        #expect(!labels.contains { $0.label == "Sodium" })
    }
}
