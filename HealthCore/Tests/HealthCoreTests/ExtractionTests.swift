import Foundation
import Testing
@testable import HealthCore

@Suite struct ExtractionTests {
    let intelligence = MockIntelligence()
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func extractsInhalerEpisode() {
        let event = intelligence.extractEvent(
            from: "Used my rescue inhaler twice this morning, chest tightness after walking outside for about an hour.",
            at: now
        )
        #expect(event.symptom == "chest tightness")
        #expect(event.category == .respiratory)
        #expect(event.bodyRegion == .chest)
        #expect(event.medications == ["albuterol (rescue inhaler)"])
        #expect(event.triggers.contains(.outdoorAir))
        #expect(event.duration == 3600)
        // med mention bumps to ≥5, "twice" adds 1
        #expect(event.severity >= 6)
        #expect(event.source == .voice)
        // "this morning" back-dates the timestamp
        #expect(event.timestamp <= now)
        // relief not stated → follow-up-worthy
        #expect(event.medicationHelped == nil)
    }

    @Test func extractsWheezingWithSeverityCue() {
        let event = intelligence.extractEvent(
            from: "Really bad wheezing during my run, had to stop for 20 minutes.",
            at: now
        )
        #expect(event.symptom == "wheezing")
        #expect(event.bodyRegion == .chest)
        #expect(event.severity >= 8)
        #expect(event.duration == 1200)
        #expect(event.triggers.contains(.exercise))
    }

    @Test func medicationReliefParsed() {
        let helped = intelligence.extractEvent(from: "Chest tightness, used my inhaler and it helped quickly.", at: now)
        #expect(helped.medicationHelped == true)
        let noHelp = intelligence.extractEvent(from: "Wheezing again, the inhaler didn't help this time.", at: now)
        #expect(noHelp.medicationHelped == false)
    }

    @Test func mildSymptomGetsLowSeverity() {
        let event = intelligence.extractEvent(from: "A slight cough tonight, nothing major.", at: now)
        #expect(event.symptom == "coughing")
        #expect(event.severity <= 4)
        #expect(event.medications.isEmpty)
        #expect(event.medicationHelped == nil)
    }

    @Test func unknownSymptomFallsBack() {
        let event = intelligence.extractEvent(from: "Just feeling off today.", at: now)
        #expect(event.symptom == "general discomfort")
        #expect(event.category == .general)
        #expect(event.bodyRegion == .systemic)
    }

    @Test func nonRespiratoryRegions() {
        #expect(intelligence.extractEvent(from: "Splitting headache all day.", at: now).bodyRegion == .head)
        #expect(intelligence.extractEvent(from: "Lower back pain after lifting.", at: now).bodyRegion == .back)
        #expect(intelligence.extractEvent(from: "Itchy rash on my arm.", at: now).bodyRegion == .skin)
    }

    @Test func parsesDurations() {
        #expect(MockIntelligence.parseDuration(from: "lasted about 2 hours") == 7200)
        #expect(MockIntelligence.parseDuration(from: "for 45 minutes or so") == 2700)
        #expect(MockIntelligence.parseDuration(from: "half an hour roughly") == 1800)
        #expect(MockIntelligence.parseDuration(from: "it went on all day") == 28800.0)
        #expect(MockIntelligence.parseDuration(from: "no time mentioned") == nil)
    }

    @Test func onsetBackdating() {
        let calendar = Calendar.current
        let evening = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: now)!
        let morning = MockIntelligence.applyOnset(to: evening, text: "woke up short of breath this morning")
        #expect(calendar.component(.hour, from: morning) == 8)
        let lastNight = MockIntelligence.applyOnset(to: evening, text: "coughing fit last night")
        #expect(lastNight < calendar.startOfDay(for: evening))
    }

    @Test func followUpQuestions() {
        // meds mentioned, no relief info, no duration → both questions, med first
        let event = intelligence.extractEvent(from: "Wheezing, used my inhaler.", at: now)
        let questions = FollowUpQuestion.questions(for: event)
        #expect(questions.count == 2)
        #expect(questions[0] == .medicationEffect(medication: "albuterol (rescue inhaler)"))
        #expect(questions[1] == .duration)

        // complete note → no questions
        let complete = intelligence.extractEvent(
            from: "Wheezing for 20 minutes, used my inhaler and it helped.", at: now
        )
        #expect(FollowUpQuestion.questions(for: complete).isEmpty)
    }
}
