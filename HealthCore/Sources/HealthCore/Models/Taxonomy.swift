import Foundation

/// Standardized vocabularies for LLM extraction. Enums for anything we
/// aggregate; freeform only where fidelity matters (symptom name, transcript).
/// Raw values are the exact strings enforced in the JSON schema.

public enum SymptomCategory: String, Codable, Sendable, CaseIterable {
    case respiratory, pain, gastrointestinal, neurological, skin, cardiovascular
    case mentalHealth = "mental_health"
    case general

    public var displayName: String {
        switch self {
        case .mentalHealth: "Mental health"
        default: rawValue.capitalized
        }
    }
}

public enum BodyRegion: String, Codable, Sendable, CaseIterable {
    case head, throat, chest, abdomen, back, arms, legs, skin, systemic

    public var displayName: String { rawValue.capitalized }

    /// Regions that render as dots on the body silhouette; `skin` and
    /// `systemic` are diffuse and render as chips beside the figure.
    public var isMappable: Bool { self != .skin && self != .systemic }

    /// Canonical dot position in unit space over the front silhouette.
    public var mapPoint: CGPoint {
        switch self {
        case .head: CGPoint(x: 0.5, y: 0.07)
        case .throat: CGPoint(x: 0.5, y: 0.165)
        case .chest: CGPoint(x: 0.5, y: 0.28)
        case .abdomen: CGPoint(x: 0.5, y: 0.42)
        case .back: CGPoint(x: 0.66, y: 0.35)
        case .arms: CGPoint(x: 0.205, y: 0.38)
        case .legs: CGPoint(x: 0.42, y: 0.75)
        case .skin, .systemic: CGPoint(x: 0.5, y: 0.5)
        }
    }
}

public enum Trigger: String, Codable, Sendable, CaseIterable {
    case exercise
    case outdoorAir = "outdoor_air"
    case allergens, stress
    case poorSleep = "poor_sleep"
    case food, weather, unknown

    public var displayName: String {
        switch self {
        case .outdoorAir: "Outdoor air"
        case .poorSleep: "Poor sleep"
        default: rawValue.capitalized
        }
    }
}

/// Deterministic completeness check: which high-value fields are missing and
/// worth ONE spoken follow-up each. Order = clinical priority. Hard cap 2.
public enum FollowUpQuestion: Equatable, Sendable {
    case medicationEffect(medication: String)
    case duration

    public var prompt: String {
        switch self {
        case .medicationEffect(let med): "Did the \(med) help?"
        case .duration: "About how long did it last?"
        }
    }

    public static func questions(for event: HealthEvent) -> [FollowUpQuestion] {
        var out: [FollowUpQuestion] = []
        if let med = event.medications.first, event.medicationHelped == nil {
            out.append(.medicationEffect(medication: med))
        }
        if event.duration == nil {
            out.append(.duration)
        }
        return Array(out.prefix(2))
    }
}
