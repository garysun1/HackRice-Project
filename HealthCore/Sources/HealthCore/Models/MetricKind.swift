import Foundation

/// The lifestyle metrics Breathing Room aggregates, as an enumerable list.
///
/// `DailyMetrics` stores these as named, individually-typed fields; this enum is the
/// iterable view of the same set. The Connections screens need to *walk* data types
/// ("what has Apple Watch imported?"), which named properties can't express.
public enum MetricKind: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case steps
    case sleepHours
    case restingHeartRate
    case workoutMinutes
    case dietaryEnergyKcal
    case caffeineMg
    case sodiumMg
    case waterML

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .steps: "Steps"
        case .sleepHours: "Sleep"
        case .restingHeartRate: "Resting heart rate"
        case .workoutMinutes: "Workouts"
        case .dietaryEnergyKcal: "Nutrition"
        case .caffeineMg: "Caffeine"
        case .sodiumMg: "Sodium"
        case .waterML: "Water"
        }
    }

    public var unitLabel: String {
        switch self {
        case .steps: "steps"
        case .sleepHours: "h"
        case .restingHeartRate: "bpm"
        case .workoutMinutes: "min"
        case .dietaryEnergyKcal: "kcal"
        case .caffeineMg, .sodiumMg: "mg"
        case .waterML: "ml"
        }
    }

    public var allowsDecimal: Bool { self == .sleepHours }

    public var inputRange: ClosedRange<Double> {
        switch self {
        case .steps: 0...100_000
        case .sleepHours: 0...24
        case .restingHeartRate: 20...250
        case .workoutMinutes: 0...1_440
        case .dietaryEnergyKcal: 0...20_000
        case .caffeineMg: 0...2_000
        case .sodiumMg, .waterML: 0...20_000
        }
    }

    public var category: HealthDataCategory {
        switch self {
        case .steps, .workoutMinutes: .fitness
        case .sleepHours: .sleep
        case .restingHeartRate, .dietaryEnergyKcal, .caffeineMg, .sodiumMg, .waterML: .general
        }
    }

    public var systemImage: String {
        switch self {
        case .steps: "figure.walk"
        case .sleepHours: "bed.double.fill"
        case .restingHeartRate: "heart.fill"
        case .workoutMinutes: "figure.run"
        case .dietaryEnergyKcal: "fork.knife"
        case .caffeineMg: "cup.and.saucer.fill"
        case .sodiumMg: "shippingbox.fill"
        case .waterML: "drop.fill"
        }
    }

    /// Renders a raw value with its unit, e.g. `8,431 steps` or `7.2 h`.
    public func formatted(_ value: Double) -> String {
        switch self {
        case .sleepHours: String(format: "%.1f h", value)
        case .steps: "\(Self.whole(value)) steps"
        case .restingHeartRate: "\(Self.whole(value)) bpm"
        case .workoutMinutes: "\(Self.whole(value)) min"
        case .dietaryEnergyKcal: "\(Self.whole(value)) kcal"
        case .caffeineMg, .sodiumMg: "\(Self.whole(value)) mg"
        case .waterML: "\(Self.whole(value)) ml"
        }
    }

    /// Grouped integer rendering. The formatter is built per call rather than cached in a
    /// `static let`, because `NumberFormatter` is not `Sendable` under Swift 6 strict checking.
    private static func whole(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }
}
