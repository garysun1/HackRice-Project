import Foundation
import SwiftData
import HealthCore

enum DataStore {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(
                for: StoredEvent.self,
                StoredDailyMetric.self,
                StoredDailyAQI.self,
                configurations: config
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    @MainActor
    static func removeSeededEvents(context: ModelContext) {
        let descriptor = FetchDescriptor<StoredEvent>(
            predicate: #Predicate { $0.sourceRaw == "seeded" }
        )
        guard let events = try? context.fetch(descriptor), !events.isEmpty else { return }
        for event in events {
            context.delete(event)
        }
        try? context.save()
    }

    /// In demo mode, load the seeded persona once (idempotent across launches).
    @MainActor
    static func seedIfNeeded(context: ModelContext, persona: AsthmaPersona.Output) {
        let existing = (try? context.fetchCount(FetchDescriptor<StoredEvent>())) ?? 0
        guard existing == 0 else { return }
        for event in persona.events {
            context.insert(StoredEvent(from: event))
        }
        try? context.save()
    }
}
