import Foundation
import HealthCore

final class CompositeHealthProvider: HealthDataProvider, @unchecked Sendable {
    private let healthKit: HealthKitProvider
    private let local: LocalMetricStore
    private let airQuality: AirQualityHistoryStore?
    private let includeHealthKitData: Bool

    init(
        healthKit: HealthKitProvider,
        local: LocalMetricStore,
        airQuality: AirQualityHistoryStore? = nil,
        includeHealthKitData: Bool = true
    ) {
        self.healthKit = healthKit
        self.local = local
        self.airQuality = airQuality
        self.includeHealthKitData = includeHealthKitData
    }

    func requestAuthorization() async throws {
        try await healthKit.requestAuthorization()
    }

    func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetrics] {
        let healthKitMetrics = includeHealthKitData
            ? ((try? await healthKit.dailyMetrics(from: start, to: end)) ?? [])
            : []
        let manual = await MainActor.run {
            ManualMetrics.dailyMetrics(from: local.entries(from: start, to: end))
        }
        let merged = DailyMetrics.merge(primary: healthKitMetrics, overrides: manual)
        let peaks = await MainActor.run {
            airQuality?.peaks(from: start, to: end) ?? [:]
        }
        let calendar = Calendar.current
        var byDay = Dictionary(
            merged.map { (calendar.startOfDay(for: $0.date), $0) },
            uniquingKeysWith: { _, last in last }
        )
        for (day, peakAQI) in peaks {
            let day = calendar.startOfDay(for: day)
            if var metrics = byDay[day] {
                if metrics.peakAQI == nil { metrics.peakAQI = peakAQI }
                byDay[day] = metrics
            } else {
                byDay[day] = DailyMetrics(date: day, peakAQI: peakAQI)
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    func contributingSources() async throws -> [String] {
        var sources = includeHealthKitData
            ? ((try? await healthKit.contributingSources()) ?? [])
            : []
        let hasManualEntries = await MainActor.run { !local.allEntries().isEmpty }
        if hasManualEntries, !sources.contains(ManualMetrics.sourceName) {
            sources.append(ManualMetrics.sourceName)
        }
        return sources
    }

    func sourceContributions() async throws -> [SourceContribution] {
        let healthKitContributions = includeHealthKitData
            ? ((try? await healthKit.sourceContributions()) ?? [])
            : []
        let manual = await MainActor.run {
            ManualMetrics.dailyMetrics(from: local.allEntries())
        }
        return healthKitContributions + SourceContribution.from(metrics: manual)
    }

    func seedDemoData(_ metrics: [DailyMetrics]) async throws {
        try await healthKit.seedDemoData(metrics)
    }
}
