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
    var categoryRaw: String = SymptomCategory.general.rawValue
    var bodyRegionRaw: String = BodyRegion.systemic.rawValue
    var severity: Int
    var duration: TimeInterval?
    var triggersRaw: [String] = []
    var medications: [String]
    var medicationHelped: Bool?
    var transcript: String
    var sourceRaw: String
    var aqi: Int?
    var pm25: Double?

    init(from event: HealthEvent) {
        self.id = event.id
        self.timestamp = event.timestamp
        self.symptom = event.symptom
        self.categoryRaw = event.category.rawValue
        self.bodyRegionRaw = event.bodyRegion.rawValue
        self.severity = event.severity
        self.duration = event.duration
        self.triggersRaw = event.triggers.map(\.rawValue)
        self.medications = event.medications
        self.medicationHelped = event.medicationHelped
        self.transcript = event.transcript
        self.sourceRaw = event.source.rawValue
        self.aqi = event.environment?.aqi
        self.pm25 = event.environment?.pm25
    }

    var bodyRegion: BodyRegion { BodyRegion(rawValue: bodyRegionRaw) ?? .systemic }
    var triggers: [Trigger] { triggersRaw.compactMap(Trigger.init(rawValue:)) }

    var asHealthEvent: HealthEvent {
        HealthEvent(
            id: id,
            timestamp: timestamp,
            symptom: symptom,
            category: SymptomCategory(rawValue: categoryRaw) ?? .general,
            bodyRegion: bodyRegion,
            severity: severity,
            duration: duration,
            triggers: triggers,
            medications: medications,
            medicationHelped: medicationHelped,
            transcript: transcript,
            source: HealthEvent.Source(rawValue: sourceRaw) ?? .text,
            environment: aqi.map { EnvironmentSnapshot(aqi: $0, pm25: pm25, capturedAt: timestamp) }
        )
    }
}
