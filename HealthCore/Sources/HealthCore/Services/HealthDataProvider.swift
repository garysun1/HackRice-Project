import Foundation

/// Abstraction over HealthKit. The app target provides `HealthKitProvider`
/// (real HKHealthStore queries with per-sample source attribution); this
/// package provides `MockHealthProvider`, which serves the seeded persona.
public protocol HealthDataProvider: Sendable {
    /// True once the user has granted read access (or immediately, for mocks).
    func requestAuthorization() async throws
    /// Daily aggregates for the given range, newest last.
    func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetrics]
    /// Distinct contributing source names seen in the data, for the Connections screen.
    func contributingSources() async throws -> [String]
}

public final class MockHealthProvider: HealthDataProvider {
    private let metrics: [DailyMetrics]

    public init(metrics: [DailyMetrics]) {
        self.metrics = metrics
    }

    public func requestAuthorization() async throws {}

    public func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetrics] {
        metrics
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
    }

    public func contributingSources() async throws -> [String] {
        var names: Set<String> = []
        for day in metrics {
            if let m = day.steps { names.insert(m.sourceName) }
            if let m = day.sleepHours { names.insert(m.sourceName) }
            if let m = day.restingHeartRate { names.insert(m.sourceName) }
            if let m = day.workoutMinutes { names.insert(m.sourceName) }
            if let m = day.dietaryEnergyKcal { names.insert(m.sourceName) }
        }
        return names.sorted()
    }
}
