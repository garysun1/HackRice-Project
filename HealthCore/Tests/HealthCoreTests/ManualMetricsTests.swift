import Foundation
import Testing
@testable import HealthCore

@Suite struct ManualMetricsTests {
    let reference = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func mergeOverridesPerMetricAndAddsManualDays() throws {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: reference)
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let primary = [
            DailyMetrics(
                date: firstDay,
                steps: .init(8_000, via: "Apple Health"),
                sleepHours: .init(7.5, via: "Apple Health")
            )
        ]
        let overrides = [
            DailyMetrics(date: firstDay, sleepHours: .init(5.5, via: ManualMetrics.sourceName)),
            DailyMetrics(date: secondDay, steps: .init(4_000, via: ManualMetrics.sourceName))
        ]

        let merged = DailyMetrics.merge(primary: primary, overrides: overrides, calendar: calendar)
        #expect(merged.map(\.date) == [firstDay, secondDay])
        #expect(merged[0].steps?.value == 8_000)
        #expect(merged[0].sleepHours?.value == 5.5)
        #expect(merged[0].sleepHours?.sourceName == ManualMetrics.sourceName)
        #expect(merged[1].steps?.value == 4_000)
    }

    @Test func mergeUsesOverrideAQIWhenPresent() {
        let day = Calendar.current.startOfDay(for: reference)
        let primary = [DailyMetrics(date: day, peakAQI: 80)]
        let overrideWithoutAQI = [DailyMetrics(date: day, sleepHours: .init(6.0, via: "Manual"))]
        let overrideWithAQI = [DailyMetrics(date: day, peakAQI: 140)]

        #expect(DailyMetrics.merge(primary: primary, overrides: overrideWithoutAQI)[0].peakAQI == 80)
        #expect(DailyMetrics.merge(primary: primary, overrides: overrideWithAQI)[0].peakAQI == 140)
    }

    @Test func manualEntriesGroupAndRoundIntegerMetrics() {
        let day = Calendar.current.startOfDay(for: reference)
        let metrics = ManualMetrics.dailyMetrics(from: [
            ManualMetricEntry(day: day, kind: .steps, value: 1_234.6),
            ManualMetricEntry(day: day, kind: .sleepHours, value: 5.5)
        ])

        #expect(metrics.count == 1)
        #expect(metrics[0].steps?.value == 1_235)
        #expect(metrics[0].sleepHours?.value == 5.5)
        #expect(metrics[0].entries.allSatisfy { $0.sourceName == ManualMetrics.sourceName })
    }

    @Test func manualMetricsProduceSourceContribution() throws {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: reference)
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let metrics = ManualMetrics.dailyMetrics(from: [
            ManualMetricEntry(day: firstDay, kind: .sleepHours, value: 6.0),
            ManualMetricEntry(day: secondDay, kind: .sleepHours, value: 7.0),
            ManualMetricEntry(day: secondDay, kind: .steps, value: 5_000)
        ])
        let contribution = try #require(
            SourceContribution.from(metrics: metrics).first { $0.sourceName == ManualMetrics.sourceName }
        )
        let sleep = try #require(contribution.dataTypes.first { $0.kind == .sleepHours })

        #expect(sleep.dayCount == 2)
        #expect(contribution.dataTypes.first { $0.kind == .steps }?.dayCount == 1)
    }
}
