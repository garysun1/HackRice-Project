import Foundation
import SwiftData
import HealthCore

/// SwiftData persistence for HealthEvent. Kept in the app layer so HealthCore
/// stays platform-pure and testable with plain `swift test`.
@Model
final class StoredEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var symptom: String
    var severity: Int
    var duration: TimeInterval?
    var tags: [String]
    var medications: [String]
    var transcript: String
    var sourceRaw: String
    var aqi: Int?
    var pm25: Double?

    init(from event: HealthEvent) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.symptom = event.symptom
        self.severity = event.severity
        self.duration = event.duration
        self.tags = event.tags
        self.medications = event.medications
        self.transcript = event.transcript
        self.sourceRaw = event.source.rawValue
        self.aqi = event.environment?.aqi
        self.pm25 = event.environment?.pm25
    }

    var asHealthEvent: HealthEvent {
        HealthEvent(
            id: id,
            timestamp: timestamp,
            symptom: symptom,
            severity: severity,
            duration: duration,
            tags: tags,
            medications: medications,
            transcript: transcript,
            source: HealthEvent.Source(rawValue: sourceRaw) ?? .text,
            environment: aqi.map { EnvironmentSnapshot(aqi: $0, pm25: pm25, capturedAt: timestamp) }
        )
    }
}
