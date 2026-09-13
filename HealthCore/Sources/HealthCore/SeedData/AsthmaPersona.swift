import Foundation

/// Deterministic 3-month demo persona: an asthma patient in Houston whose
/// episodes cluster on high-AQI days, with short sleep as a secondary trigger.
/// Same seed → identical data, so screenshots, tests, and the stage demo all agree.
public enum AsthmaPersona {

    public struct Output: Sendable {
        public let events: [HealthEvent]
        public let metrics: [DailyMetrics]
    }

    /// Generates `days` days of history ending yesterday relative to `reference`.
    public static func generate(days: Int = 92, reference: Date = Date(), seed: UInt64 = 0xC0FFEE) -> Output {
        var rng = SplitMix64(seed: seed)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: reference)

        var metrics: [DailyMetrics] = []
        var events: [HealthEvent] = []

        for offset in stride(from: days, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }

            // --- Environment: baseline Houston AQI with multi-day pollution episodes.
            // Roughly every 2 weeks a 2–4 day spike pushes AQI into 110–170.
            let cycle = offset % 14
            let inSpike = cycle < 3 && rng.chance(0.85)
            let aqi: Int = inSpike
                ? 110 + Int(rng.next(upperBound: 60))
                : 35 + Int(rng.next(upperBound: 55))

            // --- Sleep: mostly 6.5–8h, occasional short nights.
            let shortNight = rng.chance(0.2)
            let sleep = shortNight
                ? 4.5 + rng.nextDouble() * 1.2
                : 6.5 + rng.nextDouble() * 1.7

            // --- Activity.
            let steps = 4500 + Int(rng.next(upperBound: 7500))
            let workedOut = rng.chance(0.3)
            let restingHR = 62 + Int(rng.next(upperBound: 9)) + (shortNight ? 3 : 0)

            metrics.append(DailyMetrics(
                date: day,
                steps: .init(steps, via: "Fitbit (Google Health)"),
                sleepHours: .init((sleep * 10).rounded() / 10, via: "Fitbit (Google Health)"),
                restingHeartRate: .init(restingHR, via: "Apple Watch"),
                workoutMinutes: workedOut ? .init(20 + Int(rng.next(upperBound: 40)), via: "Strava") : nil,
                dietaryEnergyKcal: rng.chance(0.6) ? .init(1800 + Int(rng.next(upperBound: 700)), via: "MyFitnessPal") : nil,
                peakAQI: aqi
            ))

            // --- Episodes: probability driven by AQI and sleep (the demo's correlation).
            var pEpisode = 0.015
            if aqi > 100 { pEpisode += 0.70 }
            else if aqi > 80 { pEpisode += 0.08 }
            if sleep < 6.0 { pEpisode += 0.10 }

            guard rng.chance(pEpisode) else { continue }

            let severity: Int = {
                // 1–5 baseline with randomized environmental bumps: the AQI
                // correlation stays visible in aggregate, but individual days
                // spread across the whole 1–9 range instead of piling at 5–8.
                var s = 1 + Int(rng.next(upperBound: 5))
                if aqi > 130 { s += 2 + Int(rng.next(upperBound: 3)) }
                else if aqi > 100 { s += Int(rng.next(upperBound: 3)) }
                if sleep < 6.0 { s += Int(rng.next(upperBound: 2)) }
                return min(s, 9)
            }()

            let usedInhaler = severity >= 5 && rng.chance(0.8)
            let template = Self.episodeTemplates[Int(rng.next(upperBound: UInt64(Self.episodeTemplates.count)))]
            let hourSpan = template.hourRange.upperBound - template.hourRange.lowerBound
            let hour = template.hourRange.lowerBound + Int(rng.next(upperBound: UInt64(max(hourSpan, 1))))
            let minute = Int(rng.next(upperBound: 60))
            let timestamp = calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day) ?? day

            // Inhaler effectiveness: mostly helps, occasionally doesn't — the
            // "didn't help" cases are what a pulmonologist most wants to see.
            let inhalerHelped: Bool? = usedInhaler ? rng.chance(0.85) : nil

            events.append(HealthEvent(
                timestamp: timestamp,
                symptom: template.symptom,
                category: .respiratory,
                bodyRegion: .chest,
                severity: severity,
                duration: template.duration,
                triggers: template.triggers,
                medications: usedInhaler ? ["albuterol (rescue inhaler)"] : [],
                medicationHelped: inhalerHelped,
                transcript: usedInhaler ? template.transcriptWithInhaler : template.transcript,
                source: .seeded,
                environment: EnvironmentSnapshot(
                    aqi: aqi,
                    pm25: Double(aqi) * 0.35,
                    capturedAt: timestamp,
                    provider: "Open-Meteo"
                )
            ))
        }

        return Output(events: events, metrics: metrics)
    }

    struct EpisodeTemplate {
        let symptom: String
        let duration: TimeInterval?
        let triggers: [Trigger]
        /// Plausible local hours for this note (so "this morning" never lands at 7pm).
        let hourRange: ClosedRange<Int>
        let transcript: String
        let transcriptWithInhaler: String
    }

    static let episodeTemplates: [EpisodeTemplate] = [
        .init(
            symptom: "chest tightness",
            duration: 3600,
            triggers: [.outdoorAir],
            hourRange: 10...18,
            transcript: "Chest felt tight for about an hour after walking outside.",
            transcriptWithInhaler: "Chest felt tight for about an hour after walking outside, used my rescue inhaler."
        ),
        .init(
            symptom: "wheezing",
            duration: 1800,
            triggers: [.exercise],
            hourRange: 9...19,
            transcript: "Started wheezing about half an hour into my walk, had to slow down.",
            transcriptWithInhaler: "Started wheezing on my walk, had to stop and use my inhaler."
        ),
        .init(
            symptom: "shortness of breath",
            duration: nil,
            triggers: [],
            hourRange: 6...9,
            transcript: "Woke up short of breath this morning, took a while to settle.",
            transcriptWithInhaler: "Woke up short of breath this morning, used my rescue inhaler before it settled."
        ),
        .init(
            symptom: "coughing",
            duration: 7200,
            triggers: [],
            hourRange: 21...23,
            transcript: "Coughing fit at night, maybe a couple hours before I could sleep.",
            transcriptWithInhaler: "Coughing badly at night, used the inhaler so I could get to sleep."
        ),
        .init(
            symptom: "chest tightness",
            duration: nil,
            triggers: [.stress],
            hourRange: 10...16,
            transcript: "Slight chest tightness sitting in class, mild but distracting.",
            transcriptWithInhaler: "Chest tightness during class got bad enough that I used my inhaler."
        )
    ]
}

/// Small deterministic RNG so seeded data is identical across runs and platforms.
public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func next(upperBound: UInt64) -> UInt64 {
        guard upperBound > 0 else { return 0 }
        return next() % upperBound
    }

    public mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    public mutating func chance(_ probability: Double) -> Bool {
        nextDouble() < probability
    }
}
