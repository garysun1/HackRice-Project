import Foundation

public enum TrendSeries: Hashable, Sendable, Identifiable, CaseIterable {
    case metric(MetricKind)
    case airQuality

    public static var allCases: [TrendSeries] {
        [.airQuality] + MetricKind.allCases.map { .metric($0) }
    }

    public var id: String {
        switch self {
        case .airQuality: "airQuality"
        case .metric(let kind): kind.rawValue
        }
    }

    public var displayName: String {
        switch self {
        case .airQuality: "Air quality"
        case .metric(let kind): kind.displayName
        }
    }

    public var systemImage: String {
        switch self {
        case .airQuality: "aqi.medium"
        case .metric(let kind): kind.systemImage
        }
    }

    public func formatted(_ value: Double) -> String {
        switch self {
        case .airQuality: "AQI \(Int(value.rounded()))"
        case .metric(let kind): kind.formatted(value)
        }
    }

    public enum PlotStyle: Sendable {
        case line
        case bar
    }

    public var plotStyle: PlotStyle {
        switch self {
        case .airQuality, .metric(.restingHeartRate), .metric(.steps): .line
        default: .bar
        }
    }

    /// True when an absent day value means "none happened" (0) rather than "not recorded".
    public var missingMeansZero: Bool {
        self == .metric(.workoutMinutes)
    }

    /// Day value with the missing-value semantics applied.
    public func value(in day: DailyMetrics) -> Double? {
        day.value(for: self) ?? (missingMeansZero ? 0 : nil)
    }

    /// Per-episode override: the event's own snapshot beats the day's aggregate.
    public func value(for event: HealthEvent) -> Double? {
        switch self {
        case .airQuality: event.environment.map { Double($0.aqi) }
        case .metric: nil
        }
    }
}
