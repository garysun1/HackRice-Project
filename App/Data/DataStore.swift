import Foundation
import SwiftData
import HealthCore

enum DataStore {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: StoredEvent.self, configurations: config)
        } catch {
            // Schema drift during the hackathon: local cache data is disposable
            // (demo mode reseeds), so wipe the store and retry rather than crash.
            try? FileManager.default.removeItem(at: config.url)
            do {
                return try ModelContainer(for: StoredEvent.self, configurations: config)
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
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
