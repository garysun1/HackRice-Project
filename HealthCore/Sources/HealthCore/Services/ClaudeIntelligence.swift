import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Real intelligence via the Claude API. Uses structured outputs (JSON schema)
/// so responses are guaranteed to decode into our models — no prose, no parse
/// failures. Wrap in `ResilientIntelligence` so a network failure falls back
/// to `MockIntelligence` instead of breaking the app.
public struct ClaudeIntelligence: IntelligenceService {
    let apiKey: String
    let session: URLSession
    /// One model string to change if we ever want to trade quality for latency.
    let model = "claude-opus-5"

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public enum ClaudeError: LocalizedError {
        case httpError(Int, String)
        case refused
        case noTextInResponse
        public var errorDescription: String? {
            switch self {
            case .httpError(let code, let body): "Claude API error \(code): \(body.prefix(200))"
            case .refused: "Claude declined this request."
            case .noTextInResponse: "Claude returned no usable text."
            }
        }
    }

    // MARK: - Extraction

    public func extractEvent(from transcript: String, at timestamp: Date) async throws -> HealthEvent {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": IntelligencePrompts.extractionSchema]],
            "system": IntelligencePrompts.extractionSystem,
            "messages": [["role": "user", "content": IntelligencePrompts.extractionInput(transcript: transcript, now: timestamp)]]
        ]

        let payload: ExtractionPayload = try await request(body: body)
        return payload.toEvent(transcript: transcript, loggedAt: timestamp)
    }

    // MARK: - Briefing

    public func generateBriefing(events: [HealthEvent], metrics: [DailyMetrics], now: Date) async throws -> VisitBriefing {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "output_config": ["format": ["type": "json_schema", "schema": IntelligencePrompts.briefingSchema]],
            "system": IntelligencePrompts.briefingSystem,
            "messages": [["role": "user", "content": IntelligencePrompts.briefingInput(events: events, metrics: metrics)]]
        ]

        let payload: BriefingPayload = try await request(body: body)
        return payload.toBriefing(events: events, now: now)
    }

    // MARK: - Transport

    func request<T: Decodable>(body: [String: Any]) async throws -> T {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ClaudeError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try Self.decodeMessage(data)
    }

    struct APIResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?
        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    /// Parses a Messages API response: checks stop_reason, finds the first text
    /// block, decodes it as T. Internal + static so it's unit-testable offline.
    static func decodeMessage<T: Decodable>(_ data: Data) throws -> T {
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        if decoded.stopReason == "refusal" { throw ClaudeError.refused }
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              let payload = text.data(using: .utf8)
        else { throw ClaudeError.noTextInResponse }
        return try JSONDecoder().decode(T.self, from: payload)
    }
}

/// Tries the primary intelligence (Claude); on any failure, falls back to the
/// deterministic mock. The demo can never die because of hotel Wi-Fi.
public struct ResilientIntelligence: IntelligenceService {
    let primary: any IntelligenceService
    let fallback: MockIntelligence

    public init(primary: any IntelligenceService, fallback: MockIntelligence = MockIntelligence()) {
        self.primary = primary
        self.fallback = fallback
    }

    public func extractEvent(from transcript: String, at timestamp: Date) async throws -> HealthEvent {
        do { return try await primary.extractEvent(from: transcript, at: timestamp) }
        catch { return fallback.extractEvent(from: transcript, at: timestamp) }
    }

    public func generateBriefing(events: [HealthEvent], metrics: [DailyMetrics], now: Date) async throws -> VisitBriefing {
        do { return try await primary.generateBriefing(events: events, metrics: metrics, now: now) }
        catch { return fallback.generateBriefing(events: events, metrics: metrics, now: now) }
    }
}
