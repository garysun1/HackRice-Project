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
    public var timestamp: Date
    /// Primary symptom label, e.g. "chest tightness", "wheezing".
    public var symptom: String
    /// 1 (barely noticeable) … 10 (worst imaginable).
    public var severity: Int
    /// How long the symptom lasted, if mentioned.
    public var duration: TimeInterval?
    /// Free-form descriptors extracted from the note, e.g. ["after exercise", "outdoors"].
    public var tags: [String]
    /// Medications mentioned, e.g. ["albuterol"].
    public var medications: [String]
    /// The full transcript or typed text the event was extracted from.
    public var transcript: String
    public var source: Source
    /// Environment at capture time, if available.
    public var environment: EnvironmentSnapshot?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        symptom: String,
        severity: Int,
        duration: TimeInterval? = nil,
        tags: [String] = [],
        medications: [String] = [],
        transcript: String,
        source: Source,
        environment: EnvironmentSnapshot? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.symptom = symptom
        self.severity = min(max(severity, 1), 10)
        self.duration = duration
        self.tags = tags
        self.medications = medications
        self.transcript = transcript
        self.source = source
        self.environment = environment
    }
}
