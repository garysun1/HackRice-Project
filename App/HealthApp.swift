import SwiftUI
import os
import SwiftData
import HealthCore

@main
struct HealthApp: App {
    @State private var appEnvironment = AppEnvironment()
    private let container = DataStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .tint(.brandTeal)
                .task {
                    if appEnvironment.isDemoMode {
                        DataStore.seedIfNeeded(
                            context: container.mainContext,
                            persona: appEnvironment.persona
                        )
                    }
                }
        }
        .modelContainer(container)
    }
}

/// Composition root: parses launch arguments and wires mock vs. live services.
/// `--mock-speech` keeps SFSpeechRecognizer (and its permission prompt) untouched;
/// `-demoMode` loads the seeded 3-month persona.
@Observable
final class AppEnvironment {
    let isDemoMode: Bool
    let useMockSpeech: Bool
    let intelligence: any IntelligenceService
    let environmentService: any EnvironmentService
    /// Seeded demo persona; backs MockHealthProvider in demo mode.
    let persona: AsthmaPersona.Output
    let healthProvider: any HealthDataProvider
    let appointmentProvider: any AppointmentProvider
    /// ElevenLabs key for spoken follow-up questions (nil → text-only).
    let elevenLabsKey: String?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.isDemoMode = arguments.contains("-demoMode")
        self.useMockSpeech = arguments.contains("--mock-speech")
        // A real model (Azure OpenAI, or Claude) powers extraction + briefing
        // whenever credentials are available; --mock-intelligence (UI tests)
        // forces the deterministic mock, and ResilientIntelligence falls back
        // to it on any network failure.
        if !arguments.contains("--mock-intelligence"), let real = Secrets.makeIntelligence() {
            self.intelligence = ResilientIntelligence(primary: real)
        } else {
            self.intelligence = MockIntelligence()
        }
        Logger(subsystem: "com.garysun.healthapp", category: "config")
            .info("intelligence provider: \(String(describing: type(of: self.intelligence)), privacy: .public)")
        self.environmentService = isDemoMode
            ? CannedEnvironmentService()
            : OpenMeteoEnvironmentService()
        self.persona = AsthmaPersona.generate()
        // `-healthkit` opts into the real read path (requires the permission sheet,
        // so it's for device/manual runs — unattended runs stay on the mock).
        self.healthProvider = arguments.contains("-healthkit")
            ? HealthKitProvider()
            : MockHealthProvider(metrics: persona.metrics)
        self.appointmentProvider = isDemoMode
            ? DemoAppointmentProvider()
            : CalendarAppointmentProvider()
        self.elevenLabsKey = arguments.contains("--mock-intelligence") ? nil : Secrets.elevenLabsAPIKey
    }

    func makeTranscriber() -> any Transcriber {
        useMockSpeech ? MockTranscriber() : LiveTranscriber()
    }
}
