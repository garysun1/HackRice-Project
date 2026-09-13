import Foundation

/// The three top-level groupings on the Connections screen.
public enum HealthDataCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case general
    case sleep
    case fitness

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: "General Health"
        case .sleep: "Sleep Health"
        case .fitness: "Fitness Health"
        }
    }

    public var subtitle: String {
        switch self {
        case .general: "Vitals and nutrition"
        case .sleep: "Nightly duration and quality"
        case .fitness: "Steps, workouts, and activity"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: "heart.text.square.fill"
        case .sleep: "bed.double.fill"
        case .fitness: "figure.run"
        }
    }
}

/// What a single data type from a single source has contributed to the timeline.
public struct DataTypeContribution: Sendable, Hashable, Identifiable {
    public var id: String { kind.rawValue }
    public let kind: MetricKind
    /// How many days this source supplied this metric.
    public let dayCount: Int
    public let firstDay: Date?
    public let lastDay: Date?
    /// Most recent value seen, for a "latest reading" line.
    public let latestValue: Double?

    public init(
        kind: MetricKind,
        dayCount: Int,
        firstDay: Date? = nil,
        lastDay: Date? = nil,
        latestValue: Double? = nil
    ) {
        self.kind = kind
        self.dayCount = dayCount
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.latestValue = latestValue
    }

    public var formattedLatest: String? { latestValue.map { kind.formatted($0) } }
}

/// Everything one contributing app or device has imported into Interim.
///
/// A "connection" in this app is a source detected inside Apple Health — Interim never
/// talks to Fitbit, Oura or Garmin directly, so a source exists precisely when it is
/// supplying data. Nothing here is aspirational.
public struct SourceContribution: Sendable, Hashable, Identifiable {
    public var id: String { sourceName }
    public let sourceName: String
    public let dataTypes: [DataTypeContribution]

    public init(sourceName: String, dataTypes: [DataTypeContribution]) {
        self.sourceName = sourceName
        self.dataTypes = dataTypes
    }

    public var categories: Set<HealthDataCategory> { Set(dataTypes.map(\.kind.category)) }

    public func dataTypes(in category: HealthDataCategory) -> [DataTypeContribution] {
        dataTypes.filter { $0.kind.category == category }
    }

    public var totalDays: Int { dataTypes.map(\.dayCount).max() ?? 0 }
}

public extension SourceContribution {
    /// Collapses a day-series into per-source, per-data-type contributions.
    ///
    /// This is the inverse of how `DailyMetrics` stores things: the day series is keyed by
    /// date with a source stamped on each metric, and Connections needs it keyed by source.
    static func from(metrics: [DailyMetrics]) -> [SourceContribution] {
        struct Accumulator {
            var dayCount = 0
            var firstDay: Date?
            var lastDay: Date?
            var latestValue: Double?
        }

        var table: [String: [MetricKind: Accumulator]] = [:]
        for day in metrics.sorted(by: { $0.date < $1.date }) {
            for entry in day.entries {
                var accumulator = table[entry.sourceName]?[entry.kind] ?? Accumulator()
                accumulator.dayCount += 1
                if accumulator.firstDay == nil { accumulator.firstDay = day.date }
                // Days are ascending, so the last write wins and is genuinely the latest.
                accumulator.lastDay = day.date
                accumulator.latestValue = entry.value
                table[entry.sourceName, default: [:]][entry.kind] = accumulator
            }
        }

        return table
            .map { sourceName, kinds in
                SourceContribution(
                    sourceName: sourceName,
                    // Ordered by `allCases` so the detail screen is stable across launches.
                    dataTypes: MetricKind.allCases.compactMap { kind in
                        guard let accumulator = kinds[kind] else { return nil }
                        return DataTypeContribution(
                            kind: kind,
                            dayCount: accumulator.dayCount,
                            firstDay: accumulator.firstDay,
                            lastDay: accumulator.lastDay,
                            latestValue: accumulator.latestValue
                        )
                    }
                )
            }
            .sorted { $0.sourceName < $1.sourceName }
    }
}

public extension Array where Element == SourceContribution {
    /// Sources supplying at least one metric in the given category.
    func supplying(_ category: HealthDataCategory) -> [SourceContribution] {
        filter { $0.categories.contains(category) }
    }
}
