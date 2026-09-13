import Foundation
import HealthKit
import OSLog
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
            HKQuantityType(.dietaryCaffeine),
            HKQuantityType(.dietarySodium),
            HKQuantityType(.dietaryWater),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType()
        ]
    }

    /// Mirrors `readTypes` so `-seedHealthKit` can write the demo persona back out
    /// and have it read in again through the real query path.
    private var writeTypes: Set<HKSampleType> {
        [
            HKQuantityType(.stepCount),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.dietaryEnergyConsumed),
            HKQuantityType(.dietaryCaffeine),
            HKQuantityType(.dietarySodium),
            HKQuantityType(.dietaryWater),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType()
        ]
    }

    private static let log = Logger(subsystem: "com.hackrice.healthapp", category: "health")
    var includeWriteOnAuthorize = false

    func requestAuthorization() async throws {
        try await requestAuthorization(includeWrite: includeWriteOnAuthorize)
    }

    func requestAuthorization(includeWrite: Bool) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: includeWrite ? writeTypes : [], read: readTypes)
        let steps = store.authorizationStatus(for: HKQuantityType(.stepCount))
        let sleep = store.authorizationStatus(for: HKCategoryType(.sleepAnalysis))
        let workouts = store.authorizationStatus(for: HKObjectType.workoutType())
        Self.log.info("share auth — steps:\(steps.rawValue) sleep:\(sleep.rawValue) workouts:\(workouts.rawValue)")
    }

    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
    }

    /// Longest window we'll ask HealthKit for. Callers pass `.distantPast` to mean
    /// "everything"; taken literally that makes `HKStatisticsCollectionQuery` enumerate
    /// ~700k daily buckets and fail, which upstream `try?`s turn into a silent empty chart.
    private static let maxLookbackDays = 400

    func dailyMetrics(from requestedStart: Date, to end: Date) async throws -> [DailyMetrics] {
        let floor = Calendar.current.date(byAdding: .day, value: -Self.maxLookbackDays, to: end) ?? end
        let start = min(max(requestedStart, floor), end)

        let steps = try await dailyQuantity(.stepCount, unit: .count(), options: .cumulativeSum, from: start, to: end)
        let restingHR = try await dailyQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, from: start, to: end)
        let dietary = try await dailyQuantity(.dietaryEnergyConsumed, unit: .kilocalorie(), options: .cumulativeSum, from: start, to: end)
        let caffeine = try await dailyQuantity(.dietaryCaffeine, unit: .gramUnit(with: .milli), options: .cumulativeSum, from: start, to: end)
        let sodium = try await dailyQuantity(.dietarySodium, unit: .gramUnit(with: .milli), options: .cumulativeSum, from: start, to: end)
        let water = try await dailyQuantity(.dietaryWater, unit: .literUnit(with: .milli), options: .cumulativeSum, from: start, to: end)
        let sleep = try await dailySleepHours(from: start, to: end)
        let workouts = try await dailyWorkoutMinutes(from: start, to: end)

        var days: Set<Date> = []
        for source in [steps, restingHR, dietary, caffeine, sodium, water, sleep, workouts] {
            days.formUnion(source.keys)
        }

        // peakAQI is left nil here — air quality comes from EnvironmentService, not HealthKit.
        return days.sorted().map { day in
            DailyMetrics(
                date: day,
                steps: steps[day].map { .init(Int($0.value), via: $0.source) },
                sleepHours: sleep[day].map { .init(($0.value * 10).rounded() / 10, via: $0.source) },
                restingHeartRate: restingHR[day].map { .init(Int($0.value), via: $0.source) },
                workoutMinutes: workouts[day].map { .init(Int($0.value), via: $0.source) },
                dietaryEnergyKcal: dietary[day].map { .init(Int($0.value), via: $0.source) },
                caffeineMg: caffeine[day].map { .init(Int($0.value), via: $0.source) },
                sodiumMg: sodium[day].map { .init(Int($0.value), via: $0.source) },
                waterML: water[day].map { .init(Int($0.value), via: $0.source) }
            )
        }
    }

    func contributingSources() async throws -> [String] {
        try await sourceContributions().map(\.sourceName)
    }

    // MARK: - Per-source attribution

    /// One source's value for one metric on one day.
    private struct SourceDayValue {
        let day: Date
        let sourceName: String
        let value: Double
    }

    /// Which apps and devices supplied which metrics, and over what span.
    ///
    /// Unlike `dailyMetrics(...)`, this deliberately does not collapse multiple
    /// contributors into one name per day — that collapse is what made the old
    /// `contributingSources()` unable to say *what* a given source actually provided.
    func sourceContributions() async throws -> [SourceContribution] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -Self.maxLookbackDays, to: end) ?? end

        var byKind: [MetricKind: [SourceDayValue]] = [:]
        byKind[.steps] = try await perSourceQuantity(.stepCount, unit: .count(), options: .cumulativeSum, from: start, to: end)
        byKind[.restingHeartRate] = try await perSourceQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), options: .discreteAverage, from: start, to: end)
        byKind[.dietaryEnergyKcal] = try await perSourceQuantity(.dietaryEnergyConsumed, unit: .kilocalorie(), options: .cumulativeSum, from: start, to: end)
        byKind[.caffeineMg] = try await perSourceQuantity(.dietaryCaffeine, unit: .gramUnit(with: .milli), options: .cumulativeSum, from: start, to: end)
        byKind[.sodiumMg] = try await perSourceQuantity(.dietarySodium, unit: .gramUnit(with: .milli), options: .cumulativeSum, from: start, to: end)
        byKind[.waterML] = try await perSourceQuantity(.dietaryWater, unit: .literUnit(with: .milli), options: .cumulativeSum, from: start, to: end)
        byKind[.sleepHours] = try await perSourceSleep(from: start, to: end)
        byKind[.workoutMinutes] = try await perSourceWorkouts(from: start, to: end)

        struct Accumulator {
            var days: Set<Date> = []
            var firstDay: Date?
            var lastDay: Date?
            var latestValue: Double?
        }

        var table: [String: [MetricKind: Accumulator]] = [:]
        for (kind, values) in byKind {
            // Ascending, so the final assignment to `latestValue` really is the latest.
            for entry in values.sorted(by: { $0.day < $1.day }) {
                var accumulator = table[entry.sourceName]?[kind] ?? Accumulator()
                accumulator.days.insert(entry.day)
                if accumulator.firstDay == nil { accumulator.firstDay = entry.day }
                accumulator.lastDay = entry.day
                accumulator.latestValue = entry.value
                table[entry.sourceName, default: [:]][kind] = accumulator
            }
        }

        Self.log.info("found \(table.count) contributing source(s) in HealthKit")

        return table
            .map { sourceName, kinds in
                SourceContribution(
                    sourceName: sourceName,
                    dataTypes: MetricKind.allCases.compactMap { kind in
                        guard let accumulator = kinds[kind] else { return nil }
                        return DataTypeContribution(
                            kind: kind,
                            dayCount: accumulator.days.count,
                            firstDay: accumulator.firstDay,
                            lastDay: accumulator.lastDay,
                            latestValue: accumulator.latestValue
                        )
                    }
                )
            }
            .sorted { $0.sourceName < $1.sourceName }
    }

    /// Daily totals split per contributing source, via `.separateBySource` — which lets
    /// HealthKit do the grouping instead of us pulling every raw sample back.
    private func perSourceQuantity(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions,
        from start: Date,
        to end: Date
    ) async throws -> [SourceDayValue] {
        let type = HKQuantityType(id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        let collection: HKStatisticsCollection? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options.union(.separateBySource),
                anchorDate: Calendar.current.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: results) }
            }
            store.execute(query)
        }

        var out: [SourceDayValue] = []
        collection?.enumerateStatistics(from: start, to: end) { stats, _ in
            let day = Calendar.current.startOfDay(for: stats.startDate)
            for source in stats.sources ?? [] {
                let quantity = options.contains(.cumulativeSum)
                    ? stats.sumQuantity(for: source)
                    : stats.averageQuantity(for: source)
                guard let quantity else { continue }
                out.append(SourceDayValue(day: day, sourceName: source.name, value: quantity.doubleValue(for: unit)))
            }
        }
        return out
    }

    private func perSourceSleep(from start: Date, to end: Date) async throws -> [SourceDayValue] {
        let samples = try await samples(of: HKCategoryType(.sleepAnalysis), from: start, to: end)
        var totals: [Date: [String: Double]] = [:]
        for sample in samples {
            guard let category = sample as? HKCategorySample,
                  HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue).contains(category.value)
            else { continue }
            let day = Calendar.current.startOfDay(for: category.endDate)
            let hours = category.endDate.timeIntervalSince(category.startDate) / 3600
            let name = category.sourceRevision.source.name
            totals[day, default: [:]][name, default: 0] += hours
        }
        return totals.flatMap { day, perSource in
            perSource.map { SourceDayValue(day: day, sourceName: $0.key, value: $0.value) }
        }
    }

    private func perSourceWorkouts(from start: Date, to end: Date) async throws -> [SourceDayValue] {
        let samples = try await samples(of: HKObjectType.workoutType(), from: start, to: end)
        var totals: [Date: [String: Double]] = [:]
        for sample in samples {
            guard let workout = sample as? HKWorkout else { continue }
            let day = Calendar.current.startOfDay(for: workout.startDate)
            let name = workout.sourceRevision.source.name
            totals[day, default: [:]][name, default: 0] += workout.duration / 60
        }
        return totals.flatMap { day, perSource in
            perSource.map { SourceDayValue(day: day, sourceName: $0.key, value: $0.value) }
        }
    }

    private func samples(of type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    // MARK: - Demo seeding

    /// Writes the seeded persona into HealthKit so `-healthkit` has something to read
    /// on a simulator or fresh device. Idempotent-ish: call once per install.
    ///
    /// Caveat: HealthKit stamps every sample with *this* app as the source, so the
    /// Connections screen will credit "Breathing Room" rather than "Strava"/"Fitbit".
    /// Real attribution only appears with the real contributing apps installed.
    func seedDemoData(_ metrics: [DailyMetrics]) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Seeding twice would double every step count and calorie total, so bail out
        // if this app has already written samples. Makes `-seedHealthKit` safe to
        // leave on across relaunches during a demo.
        if try await hasSeededSamples() {
            Self.log.info("HealthKit already seeded — skipping")
            return
        }

        let calendar = Calendar.current
        var samples: [HKSample] = []

        for day in metrics {
            // Midday anchor keeps each sample inside its own day bucket.
            let noon = calendar.date(byAdding: .hour, value: 12, to: day.date) ?? day.date

            if let steps = day.steps {
                samples.append(quantity(.stepCount, unit: .count(), value: Double(steps.value), at: noon))
            }
            if let hr = day.restingHeartRate {
                samples.append(quantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), value: Double(hr.value), at: noon))
            }
            if let kcal = day.dietaryEnergyKcal {
                samples.append(quantity(.dietaryEnergyConsumed, unit: .kilocalorie(), value: Double(kcal.value), at: noon))
            }
            if let caffeine = day.caffeineMg {
                samples.append(quantity(.dietaryCaffeine, unit: .gramUnit(with: .milli), value: Double(caffeine.value), at: noon))
            }
            if let sodium = day.sodiumMg {
                samples.append(quantity(.dietarySodium, unit: .gramUnit(with: .milli), value: Double(sodium.value), at: noon))
            }
            if let water = day.waterML {
                samples.append(quantity(.dietaryWater, unit: .literUnit(with: .milli), value: Double(water.value), at: noon))
            }
            // Sleep is credited to the wake-up day by `dailySleepHours`, so the
            // sample must *end* on this day: wake at 07:00, back-date the start.
            if let sleep = day.sleepHours {
                let wake = calendar.date(byAdding: .hour, value: 7, to: day.date) ?? day.date
                let asleep = wake.addingTimeInterval(-sleep.value * 3600)
                samples.append(HKCategorySample(
                    type: HKCategoryType(.sleepAnalysis),
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: asleep,
                    end: wake
                ))
            }
        }

        Self.log.info("seeding \(samples.count) samples across \(metrics.count) days")
        try await store.save(samples)

        // Workouts have no public initializer on modern SDKs — they must be built.
        for day in metrics {
            guard let workout = day.workoutMinutes else { continue }
            let start = calendar.date(byAdding: .hour, value: 17, to: day.date) ?? day.date
            let end = start.addingTimeInterval(Double(workout.value) * 60)
            let config = HKWorkoutConfiguration()
            config.activityType = .running
            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: nil)
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        }
    }

    /// True when this app has previously written step samples of its own.
    private func hasSeededSamples() async throws -> Bool {
        let predicate = HKQuery.predicateForObjects(from: HKSource.default())
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.stepCount),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
        return !samples.isEmpty
    }

    private func quantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, value: Double, at date: Date) -> HKQuantitySample {
        HKQuantitySample(
            type: HKQuantityType(id),
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: date,
            end: date
        )
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

    /// Total workout minutes per day, credited to the day the workout started.
    /// This is what surfaces Strava, Peloton, Nike Run Club and friends by name.
    private func dailyWorkoutMinutes(from start: Date, to end: Date) async throws -> [Date: DayValue] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }

        var out: [Date: (minutes: Double, source: String)] = [:]
        for sample in samples {
            guard let workout = sample as? HKWorkout else { continue }
            let day = Calendar.current.startOfDay(for: workout.startDate)
            let minutes = workout.duration / 60
            let existing = out[day]
            // Keep the first contributor's name; days rarely mix sources.
            out[day] = ((existing?.minutes ?? 0) + minutes, existing?.source ?? workout.sourceRevision.source.name)
        }
        return out.mapValues { DayValue(value: $0.minutes, source: $0.source) }
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
