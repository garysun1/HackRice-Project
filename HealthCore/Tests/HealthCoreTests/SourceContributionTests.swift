import Foundation
import Testing
@testable import HealthCore

@Suite struct SourceContributionTests {
    let reference = Date(timeIntervalSince1970: 1_760_000_000)

    var contributions: [SourceContribution] {
        SourceContribution.from(metrics: AsthmaPersona.generate(reference: reference).metrics)
    }

    private func source(_ name: String) throws -> SourceContribution {
        try #require(contributions.first { $0.sourceName == name })
    }

    @Test func groupsPersonaByContributingSource() {
        #expect(contributions.map(\.sourceName) == [
            "Apple Watch", "Cronometer", "Fitbit (Google Health)", "MyFitnessPal", "Strava"
        ])
    }

    @Test func eachSourceReportsOnlyWhatItSupplies() throws {
        // Cronometer is the case the old name-matching badge got wrong — it had no
        // pattern and silently fell through to a generic label.
        #expect(try source("Cronometer").dataTypes.map(\.kind) == [.sodiumMg, .waterML])
        #expect(try source("Apple Watch").dataTypes.map(\.kind) == [.restingHeartRate])
        #expect(try source("Strava").dataTypes.map(\.kind) == [.workoutMinutes])
        #expect(try source("MyFitnessPal").dataTypes.map(\.kind) == [.dietaryEnergyKcal, .caffeineMg])
        #expect(try source("Fitbit (Google Health)").dataTypes.map(\.kind) == [.steps, .sleepHours])
    }

    @Test func sourceSpanningTwoCategoriesAppearsInBoth() throws {
        // Fitbit supplies steps (fitness) and sleep (sleep), so it must list under both.
        let fitbit = try source("Fitbit (Google Health)")
        #expect(fitbit.categories == [.fitness, .sleep])
        #expect(fitbit.dataTypes(in: .sleep).map(\.kind) == [.sleepHours])
        #expect(fitbit.dataTypes(in: .fitness).map(\.kind) == [.steps])
    }

    @Test func everyCategoryHasAtLeastOneSource() {
        for category in HealthDataCategory.allCases {
            #expect(!contributions.supplying(category).isEmpty, "\(category) had no sources")
        }
        #expect(contributions.supplying(.general).map(\.sourceName)
            == ["Apple Watch", "Cronometer", "MyFitnessPal"])
        #expect(contributions.supplying(.sleep).map(\.sourceName) == ["Fitbit (Google Health)"])
        #expect(contributions.supplying(.fitness).map(\.sourceName)
            == ["Fitbit (Google Health)", "Strava"])
    }

    @Test func alwaysPresentMetricsSpanTheWholePeriod() throws {
        // Steps, sleep and resting heart rate are seeded for every one of the 92 days.
        let fitbit = try source("Fitbit (Google Health)")
        #expect(fitbit.dataTypes.allSatisfy { $0.dayCount == 92 })
        #expect(try source("Apple Watch").dataTypes[0].dayCount == 92)

        // Workouts are occasional, so Strava must report fewer days than the full span.
        let strava = try source("Strava").dataTypes[0]
        #expect(strava.dayCount > 0 && strava.dayCount < 92)
    }

    @Test func contributionsCarryDateRangeAndLatestValue() throws {
        let sleep = try #require(try source("Fitbit (Google Health)").dataTypes(in: .sleep).first)
        let first = try #require(sleep.firstDay)
        let last = try #require(sleep.lastDay)
        #expect(first < last)
        let latest = try #require(sleep.latestValue)
        #expect(latest > 3 && latest < 12)
        // Formatting is unit-aware: hours render with one decimal and an "h" suffix.
        #expect(sleep.formattedLatest?.hasSuffix(" h") == true)
    }

    @Test func emptyMetricsProduceNoSources() {
        #expect(SourceContribution.from(metrics: []).isEmpty)
    }

    @Test func everyMetricKindMapsToACategory() {
        // Guards against a new MetricKind being added without a category, which would
        // silently hide it from every Connections screen.
        for kind in MetricKind.allCases {
            #expect(HealthDataCategory.allCases.contains(kind.category))
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.formatted(1).isEmpty)
        }
    }
}
