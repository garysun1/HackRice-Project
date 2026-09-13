# Breathing Room

**Your health, between visits.** An iOS app for the time your doctor never sees — log symptoms with a 10-second voice note, build a longitudinal healthspan record correlated with your sleep, activity, and air quality, and walk into your next appointment with a briefing instead of a memory.

*HackRice — Healthcare Track (longevity/healthspan).*

## Why

Appointments are 15 minutes; the months between them are where your health actually happens. Patients describe symptoms from memory — imprecise, incomplete, biased toward the last bad week. Breathing Room turns "how have you been?" into data: every episode, its severity, what you took, and what the air and your sleep looked like when it happened.

## What it does

- **Voice-first logging** — tap, talk, done. On-device speech recognition (no API keys, no audio leaves the phone), live transcript, structured extraction (symptom, severity, duration, meds, context), typed fallback.
- **Healthspan timeline** — every entry with severity badges, medication chips, and an air-quality snapshot captured at that moment (Open-Meteo, keyless).
- **Trends** — symptom episodes overlaid on AQI and sleep. Our demo persona's asthma episodes cluster on high-AQI days at 3–4× the base rate, and the app says so in one sentence.
- **Prep my visit** — one generator, two views: a clinician-style note (chief concerns, frequency/severity statistics, correlations, medication use, episode timeline) and a patient view (talking points, questions to ask). Exportable.
- **Appointment awareness** — EventKit spots "Dr. Chen — Pulmonology, Monday" on your calendar and has the briefing ready.
- **One integration, whole ecosystem** — Apple Health is the hub: Strava workouts, MyFitnessPal nutrition, Apple Watch heart data, and Fitbit (via Google Health's Aug 2026 Apple Health sync) all flow in, each credited to its source. Connections groups them into **General / Sleep / Fitness Health**, and every source drills down to exactly what it imported — data types, day counts, date span, latest reading. Nothing is listed that isn't actually supplying data.

Everything stays on-device. No accounts, no backend, no tracking.

## Run it

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate                 # produces HealthApp.xcodeproj from project.yml
open HealthApp.xcodeproj            # run the HealthApp scheme in a simulator or on device
```

## Data modes

`AppConfig.useMockData` is the single source-level mode switch. It defaults to `false`, so the app starts with real on-device data and no seeded timeline. Set it to `true` for the deterministic asthma persona and an in-memory store that never touches real data.

Apple Health is connected explicitly from **Connections › Apple Health › Connect**. Symptoms can be added from the Timeline `+` menu, while daily sleep, activity, and nutrition can be entered there, from Trends `+`, or from Connections › Manual entry. Daily AQI history comes from Open-Meteo using the authorized device location, with Houston as the fallback.

Headless (CI-style) loop used to build this project:

```sh
Scripts/preflight.sh              # one-time environment verification
Scripts/build.sh                  # simulator build
Scripts/test.sh all               # unit + UI tests with JSON result summaries
Scripts/sim.sh launch --mock-speech -demoMode   # run with seeded persona
```

Useful launch arguments:

| Argument | Effect |
|---|---|
| `-demoMode` | Force the seeded 3-month persona with an in-memory store |
| `-inMemoryStore` | Keep real-mode events, manual metrics, and AQI cache ephemeral |
| `-seedHealthKit` | After Connect, write the demo persona into HealthKit for readback testing |
| `-offline` | Disable network AQI history and use an empty canned history |
| `--mock-speech` | Deterministic transcriber — no mic/speech permissions touched |
| `-openTab trends` | Launch directly on a given tab |
| `-healthkit` | Legacy compatibility argument; accepted and ignored because real mode always uses HealthKit |

On a simulator, use an **iPhone 17**. HealthKit records authorization per bundle id and that decision survives app uninstall; if the permission state gets stuck, reset only that simulator with `xcrun simctl erase <device>`.

Core-logic tests run anywhere, no simulator needed:

```sh
swift test --package-path HealthCore
```

## Architecture (short version)

All logic lives in **HealthCore**, a UI-free Swift package (models, extraction, briefing generation, correlation stats, seeded persona) tested with `swift test`. The SwiftUI app is a thin shell; every external dependency — speech, health data, air quality, calendar, "AI" — sits behind a protocol with a mock implementation, selected at launch. The extraction/briefing layer is deterministic today and has a drop-in seam for Claude when an API key is provided.
