import Foundation

/// The "AI" seam. `MockIntelligence` is deterministic keyword extraction +
/// template briefing (instant, offline); `ClaudeIntelligence` / `AzureOpenAIIntelligence`
/// do real extraction and narrative synthesis when credentials are available.
/// Async so network-backed implementations fit; MockIntelligence satisfies the
/// requirements synchronously.
public protocol IntelligenceService: Sendable {
    /// Turn a raw transcript into a structured event.
    func extractEvent(from transcript: String, at timestamp: Date) async throws -> HealthEvent
    /// Synthesize the doctor-visit briefing from the timeline + lifestyle data.
    func generateBriefing(events: [HealthEvent], metrics: [DailyMetrics], now: Date) async throws -> VisitBriefing
}

public struct MockIntelligence: IntelligenceService {

    public init() {}

    // MARK: - Extraction (v2 taxonomy)

    /// keyword → (canonical symptom, category, body region), first match wins.
    static let symptomLexicon: [(keywords: [String], label: String, category: SymptomCategory, region: BodyRegion)] = [
        (["chest tightness", "tight chest", "chest feels tight", "chest felt tight"], "chest tightness", .respiratory, .chest),
        (["shortness of breath", "short of breath", "hard to breathe", "couldn't breathe", "can't breathe", "breathless"], "shortness of breath", .respiratory, .chest),
        (["wheez"], "wheezing", .respiratory, .chest),
        (["cough"], "coughing", .respiratory, .chest),
        (["congest", "stuffy"], "congestion", .respiratory, .head),
        (["headache", "migraine"], "headache", .neurological, .head),
        (["sore throat", "throat"], "sore throat", .respiratory, .throat),
        (["stomach", "nausea", "nauseous", "cramp"], "stomach discomfort", .gastrointestinal, .abdomen),
        (["back pain", "back ache", "backache"], "back pain", .pain, .lowerBack),
        (["rash", "itch", "hives"], "skin irritation", .skin, .skin),
        (["chest pain"], "chest pain", .cardiovascular, .chest),
        (["fatigue", "exhausted", "tired"], "fatigue", .general, .unspecified),
        (["dizzy", "lightheaded"], "dizziness", .neurological, .head),
        (["anxious", "anxiety", "panic"], "anxiety", .mentalHealth, .unspecified)
    ]

    /// Explicit location phrases override the symptom's default region — this
    /// is also how spoken answers to the "where was it?" follow-up resolve
    /// offline. Longest/most specific phrases first.
    static let regionLexicon: [(keywords: [String], region: BodyRegion)] = [
        (["left shoulder"], .leftShoulder),
        (["right shoulder"], .rightShoulder),
        (["left elbow"], .leftElbow),
        (["right elbow"], .rightElbow),
        (["left forearm"], .leftForearm),
        (["right forearm"], .rightForearm),
        (["left wrist"], .leftWrist),
        (["right wrist"], .rightWrist),
        (["left hand", "left finger", "left thumb"], .leftHand),
        (["right hand", "right finger", "right thumb"], .rightHand),
        (["left arm", "left bicep"], .leftUpperArm),
        (["right arm", "right bicep"], .rightUpperArm),
        (["left knee"], .leftKnee),
        (["right knee"], .rightKnee),
        (["left thigh", "left hamstring"], .leftThigh),
        (["right thigh", "right hamstring"], .rightThigh),
        (["left shin", "left calf"], .leftShin),
        (["right shin", "right calf"], .rightShin),
        (["left ankle", "left heel"], .leftAnkle),
        (["right ankle", "right heel"], .rightAnkle),
        (["left foot", "left toe"], .leftFoot),
        (["right foot", "right toe"], .rightFoot),
        (["upper back", "between my shoulder blades"], .upperBack),
        (["lower back"], .lowerBack),
        (["hip", "pelvis", "groin"], .pelvis),
        (["stomach", "belly", "abdomen"], .abdomen),
        (["jaw"], .jaw),
        (["eye", "ear", "nose", "cheek", "face", "sinus"], .face),
        (["throat", "neck"], .throat),
        (["chest"], .chest),
        (["head", "forehead", "temple", "scalp"], .head)
    ]

    static let medicationLexicon: [(keywords: [String], label: String)] = [
        (["rescue inhaler", "albuterol", "inhaler"], "albuterol (rescue inhaler)"),
        (["flovent", "fluticasone", "controller"], "fluticasone (controller)"),
        (["ibuprofen", "advil"], "ibuprofen"),
        (["tylenol", "acetaminophen"], "acetaminophen"),
        (["antihistamine", "zyrtec", "claritin"], "antihistamine")
    ]

    static let triggerLexicon: [(keywords: [String], trigger: Trigger)] = [
        (["outside", "outdoor", "walking out", "went out", "smog", "smoke"], .outdoorAir),
        (["exercise", "run", "running", "workout", "gym", "walking", "football", "game"], .exercise),
        (["pollen", "dust", "cat", "allerg"], .allergens),
        (["stress", "anxious", "anxiety", "deadline"], .stress),
        (["didn't sleep", "no sleep", "barely slept", "tired from"], .poorSleep),
        (["ate", "eating", "food", "meal"], .food),
        (["cold air", "humid", "heat", "hot day", "weather"], .weather)
    ]

    /// Severity phrases → 1–10.
    /// Word→rating map used ONLY inside answers to the how-bad follow-up,
    /// where the words ARE the patient's self-rating.
    static let severityCues: [(keywords: [String], severity: Int)] = [
        (["worst ever", "unbearable", "emergency"], 9),
        (["worst", "severe", "terrible", "awful"], 8),
        (["really bad", "very bad", "so bad"], 7),
        (["bad", "pretty bad"], 6),
        (["moderate", "annoying"], 5),
        (["noticeable", "uncomfortable"], 4),
        (["mild", "a little", "a bit", "minor"], 3),
        (["slight", "barely", "faint", "hardly"], 2)
    ]

    /// Severity is the patient's own rating: an explicit "N out of 10" / "N/10"
    /// anywhere, or the content of an answer to the how-bad follow-up (bare
    /// number, number word, or intensity words). Never inferred from the note.
    static func parseExplicitSeverity(from text: String) -> Int? {
        if let match = text.range(of: #"(10|[1-9])\s*(?:/|out of)\s*(?:10|ten)"#, options: .regularExpression),
           let n = Int(text[match].prefix(while: \.isNumber)) {
            return min(max(n, 1), 10)
        }
        // Scan every follow-up answer line (latest stated rating wins).
        var rating: Int?
        var search = text.startIndex..<text.endIndex
        while let marker = text.range(of: "patient answer:", range: search) {
            let line = String(text[marker.upperBound...].prefix { $0 != "\n" })
            rating = Self.severityFromAnswer(line) ?? rating
            search = marker.upperBound..<text.endIndex
        }
        return rating
    }

    private static func severityFromAnswer(_ answer: String) -> Int? {
        if let match = answer.range(of: #"\b(10|[1-9])\b"#, options: .regularExpression),
           let n = Int(answer[match]) {
            return n
        }
        let words = [("ten", 10), ("nine", 9), ("eight", 8), ("seven", 7), ("six", 6),
                     ("five", 5), ("four", 4), ("three", 3), ("two", 2), ("one", 1)]
        // Word-boundary match ("honestly" must not read as "one").
        if let (_, n) = words.first(where: {
            answer.range(of: #"\b\#($0.0)\b"#, options: .regularExpression) != nil
        }) { return n }
        return severityCues.first { $0.keywords.contains { answer.contains($0) } }?.severity
    }

    public func extractEvent(from transcript: String, at timestamp: Date) -> HealthEvent {
        let text = transcript.lowercased()

        let match = Self.symptomLexicon.first { entry in
            entry.keywords.contains { text.contains($0) }
        }

        // An explicitly stated location beats the symptom's default region.
        // Word-boundary match: "early" must not read as "ear".
        let statedRegion = Self.regionLexicon.first { entry in
            entry.keywords.contains {
                text.range(of: #"\b\#($0)\b"#, options: .regularExpression) != nil
            }
        }?.region

        let medications = Self.medicationLexicon.compactMap { entry in
            entry.keywords.contains(where: { text.contains($0) }) ? entry.label : nil
        }

        let triggers = Self.triggerLexicon.compactMap { entry in
            entry.keywords.contains(where: { text.contains($0) }) ? entry.trigger : nil
        }

        // Patient-stated only — never inferred from symptom wording.
        let severity = Self.parseExplicitSeverity(from: text)

        // Medication effect, only when explicitly stated.
        var medicationHelped: Bool?
        if !medications.isEmpty {
            if text.contains("didn't help") || text.contains("did not help") || text.contains("no relief") {
                medicationHelped = false
            } else if text.contains("helped") || text.contains("eased") || text.contains("settled") || text.contains("relief") {
                medicationHelped = true
            }
        }

        var event = HealthEvent(
            timestamp: Self.applyOnset(to: timestamp, text: text),
            symptom: match?.label ?? "general discomfort",
            category: match?.category ?? .general,
            bodyRegion: statedRegion ?? match?.region ?? .unspecified,
            severity: severity,
            duration: Self.parseDuration(from: text),
            triggers: triggers,
            medications: medications,
            medicationHelped: medicationHelped,
            transcript: transcript,
            source: .voice
        )
        // Offline fallback: contextual phrasing for the top missing field.
        event.suggestedFollowUp = FollowUpQuestion.questions(for: event).first?.prompt(for: event)
        return event
    }

    /// Back-dates "this morning" / "last night" style onsets deterministically.
    static func applyOnset(to loggedAt: Date, text: String, calendar: Calendar = .current) -> Date {
        if text.contains("this morning") || text.contains("woke up") {
            let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: loggedAt)!
            return min(morning, loggedAt)
        }
        if text.contains("last night") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: loggedAt)!
            return calendar.date(bySettingHour: 22, minute: 0, second: 0, of: yesterday)!
        }
        if text.contains("yesterday") {
            return calendar.date(byAdding: .day, value: -1, to: loggedAt)!
        }
        return loggedAt
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
            var line = "\(df.string(from: event.timestamp)): \(event.symptom), \(event.severity.map { "severity \($0)/10" } ?? "severity unrated")"
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
            correlations.append("\(aqiCorr.onHighAQIDays) of \(aqiCorr.total) episodes occurred on days with AQI > 100 (only \(aqiCorr.highAQIDayShare)% of days were high-AQI).")
        }
        if let sleepCorr = insights.shortSleepCorrelation {
            correlations.append("\(sleepCorr.afterShortSleep) of \(sleepCorr.total) episodes followed nights with under 6h sleep.")
        }
        if correlations.isEmpty { correlations.append("No strong lifestyle or environmental correlations detected yet.") }

        let medMentions = sorted.filter { !$0.medications.isEmpty }.count
        var meds = medMentions > 0
            ? "Rescue medication use mentioned in \(medMentions) of \(sorted.count) episodes."
            : "No medication use recorded in this period."
        let outcomes = sorted.compactMap(\.medicationHelped)
        if !outcomes.isEmpty {
            let helped = outcomes.filter { $0 }.count
            meds += " Medication reported effective in \(helped) of \(outcomes.count) episodes with an outcome noted."
        }

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
