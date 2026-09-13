import Foundation
import Testing
@testable import HealthCore

@Suite struct AzureOpenAIIntelligenceTests {

    // MARK: - Offline: response parsing

    @Test func decodesChatCompletion() throws {
        let api = """
        {"choices":[{"message":{"content":"{\\"symptom\\":\\"wheezing\\",\\"symptom_category\\":\\"respiratory\\",\\"body_region\\":\\"chest\\",\\"severity\\":5,\\"onset_hours_ago\\":2.5,\\"duration_minutes\\":null,\\"triggers\\":[\\"outdoor_air\\"],\\"medications\\":[],\\"medication_helped\\":null}","refusal":null}}]}
        """.data(using: .utf8)!

        let payload: ExtractionPayload = try AzureOpenAIIntelligence.decodeChatCompletion(api)
        #expect(payload.symptom == "wheezing")
        #expect(payload.severity == 5)
        #expect(payload.durationMinutes == nil)
        let event = payload.toEvent(transcript: "t", loggedAt: Date(timeIntervalSince1970: 1_760_000_000))
        #expect(event.bodyRegion == .chest)
        #expect(event.triggers == [.outdoorAir])
        #expect(event.timestamp == Date(timeIntervalSince1970: 1_760_000_000 - 2.5 * 3600))
    }

    @Test func refusalThrows() {
        let api = """
        {"choices":[{"message":{"content":null,"refusal":"I can't help with that."}}]}
        """.data(using: .utf8)!
        #expect(throws: AzureOpenAIIntelligence.AzureError.self) {
            let _: ExtractionPayload = try AzureOpenAIIntelligence.decodeChatCompletion(api)
        }
    }

    @Test func emptyChoicesThrows() {
        let api = #"{"choices":[]}"#.data(using: .utf8)!
        #expect(throws: AzureOpenAIIntelligence.AzureError.self) {
            let _: ExtractionPayload = try AzureOpenAIIntelligence.decodeChatCompletion(api)
        }
    }

    // MARK: - Live (runs only when Azure credentials are set)

    static var azureConfigured: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["AZURE_OPENAI_ENDPOINT"] != nil && env["AZURE_OPENAI_KEY"] != nil && env["AZURE_OPENAI_DEPLOYMENT"] != nil
    }

    @Test(.enabled(if: azureConfigured))
    func liveExtraction() async throws {
        let env = ProcessInfo.processInfo.environment
        let azure = AzureOpenAIIntelligence(
            endpoint: URL(string: env["AZURE_OPENAI_ENDPOINT"]!)!,
            apiKey: env["AZURE_OPENAI_KEY"]!,
            deployment: env["AZURE_OPENAI_DEPLOYMENT"]!
        )
        let event = try await azure.extractEvent(
            from: "Woke up around six really short of breath, had to sit up for twenty minutes and used my inhaler twice before it eased off.",
            at: Date()
        )
        #expect(!event.symptom.isEmpty)
        // No explicit self-rating in the note → severity must stay nil (or a valid 1-10 if the model finds one)
        #expect(event.severity.map { (1...10).contains($0) } ?? true)
        #expect(!event.medications.isEmpty)
    }

    @Test(.enabled(if: azureConfigured))
    func liveBriefing() async throws {
        let env = ProcessInfo.processInfo.environment
        let azure = AzureOpenAIIntelligence(
            endpoint: URL(string: env["AZURE_OPENAI_ENDPOINT"]!)!,
            apiKey: env["AZURE_OPENAI_KEY"]!,
            deployment: env["AZURE_OPENAI_DEPLOYMENT"]!
        )
        let persona = AsthmaPersona.generate(days: 30, reference: Date())
        let briefing = try await azure.generateBriefing(events: persona.events, metrics: persona.metrics, now: Date())
        #expect(!briefing.clinicianNote.chiefConcerns.isEmpty)
        #expect(briefing.patientView.questions.count == 3)
    }
}
