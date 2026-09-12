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
    /// Daily peak US AQI, from the environment service.
    public var peakAQI: Int?

    public init(
        date: Date,
        steps: Metric<Int>? = nil,
        sleepHours: Metric<Double>? = nil,
        restingHeartRate: Metric<Int>? = nil,
        workoutMinutes: Metric<Int>? = nil,
        dietaryEnergyKcal: Metric<Int>? = nil,
        peakAQI: Int? = nil
    ) {
        self.date = date
        self.steps = steps
        self.sleepHours = sleepHours
        self.restingHeartRate = restingHeartRate
        self.workoutMinutes = workoutMinutes
        self.dietaryEnergyKcal = dietaryEnergyKcal
        self.peakAQI = peakAQI
    }
}
