import Foundation

/// Abstraction over HealthKit. The app target provides `HealthKitProvider`
/// (real HKHealthStore queries with per-sample source attribution); this
/// package provides `MockHealthProvider`, which serves the seeded persona.
public protocol HealthDataProvider: Sendable {
    /// True once the user has granted read access (or immediately, for mocks).
    func requestAuthorization() async throws
    /// Daily aggregates for the given range, newest last.
    func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetrics]
    /// Distinct contributing source names seen in the data.
    func contributingSources() async throws -> [String]
    /// Per-source, per-data-type detail backing the Connections drill-down: which apps and
    /// devices supplied which metrics, over what span. Sources appear only when they are
    /// genuinely supplying data.
    func sourceContributions() async throws -> [SourceContribution]
    /// Writes seeded samples into the backing store so the real read path can be
    /// exercised on a simulator or a fresh device. No-op for stores that can't accept writes.
    func seedDemoData(_ metrics: [DailyMetrics]) async throws
}

public extension HealthDataProvider {
    func seedDemoData(_ metrics: [DailyMetrics]) async throws {}
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
        try await sourceContributions().map(\.sourceName)
    }

    public func sourceContributions() async throws -> [SourceContribution] {
        SourceContribution.from(metrics: metrics)
    }
}
