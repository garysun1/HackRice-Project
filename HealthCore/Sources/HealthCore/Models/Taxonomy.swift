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
    // Head to toe, center line first, then left/right pairs.
    case head, face, jaw, throat, chest, abdomen, pelvis
    case upperBack = "upper_back"
    case lowerBack = "lower_back"
    case leftShoulder = "left_shoulder", rightShoulder = "right_shoulder"
    case leftUpperArm = "left_upper_arm", rightUpperArm = "right_upper_arm"
    case leftElbow = "left_elbow", rightElbow = "right_elbow"
    case leftForearm = "left_forearm", rightForearm = "right_forearm"
    case leftWrist = "left_wrist", rightWrist = "right_wrist"
    case leftHand = "left_hand", rightHand = "right_hand"
    case leftThigh = "left_thigh", rightThigh = "right_thigh"
    case leftKnee = "left_knee", rightKnee = "right_knee"
    case leftShin = "left_shin", rightShin = "right_shin"
    case leftAnkle = "left_ankle", rightAnkle = "right_ankle"
    case leftFoot = "left_foot", rightFoot = "right_foot"
    case skin
    /// The note didn't make the location clear (or the symptom is whole-body,
    /// like fatigue). The record flow asks a follow-up to resolve it; if the
    /// patient can't localize it, it stays here and displays as "General".
    case unspecified

    public var displayName: String {
        switch self {
        case .unspecified: "General"
        case .pelvis: "Pelvis / hips"
        default: rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Regions that render as dots on the body figure; `skin` and
    /// `unspecified` are diffuse and render as chips beside it.
    public var isMappable: Bool { self != .skin && self != .unspecified }

    /// Resolves stored raw values, including names from earlier coarser
    /// taxonomies, so old on-device records survive the changes.
    public static func canonical(from raw: String) -> BodyRegion {
        if let region = BodyRegion(rawValue: raw) { return region }
        switch raw {
        case "back": return .upperBack
        case "hips": return .pelvis
        case "arms", "left_arm": return .leftUpperArm
        case "right_arm": return .rightUpperArm
        case "legs", "left_leg": return .leftThigh
        case "right_leg": return .rightThigh
        case "systemic": return .unspecified
        default: return .unspecified
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
    case bodyRegion
    case severity
    case medicationEffect(medication: String)
    case duration

    public var prompt: String {
        switch self {
        case .bodyRegion: "Where in your body did you feel it?"
        case .severity: "On a scale of 1 to 10, how bad was it?"
        case .medicationEffect(let med): "Did the \(med) help?"
        case .duration: "About how long did it last?"
        }
    }

    /// Contextual phrasing built from the note itself — used when the model
    /// didn't supply an on-topic question, so even the fallback isn't the
    /// same fixed sentence every time.
    public func prompt(for event: HealthEvent) -> String {
        let symptom = event.symptom == "general discomfort" ? "" : event.symptom
        switch self {
        case .bodyRegion:
            return symptom.isEmpty ? "Where in your body did you feel it?" : "Where exactly was the \(symptom)?"
        case .severity:
            return symptom.isEmpty ? "How bad was it, 1 to 10?" : "How bad was the \(symptom), 1 to 10?"
        case .medicationEffect(let med):
            return "Did the \(med) help?"
        case .duration:
            return symptom.isEmpty ? "About how long did it last?" : "About how long did the \(symptom) last?"
        }
    }

    public static func questions(for event: HealthEvent) -> [FollowUpQuestion] {
        var out: [FollowUpQuestion] = []
        // Location first — it's what the body map lives on.
        if event.bodyRegion == .unspecified {
            out.append(.bodyRegion)
        }
        // Severity is patient-stated, never inferred — ask when unrated.
        if event.severity == nil {
            out.append(.severity)
        }
        if let med = event.medications.first, event.medicationHelped == nil {
            out.append(.medicationEffect(medication: med))
        }
        if event.duration == nil {
            out.append(.duration)
        }
        return Array(out.prefix(2))
    }
}
