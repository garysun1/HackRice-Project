import Foundation

public struct Correlation: Sendable, Hashable, Identifiable {
    public enum Direction: Sendable, Hashable {
        case above
        case below
    }

    public enum ThresholdKind: Sendable, Hashable {
        case clinical
        case personalMedian
    }

    public enum Strength: Int, Sendable, Hashable, Comparable {
        case insufficient = 0
        case weak
        case moderate
        case strong

        public static func < (lhs: Strength, rhs: Strength) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let series: TrendSeries
    public let direction: Direction
    public let thresholdKind: ThresholdKind
    public let threshold: Double
    public let hits: Int
    public let total: Int
    public let coverageDays: Int
    public let totalDays: Int
    /// Fraction of covered days meeting the condition; nil when coverageDays == 0.
    public let baseRate: Double?

    public var id: TrendSeries { series }
    public var episodeRate: Double? { total > 0 ? Double(hits) / Double(total) : nil }
    public var dayShare: Int? { baseRate.map { Int(($0 * 100).rounded()) } }
    public var lift: Double? {
        guard let episodeRate, let baseRate, baseRate != 0 else { return nil }
        return episodeRate / baseRate
    }
    public var liftLowerBound: Double? {
        guard let baseRate, baseRate != 0, total > 0 else { return nil }
        return Self.wilsonLowerBound(hits, total, z: 1.96) / baseRate
    }

    /// Classifies only potential risk factors; inverse associations remain weak.
    public var strength: Strength {
        guard total >= 3,
              let baseRate,
              baseRate != 0,
              coverageDays * 2 >= totalDays else { return .insufficient }
        guard let liftLowerBound else { return .weak }
        if liftLowerBound >= 1.5 { return .strong }
        if liftLowerBound > 1.0 { return .moderate }
        return .weak
    }

    static func wilsonLowerBound(_ successes: Int, _ sampleSize: Int, z: Double) -> Double {
        guard sampleSize > 0 else { return 0 }
        let n = Double(sampleSize)
        let proportion = Double(successes) / n
        let zSquared = z * z
        let center = proportion + zSquared / (2 * n)
        let margin = z * sqrt((proportion * (1 - proportion) + zSquared / (4 * n)) / n)
        return (center - margin) / (1 + zSquared / n)
    }

    static func rule(for series: TrendSeries) -> (
        direction: Direction,
        kind: ThresholdKind,
        fixed: Double?
    ) {
        switch series {
        case .airQuality:
            (.above, .clinical, 100)
        case .metric(.sleepHours):
            (.below, .clinical, 6)
        case .metric(.restingHeartRate), .metric(.caffeineMg), .metric(.sodiumMg),
             .metric(.dietaryEnergyKcal), .metric(.workoutMinutes):
            (.above, .personalMedian, nil)
        case .metric(.waterML), .metric(.steps):
            (.below, .personalMedian, nil)
        }
    }
}

public struct WeeklyPoint: Hashable, Sendable, Identifiable {
    public let weekStart: Date
    public let value: Double
    public let daysWithData: Int

    public var id: Date { weekStart }
}

extension Insights {
    /// Buckets by calendar week; workouts count unlogged days as zero while other missing values are skipped.
    public static func weekly(
        _ metrics: [DailyMetrics],
        series: TrendSeries,
        calendar: Calendar = .current
    ) -> [WeeklyPoint] {
        let grouped = Dictionary(grouping: metrics) { day in
            calendar.dateInterval(of: .weekOfYear, for: day.date)?.start
        }
        return grouped.compactMap { weekStart, days -> WeeklyPoint? in
            guard let weekStart else { return nil }
            let values = days.compactMap { series.value(in: $0) }
            guard !values.isEmpty else { return nil }
            return WeeklyPoint(
                weekStart: weekStart,
                value: values.reduce(0, +) / Double(values.count),
                daysWithData: values.count
            )
        }
        .sorted { $0.weekStart < $1.weekStart }
    }
}
