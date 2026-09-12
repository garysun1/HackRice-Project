import Foundation
import HealthKit
import HealthCore

/// Real HealthKit read path. One integration point covers the whole ecosystem:
/// Fitbit (via Google Health sync), Strava, MyFitnessPal, sleep apps, Apple Watch —
/// they all write into HealthKit, and HKSourceRevision tells us who contributed what.
final class HealthKitProvider: HealthDataProvider, @unchecked Sendable {
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.dietaryEnergyConsumed),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType()
        ]
    }

    private var writeTypes: Set<HKSampleType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.dietaryEnergyConsumed),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRate)
        ]
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    func dailyMetrics(from start: Date, to end: Date) async throws -> [DailyMetrics] {
        let calendar = Calendar.current
        let steps = try await dailyQuantity(.stepCount, unit: .count(), options: .cumulativeSum, from: start, to: end)
        let restingHR = try await dailyQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, from: start, to: end)
        let dietary = try await dailyQuantity(.dietaryEnergyConsumed, unit: .kilocalorie(), options: .cumulativeSum, from: start, to: end)
        let sleep = try await dailySleepHours(from: start, to: end)

        var days: Set<Date> = []
        days.formUnion(steps.keys)
        days.formUnion(restingHR.keys)
        days.formUnion(dietary.keys)
        days.formUnion(sleep.keys)

        return days.sorted().map { day in
            DailyMetrics(
                date: day,
                steps: steps[day].map { .init(Int($0.value), via: $0.source) },
                sleepHours: sleep[day].map { .init(($0.value * 10).rounded() / 10, via: $0.source) },
                restingHeartRate: restingHR[day].map { .init(Int($0.value), via: $0.source) },
                dietaryEnergyKcal: dietary[day].map { .init(Int($0.value), via: $0.source) }
            )
        }
        // Note: workoutMinutes and peakAQI are filled elsewhere (workouts omitted for brevity in v1).
        _ = calendar
    }

    func contributingSources() async throws -> [String] {
        var names: Set<String> = []
        for type in [HKQuantityType(.stepCount), HKCategoryType(.sleepAnalysis), HKQuantityType(.dietaryEnergyConsumed)] as [HKSampleType] {
            let sources: Set<HKSource> = try await withCheckedThrowingContinuation { continuation in
                let query = HKSourceQuery(sampleType: type, samplePredicate: nil) { _, sources, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: sources ?? []) }
                }
                store.execute(query)
            }
            names.formUnion(sources.map(\.name))
        }
        return names.sorted()
    }

    // MARK: - Helpers

    private struct DayValue { let value: Double; let source: String }

    private func dailyQuantity(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        from start: Date,
        to end: Date
    ) async throws -> [Date: DayValue] {
        let type = HKQuantityType(id)
        let sourceName = try await primarySourceName(for: type)
        let interval = DateComponents(day: 1)
        let anchor = Calendar.current.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let collection: HKStatisticsCollection? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: results) }
            }
            store.execute(query)
        }

        var out: [Date: DayValue] = [:]
        collection?.enumerateStatistics(from: start, to: end) { stats, _ in
            let quantity = options.contains(.cumulativeSum) ? stats.sumQuantity() : stats.averageQuantity()
            if let quantity {
                out[Calendar.current.startOfDay(for: stats.startDate)] =
                    DayValue(value: quantity.doubleValue(for: unit), source: sourceName)
            }
        }
        return out
    }

    private func dailySleepHours(from start: Date, to end: Date) async throws -> [Date: DayValue] {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }

        var out: [Date: (hours: Double, source: String)] = [:]
        for sample in samples {
            guard let category = sample as? HKCategorySample,
                  HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue).contains(category.value)
            else { continue }
            // Attribute the night's sleep to the wake-up day.
            let day = Calendar.current.startOfDay(for: category.endDate)
            let hours = category.endDate.timeIntervalSince(category.startDate) / 3600
            let existing = out[day]?.hours ?? 0
            out[day] = (existing + hours, category.sourceRevision.source.name)
        }
        return out.mapValues { DayValue(value: $0.hours, source: $0.source) }
    }

    private func primarySourceName(for type: HKSampleType) async throws -> String {
        let sources: Set<HKSource> = try await withCheckedThrowingContinuation { continuation in
            let query = HKSourceQuery(sampleType: type, samplePredicate: nil) { _, sources, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: sources ?? []) }
            }
            store.execute(query)
        }
        // Prefer a non-first-party contributor for honest attribution badges.
        let thirdParty = sources.first { !$0.bundleIdentifier.hasPrefix("com.apple") }
        return thirdParty?.name ?? sources.first?.name ?? "Apple Health"
    }
}
