import Foundation

/// Correlation and summary statistics over the timeline — shared by the
/// briefing generator and the Trends screen.
public struct Insights: Sendable {
    public let events: [HealthEvent]
    public let metrics: [DailyMetrics]
    private let calendar: Calendar

    public init(events: [HealthEvent], metrics: [DailyMetrics], calendar: Calendar = .current) {
        self.events = events.sorted { $0.timestamp < $1.timestamp }
        self.metrics = metrics
        self.calendar = calendar
    }

    public var periodDays: Int {
        guard let first = events.first, let last = events.last else { return 0 }
        return max(calendar.dateComponents([.day], from: first.timestamp, to: last.timestamp).day ?? 0, 1)
    }

    public var meanSeverity: Double {
        guard !events.isEmpty else { return 0 }
        return Double(events.map(\.severity).reduce(0, +)) / Double(events.count)
    }

    public var severeCount: Int { events.filter { $0.severity >= 7 }.count }

    public var episodesPerWeek: Double {
        guard periodDays > 0 else { return 0 }
        return Double(events.count) / (Double(periodDays) / 7.0)
    }

    public var symptomCounts: [(symptom: String, count: Int)] {
        Dictionary(grouping: events, by: \.symptom)
            .map { (symptom: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private func metricsByDay() -> [Date: DailyMetrics] {
        Dictionary(
            metrics.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, last in last }
        )
    }

    public func correlation(for series: TrendSeries) -> Correlation? {
        guard !events.isEmpty, !metrics.isEmpty else { return nil }
        let resolvedDays = metrics.compactMap { series.value(in: $0) }
        let rule = Correlation.rule(for: series)
        let threshold: Double
        if let fixed = rule.fixed {
            threshold = fixed
        } else {
            guard !resolvedDays.isEmpty else { return nil }
            threshold = resolvedDays.sorted()[resolvedDays.count / 2]
        }

        func meetsCondition(_ value: Double) -> Bool {
            switch rule.direction {
            case .above: value > threshold
            case .below: value < threshold
            }
        }

        let byDay = metricsByDay()
        let episodeValues = events.compactMap { event in
            series.value(for: event)
                ?? byDay[calendar.startOfDay(for: event.timestamp)].flatMap { series.value(in: $0) }
        }
        guard !episodeValues.isEmpty else { return nil }
        let dayHits = resolvedDays.filter(meetsCondition).count
        let baseRate = resolvedDays.isEmpty
            ? nil
            : Double(dayHits) / Double(resolvedDays.count)

        return Correlation(
            series: series,
            direction: rule.direction,
            thresholdKind: rule.kind,
            threshold: threshold,
            hits: episodeValues.filter(meetsCondition).count,
            total: episodeValues.count,
            coverageDays: resolvedDays.count,
            totalDays: metrics.count,
            baseRate: baseRate
        )
    }

    /// Strongest first: by strength tier desc, then lift desc (nil lift last), then displayName for a stable tie-break.
    public var rankedCorrelations: [Correlation] {
        TrendSeries.allCases.compactMap { correlation(for: $0) }
            .sorted { lhs, rhs in
                if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
                switch (lhs.lift, rhs.lift) {
                case let (left?, right?) where left != right: return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.series.displayName < rhs.series.displayName
                }
            }
    }

    /// Every series with at least one day of data, ranked-correlation ones first (in that order), the rest in TrendSeries.allCases order.
    public var rankedSeries: [TrendSeries] {
        let available = TrendSeries.allCases.filter { series in
            metrics.contains { series.value(in: $0) != nil }
        }
        let ranked = rankedCorrelations.map(\.series).filter { available.contains($0) }
        return ranked + available.filter { !ranked.contains($0) }
    }

    public struct AQICorrelation: Sendable {
        public let onHighAQIDays: Int
        public let total: Int
        /// Percent of tracked days that were high-AQI, for the base-rate comparison.
        /// Nil when no day carries an AQI reading — a HealthKit-only timeline has no
        /// daily air-quality series, and quoting "0% of days" there would be a lie.
        public let highAQIDayShare: Int?
    }

    /// Episodes on days with AQI > 100, vs. the base rate of such days.
    /// Uses the event's own snapshot when present, else that day's peak AQI.
    public var highAQICorrelation: AQICorrelation? {
        guard let correlation = correlation(for: .airQuality) else { return nil }
        return AQICorrelation(
            onHighAQIDays: correlation.hits,
            total: correlation.total,
            highAQIDayShare: correlation.dayShare
        )
    }

    public struct SleepCorrelation: Sendable {
        public let afterShortSleep: Int
        public let total: Int
    }

    /// Episodes on days where the previous night's sleep was under 6 hours.
    public var shortSleepCorrelation: SleepCorrelation? {
        guard let correlation = correlation(for: .metric(.sleepHours)) else { return nil }
        return SleepCorrelation(afterShortSleep: correlation.hits, total: correlation.total)
    }
}
