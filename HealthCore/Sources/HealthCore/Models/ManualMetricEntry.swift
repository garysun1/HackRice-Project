import Foundation

public struct ManualMetricEntry: Sendable, Hashable {
    public let day: Date
    public let kind: MetricKind
    public let value: Double

    public init(day: Date, kind: MetricKind, value: Double) {
        self.day = day
        self.kind = kind
        self.value = value
    }
}

public enum ManualMetrics {
    public static let sourceName = "Manual entry"

    /// Groups entries by calendar day into attributed daily metrics; integer-valued kinds are rounded.
    public static func dailyMetrics(
        from entries: [ManualMetricEntry],
        calendar: Calendar = .current
    ) -> [DailyMetrics] {
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.day) }
        return grouped.map { day, entries in
            var values: [MetricKind: Double] = [:]
            for entry in entries {
                values[entry.kind] = entry.value
            }
            return DailyMetrics(
                date: day,
                steps: integerMetric(values[.steps]),
                sleepHours: values[.sleepHours].map { .init($0, via: sourceName) },
                restingHeartRate: integerMetric(values[.restingHeartRate]),
                workoutMinutes: integerMetric(values[.workoutMinutes]),
                dietaryEnergyKcal: integerMetric(values[.dietaryEnergyKcal]),
                caffeineMg: integerMetric(values[.caffeineMg]),
                sodiumMg: integerMetric(values[.sodiumMg]),
                waterML: integerMetric(values[.waterML])
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func integerMetric(_ value: Double?) -> DailyMetrics.Metric<Int>? {
        value.map { .init(Int($0.rounded()), via: sourceName) }
    }
}
