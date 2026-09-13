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

    /// Over patient-rated episodes only; unrated ones don't skew the mean.
    public var meanSeverity: Double {
        let rated = events.compactMap(\.severity)
        guard !rated.isEmpty else { return 0 }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    public var severeCount: Int { events.filter { ($0.severity ?? 0) >= 7 }.count }

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
        Dictionary(uniqueKeysWithValues: metrics.map { (calendar.startOfDay(for: $0.date), $0) })
    }

    public struct AQICorrelation: Sendable {
        public let onHighAQIDays: Int
        public let total: Int
        /// Percent of all tracked days that were high-AQI, for the base-rate comparison.
        public let highAQIDayShare: Int
    }

    /// Episodes on days with AQI > 100, vs. the base rate of such days.
    /// Uses the event's own snapshot when present, else that day's peak AQI.
    public var highAQICorrelation: AQICorrelation? {
        guard !events.isEmpty, !metrics.isEmpty else { return nil }
        let byDay = metricsByDay()
        var high = 0, counted = 0
        for event in events {
            let aqi = event.environment?.aqi ?? byDay[calendar.startOfDay(for: event.timestamp)]?.peakAQI
            guard let aqi else { continue }
            counted += 1
            if aqi > 100 { high += 1 }
        }
        guard counted > 0 else { return nil }
        let highDays = metrics.filter { ($0.peakAQI ?? 0) > 100 }.count
        let share = Int((Double(highDays) / Double(metrics.count) * 100).rounded())
        return AQICorrelation(onHighAQIDays: high, total: counted, highAQIDayShare: share)
    }

    public struct SleepCorrelation: Sendable {
        public let afterShortSleep: Int
        public let total: Int
    }

    /// Episodes on days where the previous night's sleep was under 6 hours.
    public var shortSleepCorrelation: SleepCorrelation? {
        guard !events.isEmpty, !metrics.isEmpty else { return nil }
        let byDay = metricsByDay()
        var short = 0, counted = 0
        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            guard let sleep = byDay[day]?.sleepHours?.value else { continue }
            counted += 1
            if sleep < 6.0 { short += 1 }
        }
        guard counted > 0 else { return nil }
        return SleepCorrelation(afterShortSleep: short, total: counted)
    }
}
