import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real intelligence via Azure OpenAI (Chat Completions, OpenAI-compatible v1
/// endpoint) with strict JSON-schema structured outputs. Same seam and same
/// guarantees as ClaudeIntelligence; wrap in `ResilientIntelligence` so any
/// failure falls back to the deterministic mock.
public struct AzureOpenAIIntelligence: IntelligenceService {
    let endpoint: URL          // e.g. https://garysun.openai.azure.com
    let apiKey: String
    let deployment: String     // Azure deployment name, e.g. "gpt-5-mini"
    let session: URLSession

    public init(endpoint: URL, apiKey: String, deployment: String, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.deployment = deployment
        self.session = session
    }

    public enum AzureError: LocalizedError {
        case httpError(Int, String)
        case refused(String)
        case emptyResponse
        public var errorDescription: String? {
            switch self {
            case .httpError(let code, let body): "Azure OpenAI error \(code): \(body.prefix(200))"
            case .refused(let why): "Model declined: \(why)"
            case .emptyResponse: "Azure OpenAI returned no content."
            }
        }
    }

    // MARK: - IntelligenceService

    public func extractEvent(from transcript: String, at timestamp: Date) async throws -> HealthEvent {
        let body: [String: Any] = [
            "model": deployment,
            "max_completion_tokens": 2048,
            "reasoning_effort": "minimal",  // extraction is simple; speed matters on save
            "messages": [
                ["role": "system", "content": IntelligencePrompts.extractionSystem],
                ["role": "user", "content": IntelligencePrompts.extractionInput(transcript: transcript, now: timestamp)]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "health_event", "strict": true, "schema": IntelligencePrompts.extractionSchema]
            ]
        ]
        let payload: ExtractionPayload = try await request(body: body)
        return payload.toEvent(transcript: transcript, loggedAt: timestamp)
    }

    public func generateBriefing(events: [HealthEvent], metrics: [DailyMetrics], now: Date) async throws -> VisitBriefing {
        let body: [String: Any] = [
            "model": deployment,
            "max_completion_tokens": 8192,
            "reasoning_effort": "low",  // narrative over precomputed facts; keeps latency demo-friendly
            "messages": [
                ["role": "system", "content": IntelligencePrompts.briefingSystem],
                ["role": "user", "content": IntelligencePrompts.briefingInput(events: events, metrics: metrics)]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "visit_briefing", "strict": true, "schema": IntelligencePrompts.briefingSchema]
            ]
        ]
        let payload: BriefingPayload = try await request(body: body)
        return payload.toBriefing(events: events, now: now)
    }

    // MARK: - Transport

    func request<T: Decodable>(body: [String: Any]) async throws -> T {
        let url = endpoint.appendingPathComponent("openai/v1/chat/completions")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "api-key")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AzureError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.decodeChatCompletion(data)
    }

    struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
                let refusal: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }

    /// Parses a Chat Completions response: surfaces refusals, decodes the
    /// message content as T. Internal + static so it's unit-testable offline.
    static func decodeChatCompletion<T: Decodable>(_ data: Data) throws -> T {
        let decoded = try JSONDecoder().decode(Completion.self, from: data)
        guard let message = decoded.choices.first?.message else { throw AzureError.emptyResponse }
        if let refusal = message.refusal { throw AzureError.refused(refusal) }
        guard let content = message.content, let payload = content.data(using: .utf8) else {
            throw AzureError.emptyResponse
        }
        return try JSONDecoder().decode(T.self, from: payload)
    }
}
