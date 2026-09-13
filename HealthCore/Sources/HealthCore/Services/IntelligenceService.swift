import Foundation

/// The "AI" seam. Tonight `MockIntelligence` (deterministic keyword extraction +
/// template briefing) stands in; `ClaudeIntelligence` in the app target takes over
/// when ANTHROPIC_API_KEY is provided.
public protocol IntelligenceService: Sendable {
    /// Turn a raw transcript into a structured event.
    func extractEvent(from transcript: String, at timestamp: Date) -> HealthEvent
    /// Synthesize the doctor-visit briefing from the timeline + lifestyle data.
    func generateBriefing(events: [HealthEvent], metrics: [DailyMetrics], now: Date) -> VisitBriefing
}

public struct MockIntelligence: IntelligenceService {

    public init() {}

    // MARK: - Extraction

    /// symptom keyword → canonical label, ordered by specificity (first match wins).
    static let symptomLexicon: [(keywords: [String], label: String)] = [
        (["chest tightness", "tight chest", "chest feels tight"], "chest tightness"),
        (["shortness of breath", "short of breath", "hard to breathe", "couldn't breathe", "can't breathe", "breathless"], "shortness of breath"),
        (["wheez"], "wheezing"),
        (["cough"], "coughing"),
        (["congest", "stuffy"], "congestion"),
        (["headache", "migraine"], "headache"),
        (["fatigue", "exhausted", "tired"], "fatigue"),
        (["dizzy", "lightheaded"], "dizziness"),
        (["nausea", "nauseous"], "nausea"),
        (["chest pain"], "chest pain")
    ]

    static let medicationLexicon: [(keywords: [String], label: String)] = [
        (["rescue inhaler", "albuterol", "inhaler"], "albuterol (rescue inhaler)"),
        (["flovent", "fluticasone", "controller"], "fluticasone (controller)"),
        (["ibuprofen", "advil"], "ibuprofen"),
        (["tylenol", "acetaminophen"], "acetaminophen"),
        (["antihistamine", "zyrtec", "claritin"], "antihistamine")
    ]

    static let contextTags: [(keywords: [String], tag: String)] = [
        (["outside", "outdoor", "walking out", "went out"], "outdoors"),
        (["exercise", "run", "running", "workout", "gym", "walking"], "during/after activity"),
        (["morning"], "morning"),
        (["night", "sleep", "woke up", "couldn't sleep"], "night"),
        (["work", "office", "class", "school"], "at work/school"),
        (["stress", "anxious", "anxiety"], "stress-related")
    ]

    /// Severity phrases → 1–10.
    static let severityCues: [(keywords: [String], severity: Int)] = [
        (["worst", "severe", "terrible", "unbearable", "really bad", "very bad"], 8),
        (["bad", "pretty bad", "hard to", "couldn't"], 6),
        (["moderate", "noticeable", "annoying"], 5),
        (["mild", "slight", "a little", "a bit", "minor"], 3)
    ]

    public func extractEvent(from transcript: String, at timestamp: Date) -> HealthEvent {
        let text = transcript.lowercased()

        let symptom = Self.symptomLexicon.first { entry in
            entry.keywords.contains { text.contains($0) }
        }?.label ?? "general discomfort"

        let medications = Self.medicationLexicon.compactMap { entry in
            entry.keywords.contains(where: { text.contains($0) }) ? entry.label : nil
        }

        let tags = Self.contextTags.compactMap { entry in
            entry.keywords.contains(where: { text.contains($0) }) ? entry.tag : nil
        }

        var severity = Self.severityCues.first { entry in
            entry.keywords.contains { text.contains($0) }
        }?.severity ?? 4
        // Mentioning a rescue medication implies a meaningful episode.
        if !medications.isEmpty { severity = max(severity, 5) }
        // "twice"/"multiple times" bumps it further.
        if text.contains("twice") || text.contains("multiple times") || text.contains("again") {
            severity = min(severity + 1, 10)
        }

        return HealthEvent(
            timestamp: timestamp,
            symptom: symptom,
            severity: severity,
            duration: Self.parseDuration(from: text),
            tags: tags,
            medications: medications,
            transcript: transcript,
            source: .voice
        )
    }

    /// Parses "for about an hour", "for 20 minutes", "all day".
    static func parseDuration(from text: String) -> TimeInterval? {
        if text.contains("all day") { return 8 * 3600 }
        if text.contains("all night") { return 8 * 3600 }
        let patterns: [(regex: String, unit: TimeInterval)] = [
            (#"(\d+)\s*(?:hour|hr)"#, 3600),
            (#"(\d+)\s*(?:minute|min)"#, 60)
        ]
        for (pattern, unit) in patterns {
            if let match = text.range(of: pattern, options: .regularExpression) {
                let digits = text[match].filter(\.isNumber)
                if let n = Double(digits) { return n * unit }
            }
        }
        if text.contains("half an hour") { return 1800 }
        if text.contains("an hour") || text.contains("one hour") { return 3600 }
        return nil
    }

    // MARK: - Briefing

    public func generateBriefing(events: [HealthEvent], metrics: [DailyMetrics], now: Date) -> VisitBriefing {
        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        let start = sorted.first?.timestamp ?? now
        let end = sorted.last?.timestamp ?? now
        let insights = Insights(events: sorted, metrics: metrics)

        let df = DateFormatter()
        df.dateFormat = "MMM d"

        let symptomCounts = insights.symptomCounts
        let topSymptoms = symptomCounts.prefix(3).map { "\($0.symptom) (\($0.count)×)" }.joined(separator: ", ")

        let chief = "\(sorted.count) symptom episodes over \(insights.periodDays) days, predominantly \(topSymptoms)."

        let timeline = sorted.suffix(15).map { event in
            var line = "\(df.string(from: event.timestamp)): \(event.symptom), severity \(event.severity)/10"
            if !event.medications.isEmpty { line += " — \(event.medications.joined(separator: ", "))" }
            if let aqi = event.environment?.aqi { line += " (AQI \(aqi))" }
            return line
        }

        let freq = String(
            format: "Mean severity %.1f/10; %d episodes ≥7/10; ~%.1f episodes/week.",
            insights.meanSeverity, insights.severeCount, insights.episodesPerWeek
        )

        var correlations: [String] = []
        if let aqiCorr = insights.highAQICorrelation {
            var line = "\(aqiCorr.onHighAQIDays) of \(aqiCorr.total) episodes occurred on days with AQI > 100"
            // Only claim a base rate when daily air-quality history backs it up.
            if let share = aqiCorr.highAQIDayShare {
                line += " (only \(share)% of days were high-AQI)"
            }
            correlations.append(line + ".")
        }
        if let sleepCorr = insights.shortSleepCorrelation {
            correlations.append("\(sleepCorr.afterShortSleep) of \(sleepCorr.total) episodes followed nights with under 6h sleep.")
        }
        if correlations.isEmpty { correlations.append("No strong lifestyle or environmental correlations detected yet.") }

        let medMentions = sorted.filter { !$0.medications.isEmpty }.count
        let meds = medMentions > 0
            ? "Rescue medication use mentioned in \(medMentions) of \(sorted.count) episodes."
            : "No medication use recorded in this period."

        let note = VisitBriefing.ClinicianNote(
            chiefConcerns: chief,
            episodeTimeline: timeline,
            frequencyAndSeverity: freq,
            correlations: correlations,
            medicationNotes: meds
        )

        var talkingPoints = [
            "Your symptoms happened about \(String(format: "%.1f", insights.episodesPerWeek)) times a week — mention whether that feels like more or less than before."
        ]
        if insights.highAQICorrelation != nil {
            talkingPoints.append("Most of your episodes happened on bad air-quality days — ask whether your treatment plan should account for that.")
        }
        if insights.shortSleepCorrelation != nil {
            talkingPoints.append("Episodes were more common after short nights of sleep.")
        }
        if medMentions > 0 {
            talkingPoints.append("You used your rescue medication in \(medMentions) episodes — ask if that frequency is expected.")
        }

        let questions = [
            "Given this pattern, should my controller medication change?",
            "Should I avoid outdoor activity when the AQI is above a certain level?",
            "Are there triggers here you'd want me to track more closely?"
        ]

        let patient = VisitBriefing.PatientView(
            summary: "Over the last \(insights.periodDays) days you logged \(sorted.count) episodes, mostly \(symptomCounts.first?.symptom ?? "—"). Severity averaged \(String(format: "%.1f", insights.meanSeverity))/10.",
            talkingPoints: talkingPoints,
            questions: questions
        )

        return VisitBriefing(generatedAt: now, periodStart: start, periodEnd: end, clinicianNote: note, patientView: patient)
    }
}
