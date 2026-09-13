import Foundation
import Testing
@testable import HealthCore

@Suite struct CorrelationTests {
    let reference = Date(timeIntervalSince1970: 1_760_000_000)

    var persona: AsthmaPersona.Output { AsthmaPersona.generate(reference: reference) }

    @Test func personaRanksAirQualityFirst() throws {
        let insights = Insights(events: persona.events, metrics: persona.metrics)
        let first = try #require(insights.rankedCorrelations.first)
        #expect(first.series == .airQuality)
        #expect(first.strength == .strong)
        #expect(try #require(first.lift) > 1.8)
        #expect(first.hits == 9)
        #expect(first.total == 13)
        #expect(first.dayShare == 17)
    }

    @Test func personaSleepIsCountedButWeak() throws {
        let insights = Insights(events: persona.events, metrics: persona.metrics)
        let sleep = try #require(insights.correlation(for: .metric(.sleepHours)))
        #expect(sleep.hits == 4)
        #expect(sleep.total == 13)
        #expect(sleep.strength == .weak)
        #expect(insights.rankedCorrelations.prefix(3).map(\.series).contains(.metric(.sleepHours)))
    }

    @Test func personaNutritionCoverage() throws {
        let insights = Insights(events: persona.events, metrics: persona.metrics)
        let caffeine = try #require(insights.correlation(for: .metric(.caffeineMg)))
        #expect(caffeine.coverageDays == 55)
        #expect(caffeine.totalDays == 92)
        #expect(caffeine.total == 8)
    }

    @Test func workoutsTreatMissingAsZero() throws {
        let insights = Insights(events: persona.events, metrics: persona.metrics)
        let workouts = try #require(insights.correlation(for: .metric(.workoutMinutes)))
        #expect(workouts.coverageDays == 92)
        #expect(workouts.total == 13)
        #expect(workouts.threshold == 0)
        #expect(workouts.direction == .above)
    }

    @Test func tooFewEpisodesIsInsufficientButCounted() throws {
        let calendar = Calendar.current
        let metrics = (0..<10).map { index in
            DailyMetrics(
                date: calendar.date(byAdding: .day, value: index, to: reference)!,
                peakAQI: index < 3 ? 140 : 50
            )
        }
        let events = (0..<2).map { index in event(on: metrics[index].date) }
        let correlation = try #require(Insights(events: events, metrics: metrics).correlation(for: .airQuality))
        #expect(correlation.hits == 2)
        #expect(correlation.total == 2)
        #expect(correlation.strength == .insufficient)
        #expect(correlation.lift != nil)
    }

    @Test func lowCoverageIsInsufficient() throws {
        let calendar = Calendar.current
        let metrics = (0..<20).map { index in
            DailyMetrics(
                date: calendar.date(byAdding: .day, value: index, to: reference)!,
                caffeineMg: index < 6 ? .init(100 + index, via: "Test") : nil
            )
        }
        let events = (0..<6).map { index in event(on: metrics[index].date) }
        let correlation = try #require(
            Insights(events: events, metrics: metrics).correlation(for: .metric(.caffeineMg))
        )
        #expect(correlation.strength == .insufficient)
    }

    @Test func zeroBaseRateIsInsufficient() throws {
        let calendar = Calendar.current
        let metrics = (0..<10).map { index in
            DailyMetrics(date: calendar.date(byAdding: .day, value: index, to: reference)!, peakAQI: 50)
        }
        let events = (0..<5).map { index in event(on: metrics[index].date) }
        let correlation = try #require(Insights(events: events, metrics: metrics).correlation(for: .airQuality))
        #expect(correlation.baseRate == 0)
        #expect(correlation.lift == nil)
        #expect(correlation.strength == .insufficient)
    }

    @Test func syntheticStrongBeatsNoise() throws {
        let calendar = Calendar.current
        let metrics = (0..<40).map { index in
            DailyMetrics(
                date: calendar.date(byAdding: .day, value: index, to: reference)!,
                steps: .init(index.isMultiple(of: 2) ? 5_000 : 10_000, via: "Test"),
                sleepHours: .init(7.0, via: "Test"),
                peakAQI: index < 8 ? 140 : 50
            )
        }
        let eventDays = Array(0..<8) + [8, 9]
        let events = eventDays.map { event(on: metrics[$0].date) }
        let insights = Insights(events: events, metrics: metrics)
        let ranked = insights.rankedCorrelations
        #expect(ranked.first?.series == .airQuality)
        #expect(ranked.first?.strength == .strong)
        let steps = try #require(insights.correlation(for: .metric(.steps)))
        let sleep = try #require(insights.correlation(for: .metric(.sleepHours)))
        #expect(steps.strength == .weak)
        #expect(sleep.strength == .insufficient)
        let stepIndex = try #require(ranked.firstIndex { $0.series == .metric(.steps) })
        let sleepIndex = try #require(ranked.firstIndex { $0.series == .metric(.sleepHours) })
        #expect(sleepIndex > stepIndex)
    }

    @Test func shimsMatchEngine() throws {
        let insights = Insights(events: persona.events, metrics: persona.metrics)
        let aqi = try #require(insights.highAQICorrelation)
        let sleep = try #require(insights.shortSleepCorrelation)
        #expect(aqi.onHighAQIDays == 9)
        #expect(aqi.total == 13)
        #expect(aqi.highAQIDayShare == 17)
        #expect(sleep.afterShortSleep == 4)
        #expect(sleep.total == 13)
    }

    @Test func airQualitySnapshotBeatsDailyPeak() throws {
        let calendar = Calendar.current
        let metrics = (0..<3).map { index in
            DailyMetrics(
                date: calendar.date(byAdding: .day, value: index, to: reference)!,
                sleepHours: .init(7.0, via: "Apple Watch")
            )
        }
        let events = metrics.map { day in
            event(on: day.date, aqi: 140)
        }
        let snapshotOnly = try #require(
            Insights(events: events, metrics: metrics).correlation(for: .airQuality)
        )
        #expect(snapshotOnly.hits == 3)
        #expect(snapshotOnly.total == 3)
        #expect(snapshotOnly.baseRate == nil)
        #expect(snapshotOnly.strength == .insufficient)

        let peakDay = DailyMetrics(date: reference, peakAQI: 150)
        let lowSnapshot = event(on: reference, aqi: 40)
        let overridden = try #require(
            Insights(events: [lowSnapshot], metrics: [peakDay]).correlation(for: .airQuality)
        )
        #expect(overridden.hits == 0)
    }

    @Test func weeklyBucketsPersona() {
        let points = Insights.weekly(persona.metrics, series: .airQuality)
        #expect(points.count == 13 || points.count == 14)
        #expect(points.allSatisfy { (1...7).contains($0.daysWithData) })
        #expect(points.map(\.daysWithData).reduce(0, +) == 92)
    }

    @Test func weeklyAveragesOnlyPopulatedDays() throws {
        let calendar = Calendar.current
        let weekStart = try #require(calendar.dateInterval(of: .weekOfYear, for: reference)?.start)
        let metrics = (0..<7).map { index in
            DailyMetrics(
                date: calendar.date(byAdding: .day, value: index, to: weekStart)!,
                workoutMinutes: index == 0 ? .init(30, via: "Test") : nil,
                caffeineMg: index < 3 ? .init((index + 1) * 100, via: "Test") : nil
            )
        }
        let caffeine = try #require(Insights.weekly(metrics, series: .metric(.caffeineMg)).first)
        #expect(caffeine.value == 200)
        #expect(caffeine.daysWithData == 3)
        let workouts = try #require(Insights.weekly(metrics, series: .metric(.workoutMinutes)).first)
        #expect(abs(workouts.value - 30.0 / 7.0) < 0.000_001)
        #expect(workouts.daysWithData == 7)
    }

    @Test func duplicateDaysDoNotTrap() {
        let metrics = [
            DailyMetrics(date: reference, sleepHours: .init(5.0, via: "Test")),
            DailyMetrics(date: reference, sleepHours: .init(7.0, via: "Test"))
        ]
        let insights = Insights(events: [event(on: reference)], metrics: metrics)
        #expect(insights.correlation(for: .metric(.sleepHours)) != nil)
    }

    @Test func wilsonLowerBound() {
        #expect(Correlation.wilsonLowerBound(0, 0, z: 1.96) == 0)
        let perfect = Correlation.wilsonLowerBound(13, 13, z: 1.96)
        #expect(perfect > 0.75 && perfect < 1)
        let persona = Correlation.wilsonLowerBound(9, 13, z: 1.96)
        #expect(abs(persona - 0.42) < 0.02)
    }

    private func event(on date: Date, aqi: Int? = nil) -> HealthEvent {
        HealthEvent(
            timestamp: date,
            symptom: "test",
            severity: 5,
            transcript: "test",
            source: .seeded,
            environment: aqi.map { EnvironmentSnapshot(aqi: $0, capturedAt: date) }
        )
    }
}
