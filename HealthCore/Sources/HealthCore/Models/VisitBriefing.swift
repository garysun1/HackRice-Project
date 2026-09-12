import Foundation

/// The "Prep my visit" output: one generator, two renderings.
/// `clinicianNote` is a structured summary meant to be shown to a doctor;
/// `patientView` is plain-language talking points for the patient.
public struct VisitBriefing: Codable, Hashable, Sendable {
    public struct ClinicianNote: Codable, Hashable, Sendable {
        /// e.g. "12 symptom episodes over 90 days, predominantly chest tightness and wheezing."
        public var chiefConcerns: String
        /// Chronological one-line episode summaries.
        public var episodeTimeline: [String]
        /// e.g. "Mean severity 5.2/10; 4 episodes ≥7/10; frequency increasing month-over-month."
        public var frequencyAndSeverity: String
        /// e.g. "9 of 12 episodes occurred on days with AQI > 100."
        public var correlations: [String]
        /// e.g. "Rescue inhaler use mentioned in 7 episodes."
        public var medicationNotes: String
    }

    public struct PatientView: Codable, Hashable, Sendable {
        /// Plain-language summary of the period.
        public var summary: String
        /// "Bring these up with your doctor."
        public var talkingPoints: [String]
        /// Suggested questions to ask.
        public var questions: [String]
    }

    public var generatedAt: Date
    /// The date range the briefing covers.
    public var periodStart: Date
    public var periodEnd: Date
    public var clinicianNote: ClinicianNote
    public var patientView: PatientView

    public init(generatedAt: Date, periodStart: Date, periodEnd: Date, clinicianNote: ClinicianNote, patientView: PatientView) {
        self.generatedAt = generatedAt
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.clinicianNote = clinicianNote
        self.patientView = patientView
    }
}
