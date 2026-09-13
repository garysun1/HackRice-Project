import Foundation

/// One day of lifestyle data aggregated from HealthKit (or the mock provider).
/// Each metric carries the name of the app/device that contributed it so the UI
/// can show honest source-attribution badges ("Steps via Fitbit (Google Health)").
public struct DailyMetrics: Identifiable, Codable, Hashable, Sendable {
    public struct Metric<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        public var value: Value
        /// Contributing app/device, from HKSourceRevision (e.g. "Google Health", "Strava").
        public var sourceName: String

        public init(_ value: Value, via sourceName: String) {
            self.value = value
            self.sourceName = sourceName
        }
    }

    public var id: Date { date }
    /// Start of day, in the user's calendar.
    public var date: Date
    public var steps: Metric<Int>?
    public var sleepHours: Metric<Double>?
    public var restingHeartRate: Metric<Int>?
    /// Workout minutes across all sources.
    public var workoutMinutes: Metric<Int>?
    /// Dietary energy in kilocalories (e.g. from MyFitnessPal).
    public var dietaryEnergyKcal: Metric<Int>?
    /// Caffeine in mg (MyFitnessPal, Cronometer) — a sleep-quality driver.
    public var caffeineMg: Metric<Int>?
    /// Sodium in mg (MyFitnessPal, Cronometer).
    public var sodiumMg: Metric<Int>?
    /// Water intake in millilitres.
    public var waterML: Metric<Int>?
    /// Daily peak US AQI, from the environment service.
    public var peakAQI: Int?

    public init(
        date: Date,
        steps: Metric<Int>? = nil,
        sleepHours: Metric<Double>? = nil,
        restingHeartRate: Metric<Int>? = nil,
        workoutMinutes: Metric<Int>? = nil,
        dietaryEnergyKcal: Metric<Int>? = nil,
        caffeineMg: Metric<Int>? = nil,
        sodiumMg: Metric<Int>? = nil,
        waterML: Metric<Int>? = nil,
        peakAQI: Int? = nil
    ) {
        self.date = date
        self.steps = steps
        self.sleepHours = sleepHours
        self.restingHeartRate = restingHeartRate
        self.workoutMinutes = workoutMinutes
        self.dietaryEnergyKcal = dietaryEnergyKcal
        self.caffeineMg = caffeineMg
        self.sodiumMg = sodiumMg
        self.waterML = waterML
        self.peakAQI = peakAQI
    }

    /// Every populated metric on this day as `(kind, value, source)`.
    ///
    /// The single place that bridges the named fields above to `MetricKind`. Adding a
    /// metric means adding a field, an enum case, and one line here — after which it
    /// flows through attribution, Connections, and the per-source detail screens for free.
    public var entries: [(kind: MetricKind, value: Double, sourceName: String)] {
        var out: [(MetricKind, Double, String)] = []
        if let m = steps { out.append((.steps, Double(m.value), m.sourceName)) }
        if let m = sleepHours { out.append((.sleepHours, m.value, m.sourceName)) }
        if let m = restingHeartRate { out.append((.restingHeartRate, Double(m.value), m.sourceName)) }
        if let m = workoutMinutes { out.append((.workoutMinutes, Double(m.value), m.sourceName)) }
        if let m = dietaryEnergyKcal { out.append((.dietaryEnergyKcal, Double(m.value), m.sourceName)) }
        if let m = caffeineMg { out.append((.caffeineMg, Double(m.value), m.sourceName)) }
        if let m = sodiumMg { out.append((.sodiumMg, Double(m.value), m.sourceName)) }
        if let m = waterML { out.append((.waterML, Double(m.value), m.sourceName)) }
        return out
    }

    public func value(for series: TrendSeries) -> Double? {
        switch series {
        case .airQuality: peakAQI.map(Double.init)
        case .metric(let kind): entries.first { $0.kind == kind }?.value
        }
    }

    /// Every populated metric paired with the app/device that supplied it.
    public var attributedMetrics: [(label: String, sourceName: String)] {
        entries.map { (label: $0.kind.displayName, sourceName: $0.sourceName) }
    }
}
