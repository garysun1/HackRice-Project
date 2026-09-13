import Foundation

/// Prompt content shared by all real intelligence providers (Claude, Azure OpenAI).
/// We compute the statistics; the model writes the narrative — never the reverse.
enum IntelligencePrompts {

    static let extractionSystem = """
    You extract structured health events from short patient voice notes for a personal \
    health timeline. Be faithful to what was said; do not invent details. Severity: mild \
    language ~2-3, unqualified symptoms ~4-5, rescue medication use or strong language \
    ~6-8, emergency language ~9-10.
    """

    static let briefingSystem = """
    You prepare doctor-visit briefings from a patient's between-visit health timeline. \
    Produce two views from the same facts: a clinician-style note (precise, clinical \
    register, no fluff) and a plain-language patient view (warm, actionable). Use ONLY \
    the statistics provided — do not recompute or invent numbers. episode_timeline: one \
    compact line per episode, most recent last, date as 'Mon D'. correlations: one \
    sentence per provided correlation, leading with the numbers. talking_points: 2-4 \
    items the patient should raise. questions: exactly 3 questions to ask the doctor.
    """

    /// The user-turn content for briefing generation: computed stats + episode log.
    static func briefingInput(events: [HealthEvent], metrics: [DailyMetrics]) -> String {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let insights = Insights(events: sorted, metrics: metrics)
        let df = ISO8601DateFormatter()

        var facts: [String] = [
            "Episodes: \(sorted.count) over \(insights.periodDays) days",
            String(format: "Mean severity %.1f/10; %d episodes >=7/10; %.1f episodes/week", insights.meanSeverity, insights.severeCount, insights.episodesPerWeek),
            "Symptom counts: " + insights.symptomCounts.map { "\($0.symptom) x\($0.count)" }.joined(separator: ", ")
        ]
        if let c = insights.highAQICorrelation {
            facts.append("\(c.onHighAQIDays) of \(c.total) episodes occurred on days with AQI > 100, while only \(c.highAQIDayShare)% of tracked days were high-AQI")
        }
        if let s = insights.shortSleepCorrelation {
            facts.append("\(s.afterShortSleep) of \(s.total) episodes followed nights with under 6h sleep")
        }
        let medMentions = sorted.filter { !$0.medications.isEmpty }.count
        facts.append("Rescue/medication use mentioned in \(medMentions) of \(sorted.count) episodes")

        let episodeLines = sorted.suffix(20).map { e in
            var line = "\(df.string(from: e.timestamp)): \(e.symptom), severity \(e.severity)/10"
            if !e.medications.isEmpty { line += ", meds: \(e.medications.joined(separator: "; "))" }
            if let aqi = e.environment?.aqi { line += ", AQI \(aqi)" }
            if !e.tags.isEmpty { line += ", context: \(e.tags.joined(separator: "; "))" }
            line += " — \"\(e.transcript)\""
            return line
        }.joined(separator: "\n")

        return "COMPUTED STATISTICS:\n\(facts.joined(separator: "\n"))\n\nEPISODES:\n\(episodeLines)"
    }

    /// JSON schema for event extraction (shared shape; both APIs accept standard JSON Schema).
    /// Computed (not stored) to satisfy Swift 6 strict concurrency for [String: Any].
    static var extractionSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "symptom": ["type": "string", "description": "Primary symptom in 1-3 lowercase words, e.g. 'chest tightness'"],
            "severity": ["type": "integer", "description": "1 (barely noticeable) to 10 (worst imaginable), judged from language and medication use"],
            "duration_minutes": ["type": ["integer", "null"], "description": "How long the symptom lasted, if stated"],
            "tags": ["type": "array", "items": ["type": "string"], "description": "Short context tags like 'outdoors', 'morning', 'during/after activity', 'stress-related'"],
            "medications": ["type": "array", "items": ["type": "string"], "description": "Medications mentioned, normalized, e.g. 'albuterol (rescue inhaler)'"]
        ],
        "required": ["symptom", "severity", "duration_minutes", "tags", "medications"],
        "additionalProperties": false
    ] }

    /// JSON schema for the dual-view briefing.
    static var briefingSchema: [String: Any] {
        let stringArray: [String: Any] = ["type": "array", "items": ["type": "string"]]
        return [
            "type": "object",
            "properties": [
                "chief_concerns": ["type": "string"],
                "episode_timeline": stringArray,
                "frequency_and_severity": ["type": "string"],
                "correlations": stringArray,
                "medication_notes": ["type": "string"],
                "patient_summary": ["type": "string"],
                "talking_points": stringArray,
                "questions": stringArray
            ],
            "required": ["chief_concerns", "episode_timeline", "frequency_and_severity", "correlations", "medication_notes", "patient_summary", "talking_points", "questions"],
            "additionalProperties": false
        ]
    }
}

/// Shared decodable payloads for both providers.
struct ExtractionPayload: Decodable {
    let symptom: String
    let severity: Int
    let durationMinutes: Int?
    let tags: [String]
    let medications: [String]

    enum CodingKeys: String, CodingKey {
        case symptom, severity, tags, medications
        case durationMinutes = "duration_minutes"
    }

    func toEvent(transcript: String, at timestamp: Date) -> HealthEvent {
        HealthEvent(
            timestamp: timestamp,
            symptom: symptom,
            severity: severity,
            duration: durationMinutes.map { TimeInterval($0 * 60) },
            tags: tags,
            medications: medications,
            transcript: transcript,
            source: .voice
        )
    }
}

struct BriefingPayload: Decodable {
    let chiefConcerns: String
    let episodeTimeline: [String]
    let frequencyAndSeverity: String
    let correlations: [String]
    let medicationNotes: String
    let patientSummary: String
    let talkingPoints: [String]
    let questions: [String]

    enum CodingKeys: String, CodingKey {
        case chiefConcerns = "chief_concerns"
        case episodeTimeline = "episode_timeline"
        case frequencyAndSeverity = "frequency_and_severity"
        case correlations
        case medicationNotes = "medication_notes"
        case patientSummary = "patient_summary"
        case talkingPoints = "talking_points"
        case questions
    }

    func toBriefing(events: [HealthEvent], now: Date) -> VisitBriefing {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        return VisitBriefing(
            generatedAt: now,
            periodStart: sorted.first?.timestamp ?? now,
            periodEnd: sorted.last?.timestamp ?? now,
            clinicianNote: .init(
                chiefConcerns: chiefConcerns,
                episodeTimeline: episodeTimeline,
                frequencyAndSeverity: frequencyAndSeverity,
                correlations: correlations,
                medicationNotes: medicationNotes
            ),
            patientView: .init(
                summary: patientSummary,
                talkingPoints: talkingPoints,
                questions: questions
            )
        )
    }
}
