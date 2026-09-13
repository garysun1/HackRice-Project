import Foundation

/// Prompt content shared by all real intelligence providers (Claude, Azure OpenAI).
/// We compute the statistics; the model writes the narrative — never the reverse.
enum IntelligencePrompts {

    static let extractionSystem = """
    You extract structured health events from short patient voice notes for a personal \
    health timeline. Be faithful to what was said; do not invent details. severity: \
    NEVER infer it from symptom wording — it is the patient's own rating. Set it only \
    when they explicitly self-rate: a number ("a 7", "8 out of 10") or an answer to a \
    how-bad follow-up (map word answers like "pretty bad" or "barely noticed it" onto \
    1-10). Otherwise null and the app will ask. body_region: the most specific region the note \
    supports; use left/right only when the side is stated — if a limb symptom has no \
    side ("my knee hurts"), or the location is unstated, or the symptom is whole-body \
    (fatigue, anxiety), return null and the app will ask. onset_hours_ago: convert phrases like "this morning" \
    or "last night" into hours before the current time provided; null if the event is \
    happening now or no time is stated. medication_helped: only true/false when relief or \
    lack of relief is explicitly stated, else null. Follow-up Q/A pairs appended to a note \
    refine the same single event. follow_up_question: ONE short spoken question (under 15 \
    words, natural conversational phrasing referencing what they said). Pick the target \
    by this STRICT order — do not skip ahead: (1) if body_region is null, ask where (or \
    which side, for a sideless limb symptom); (2) else if severity is null, you MUST ask \
    how bad it was on a 1-to-10 scale, tied to their words ("How bad was the tightness, \
    1 to 10?") — never ask about medication or anything else while severity is null; \
    (3) else if medication_helped is null and a medication was mentioned, ask whether it \
    helped; (4) else if duration is null, ask how long it lasted. null ONLY when every \
    one of those fields is filled or the patient already declined to answer it.
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

    /// User-turn content for extraction: the transcript plus the reference time
    /// the model needs to resolve relative onsets.
    static func extractionInput(transcript: String, now: Date) -> String {
        let df = ISO8601DateFormatter()
        return "Current time: \(df.string(from: now))\n\nVoice note:\n\(transcript)"
    }

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
        let medOutcomes = sorted.compactMap(\.medicationHelped)
        if !medOutcomes.isEmpty {
            let helped = medOutcomes.filter { $0 }.count
            facts.append("Of \(medOutcomes.count) episodes with medication outcome reported, medication helped in \(helped)")
        }

        let episodeLines = sorted.suffix(20).map { e in
            var line = "\(df.string(from: e.timestamp)): \(e.symptom) (\(e.category.rawValue), \(e.bodyRegion.rawValue)), \(e.severity.map { "severity \($0)/10" } ?? "severity unrated")"
            if !e.medications.isEmpty {
                line += ", meds: \(e.medications.joined(separator: "; "))"
                if let helped = e.medicationHelped { line += helped ? " (helped)" : " (did not help)" }
            }
            if let aqi = e.environment?.aqi { line += ", AQI \(aqi)" }
            if !e.triggers.isEmpty { line += ", triggers: \(e.triggers.map(\.rawValue).joined(separator: "; "))" }
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
            "symptom_category": ["type": "string", "enum": SymptomCategory.allCases.map(\.rawValue)],
            "body_region": [
                "type": ["string", "null"],
                "enum": BodyRegion.allCases.filter { $0 != .unspecified }.map(\.rawValue) as [Any] + [NSNull()],
                "description": "Most specific anatomical location; null when unclear, side unstated, or whole-body"
            ],
            "severity": ["type": ["integer", "null"], "description": "1-10 ONLY when the patient explicitly self-rates or answers a how-bad follow-up; null otherwise — never inferred from wording"],
            "onset_hours_ago": ["type": ["number", "null"], "description": "Hours before current time the symptom started, resolved from phrases like 'this morning'; null if now/unstated"],
            "duration_minutes": ["type": ["integer", "null"], "description": "How long the symptom lasted, if stated"],
            "triggers": ["type": "array", "items": ["type": "string", "enum": Trigger.allCases.map(\.rawValue)], "description": "Suspected triggers actually indicated by the note"],
            "medications": ["type": "array", "items": ["type": "string"], "description": "Medications mentioned, normalized, e.g. 'albuterol (rescue inhaler)'"],
            "medication_helped": ["type": ["boolean", "null"], "description": "true/false only if relief or lack of relief is explicitly stated"],
            "follow_up_question": ["type": ["string", "null"], "description": "One concise spoken follow-up (<15 words) for the most valuable missing field, or null"]
        ],
        "required": ["symptom", "symptom_category", "body_region", "severity", "onset_hours_ago", "duration_minutes", "triggers", "medications", "medication_helped", "follow_up_question"],
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
    let symptomCategory: String
    let bodyRegion: String?
    let severity: Int?
    let onsetHoursAgo: Double?
    let durationMinutes: Int?
    let triggers: [String]
    let medications: [String]
    let medicationHelped: Bool?
    let followUpQuestion: String?

    enum CodingKeys: String, CodingKey {
        case symptom, severity, triggers, medications
        case symptomCategory = "symptom_category"
        case bodyRegion = "body_region"
        case onsetHoursAgo = "onset_hours_ago"
        case durationMinutes = "duration_minutes"
        case medicationHelped = "medication_helped"
        case followUpQuestion = "follow_up_question"
    }

    func toEvent(transcript: String, loggedAt: Date) -> HealthEvent {
        let occurred = onsetHoursAgo.map { loggedAt.addingTimeInterval(-$0 * 3600) } ?? loggedAt
        // The model occasionally guesses a side while simultaneously asking
        // which side it was — trust the question: if it's still asking about
        // the side, the location isn't resolved yet.
        let questionAsksSide = followUpQuestion.map {
            let q = $0.lowercased()
            return q.contains("which side") || q.contains("left or right")
        } ?? false
        var event = HealthEvent(
            timestamp: occurred,
            symptom: symptom,
            category: SymptomCategory(rawValue: symptomCategory) ?? .general,
            bodyRegion: questionAsksSide
                ? .unspecified
                : bodyRegion.map(BodyRegion.canonical(from:)) ?? .unspecified,
            severity: severity,
            duration: durationMinutes.map { TimeInterval($0 * 60) },
            triggers: triggers.compactMap(Trigger.init(rawValue:)),
            medications: medications,
            medicationHelped: medicationHelped,
            transcript: transcript,
            source: .voice
        )
        event.suggestedFollowUp = followUpQuestion
        return event
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
