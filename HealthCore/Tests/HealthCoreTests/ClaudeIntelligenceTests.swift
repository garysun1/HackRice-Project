import Foundation
import Testing
@testable import HealthCore

@Suite struct ClaudeIntelligenceTests {

    // MARK: - Offline: response parsing

    @Test func decodesExtractionResponse() throws {
        let api = """
        {"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\\"symptom\\":\\"chest tightness\\",\\"severity\\":6,\\"duration_minutes\\":60,\\"tags\\":[\\"outdoors\\"],\\"medications\\":[\\"albuterol (rescue inhaler)\\"]}"}],"stop_reason":"end_turn"}
        """.data(using: .utf8)!

        let payload: ExtractionPayload = try ClaudeIntelligence.decodeMessage(api)
        #expect(payload.symptom == "chest tightness")
        #expect(payload.severity == 6)
        #expect(payload.durationMinutes == 60)
        #expect(payload.medications == ["albuterol (rescue inhaler)"])
    }

    @Test func refusalThrows() {
        let api = """
        {"content":[],"stop_reason":"refusal"}
        """.data(using: .utf8)!
        #expect(throws: ClaudeIntelligence.ClaudeError.self) {
            let _: ExtractionPayload = try ClaudeIntelligence.decodeMessage(api)
        }
    }

    @Test func missingTextThrows() {
        let api = """
        {"content":[{"type":"thinking","thinking":"hmm"}],"stop_reason":"end_turn"}
        """.data(using: .utf8)!
        #expect(throws: ClaudeIntelligence.ClaudeError.self) {
            let _: ExtractionPayload = try ClaudeIntelligence.decodeMessage(api)
        }
    }

    // MARK: - Offline: fallback wrapper

    struct AlwaysFailing: IntelligenceService {
        struct Boom: Error {}
        func extractEvent(from transcript: String, at timestamp: Date) async throws -> HealthEvent { throw Boom() }
        func generateBriefing(events: [HealthEvent], metrics: [DailyMetrics], now: Date) async throws -> VisitBriefing { throw Boom() }
    }

    @Test func resilientFallsBackToMock() async throws {
        let resilient = ResilientIntelligence(primary: AlwaysFailing())
        let event = try await resilient.extractEvent(
            from: "Used my rescue inhaler, chest tightness after walking outside.",
            at: Date(timeIntervalSince1970: 1_760_000_000)
        )
        #expect(event.symptom == "chest tightness")  // mock's keyword extraction ran
        #expect(!event.medications.isEmpty)
    }

    // MARK: - Live (runs only when ANTHROPIC_API_KEY is set)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.hasPrefix("sk-ant") == true))
    func liveExtraction() async throws {
        let claude = ClaudeIntelligence(apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]!)
        let event = try await claude.extractEvent(
            from: "Woke up around six really short of breath, had to sit up for twenty minutes and used my inhaler twice before it eased off.",
            at: Date()
        )
        #expect(!event.symptom.isEmpty)
        #expect(event.severity >= 1 && event.severity <= 10)
        #expect(!event.medications.isEmpty)
    }
}
