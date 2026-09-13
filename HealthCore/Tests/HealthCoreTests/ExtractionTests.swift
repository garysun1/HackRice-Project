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
        // severity is patient-stated only — never inferred from the note
        #expect(event.severity == nil)
        #expect(event.source == .voice)
        // "this morning" back-dates the timestamp
        #expect(event.timestamp <= now)
        // relief not stated → follow-up-worthy
        #expect(event.medicationHelped == nil)
    }

    @Test func severityOnlyWhenPatientStated() {
        // Descriptive language alone never sets severity...
        let inferred = intelligence.extractEvent(
            from: "Really bad wheezing during my run, had to stop for 20 minutes.",
            at: now
        )
        #expect(inferred.severity == nil)
        #expect(inferred.duration == 1200)
        #expect(inferred.triggers.contains(.exercise))

        // ...an explicit self-rating in the note does.
        let selfRated = intelligence.extractEvent(from: "Wheezing on my run, maybe a 7 out of 10.", at: now)
        #expect(selfRated.severity == 7)

        // Answers to the how-bad follow-up count as self-ratings too:
        let numeric = intelligence.extractEvent(
            from: "Wheezing on my run.\nFollow-up — How bad was it?\nPatient answer: probably an 8",
            at: now
        )
        #expect(numeric.severity == 8)
        let words = intelligence.extractEvent(
            from: "Wheezing on my run.\nFollow-up — How bad was it?\nPatient answer: pretty bad honestly",
            at: now
        )
        #expect(words.severity == 6)
    }

    @Test func medicationReliefParsed() {
        let helped = intelligence.extractEvent(from: "Chest tightness, used my inhaler and it helped quickly.", at: now)
        #expect(helped.medicationHelped == true)
        let noHelp = intelligence.extractEvent(from: "Wheezing again, the inhaler didn't help this time.", at: now)
        #expect(noHelp.medicationHelped == false)
    }

    @Test func mildSymptomStaysUnrated() {
        let event = intelligence.extractEvent(from: "A slight cough tonight, nothing major.", at: now)
        #expect(event.symptom == "coughing")
        #expect(event.severity == nil)
        #expect(event.medications.isEmpty)
        #expect(event.medicationHelped == nil)
    }

    @Test func unknownSymptomFallsBack() {
        let event = intelligence.extractEvent(from: "Just feeling off today.", at: now)
        #expect(event.symptom == "general discomfort")
        #expect(event.category == .general)
        #expect(event.bodyRegion == .unspecified)
        // Unlocalized notes must lead with the location follow-up.
        #expect(FollowUpQuestion.questions(for: event).first == .bodyRegion)
    }

    @Test func nonRespiratoryRegions() {
        #expect(intelligence.extractEvent(from: "Splitting headache all day.", at: now).bodyRegion == .head)
        #expect(intelligence.extractEvent(from: "Lower back pain after lifting.", at: now).bodyRegion == .lowerBack)
        #expect(intelligence.extractEvent(from: "Twisted my right knee on the trail.", at: now).bodyRegion == .rightKnee)
        #expect(intelligence.extractEvent(from: "Sore left shoulder since the gym.", at: now).bodyRegion == .leftShoulder)
        #expect(intelligence.extractEvent(from: "Rolled my left ankle early this morning.", at: now).bodyRegion == .leftAnkle)
        #expect(intelligence.extractEvent(from: "Jaw pain when chewing.", at: now).bodyRegion == .jaw)
        // Sideless "arm" isn't a location override; rash stays diffuse (skin).
        #expect(intelligence.extractEvent(from: "Itchy rash on my arm.", at: now).bodyRegion == .skin)
    }

    @Test func legacyRegionNamesStillDecode() {
        #expect(BodyRegion.canonical(from: "systemic") == .unspecified)
        #expect(BodyRegion.canonical(from: "back") == .upperBack)
        #expect(BodyRegion.canonical(from: "left_leg") == .leftThigh)
        #expect(BodyRegion.canonical(from: "arms") == .leftUpperArm)
        #expect(BodyRegion.canonical(from: "hips") == .pelvis)
        #expect(BodyRegion.canonical(from: "no_such_region") == .unspecified)
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
        // unrated + meds with no relief info → severity leads, med second (cap 2)
        let event = intelligence.extractEvent(from: "Wheezing, used my inhaler.", at: now)
        let questions = FollowUpQuestion.questions(for: event)
        #expect(questions.count == 2)
        #expect(questions[0] == .severity)
        #expect(questions[1] == .medicationEffect(medication: "albuterol (rescue inhaler)"))

        // fully answered note (self-rated, relief + duration stated) → nothing to ask
        let complete = intelligence.extractEvent(
            from: "Wheezing for 20 minutes, about a 4 out of 10, used my inhaler and it helped.", at: now
        )
        #expect(FollowUpQuestion.questions(for: complete).isEmpty)
    }
}
