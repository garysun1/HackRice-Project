import Foundation

/// A single entry on the healthspan timeline — one symptom report, captured by voice or text.
public struct HealthEvent: Identifiable, Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case voice
        case text
        case manual
        case seeded
    }

    public var id: UUID
    /// When the symptom occurred (back-dated from "this morning"-style onsets),
    /// not necessarily when it was logged.
    public var timestamp: Date
    /// Primary symptom label, e.g. "chest tightness", "wheezing".
    public var symptom: String
    /// Standardized grouping for analytics.
    public var category: SymptomCategory
    /// Standardized anatomical location for the body map.
    public var bodyRegion: BodyRegion
    /// 1 (barely noticeable) … 10 (worst imaginable).
    /// 1–10, patient-stated only — nil until they rate it (never inferred).
    public var severity: Int?
    /// How long the symptom lasted, if mentioned.
    public var duration: TimeInterval?
    /// Standardized suspected triggers.
    public var triggers: [Trigger]
    /// Medications mentioned, e.g. ["albuterol"].
    public var medications: [String]
    /// Whether the medication relieved the symptom, if stated.
    public var medicationHelped: Bool?
    /// The full transcript or typed text the event was extracted from.
    public var transcript: String
    public var source: Source
    /// Environment at capture time, if available.
    public var environment: EnvironmentSnapshot?
    /// Transient: a model-phrased spoken follow-up question targeting the most
    /// valuable missing field (nil = note is complete). Not persisted.
    public var suggestedFollowUp: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        symptom: String,
        category: SymptomCategory = .general,
        bodyRegion: BodyRegion = .unspecified,
        severity: Int? = nil,
        duration: TimeInterval? = nil,
        triggers: [Trigger] = [],
        medications: [String] = [],
        medicationHelped: Bool? = nil,
        transcript: String,
        source: Source,
        environment: EnvironmentSnapshot? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.symptom = symptom
        self.category = category
        self.bodyRegion = bodyRegion
        self.severity = severity.map { min(max($0, 1), 10) }
        self.duration = duration
        self.triggers = triggers
        self.medications = medications
        self.medicationHelped = medicationHelped
        self.transcript = transcript
        self.source = source
        self.environment = environment
    }
}
