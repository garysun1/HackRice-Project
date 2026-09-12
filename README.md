# Interim

**Your health, between visits.** An iOS app for the time your doctor never sees — log symptoms with a 10-second voice note, build a longitudinal healthspan record correlated with your sleep, activity, and air quality, and walk into your next appointment with a briefing instead of a memory.

*HackRice — Healthcare Track (longevity/healthspan).*

| Timeline | Trends | Briefing | Connections |
|---|---|---|---|
| ![Timeline](docs/screenshots/timeline.png) | ![Trends](docs/screenshots/trends.png) | ![Briefing](docs/screenshots/briefing-banner.png) | ![Connections](docs/screenshots/connections.png) |

## Why

Appointments are 15 minutes; the months between them are where your health actually happens. Patients describe symptoms from memory — imprecise, incomplete, biased toward the last bad week. Interim turns "how have you been?" into data: every episode, its severity, what you took, and what the air and your sleep looked like when it happened.

## What it does

- **Voice-first logging** — tap, talk, done. On-device speech recognition (no API keys, no audio leaves the phone), live transcript, structured extraction (symptom, severity, duration, meds, context), typed fallback.
- **Healthspan timeline** — every entry with severity badges, medication chips, and an air-quality snapshot captured at that moment (Open-Meteo, keyless).
- **Trends** — symptom episodes overlaid on AQI and sleep. Our demo persona's asthma episodes cluster on high-AQI days at 3–4× the base rate, and the app says so in one sentence.
- **Prep my visit** — one generator, two views: a clinician-style note (chief concerns, frequency/severity statistics, correlations, medication use, episode timeline) and a patient view (talking points, questions to ask). Exportable.
- **Appointment awareness** — EventKit spots "Dr. Chen — Pulmonology, Monday" on your calendar and has the briefing ready.
- **One integration, whole ecosystem** — Apple Health is the hub: Strava workouts, MyFitnessPal nutrition, Apple Watch heart data, and Fitbit (via Google Health's Aug 2026 Apple Health sync) all flow in, each credited to its source.

Everything stays on-device. No accounts, no backend, no tracking.

## Run it

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate                 # produces HealthApp.xcodeproj from project.yml
open HealthApp.xcodeproj            # run the HealthApp scheme in a simulator or on device
```

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
| `-demoMode` | Seed 3 months of demo data (deterministic asthma persona) |
| `--mock-speech` | Deterministic transcriber — no mic/speech permissions touched |
| `-healthkit` | Use the real HealthKit read path instead of the seeded mock |
| `-openTab trends` | Launch directly on a given tab |

Core-logic tests run anywhere, no simulator needed:

```sh
swift test --package-path HealthCore
```

## Architecture (short version)

All logic lives in **HealthCore**, a UI-free Swift package (models, extraction, briefing generation, correlation stats, seeded persona) tested with `swift test`. The SwiftUI app is a thin shell; every external dependency — speech, health data, air quality, calendar, "AI" — sits behind a protocol with a mock implementation, selected at launch. The extraction/briefing layer is deterministic today and has a drop-in seam for Claude when an API key is provided.
