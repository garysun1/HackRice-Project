import SwiftUI
import SwiftData
import OSLog
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
                    await appEnvironment.prepareHealthData()
                }
        }
        .modelContainer(container)
    }
}

/// Composition root: parses launch arguments and wires mock vs. live services.
/// `--mock-speech` keeps SFSpeechRecognizer (and its permission prompt) untouched;
/// `-demoMode` loads the seeded 3-month persona.
@MainActor
@Observable
final class AppEnvironment {
    static let log = Logger(subsystem: "com.hackrice.healthapp", category: "health")

    let isDemoMode: Bool
    let useMockSpeech: Bool
    let intelligence: any IntelligenceService
    let environmentService: any EnvironmentService
    /// Seeded demo persona; backs MockHealthProvider in demo mode.
    let persona: AsthmaPersona.Output
    let healthProvider: any HealthDataProvider
    let appointmentProvider: any AppointmentProvider
    /// `-seedHealthKit` writes the persona into HealthKit so the real read path
    /// has data to return on a simulator or a fresh device.
    let shouldSeedHealthKit: Bool

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.isDemoMode = arguments.contains("-demoMode")
        self.useMockSpeech = arguments.contains("--mock-speech")
        self.shouldSeedHealthKit = arguments.contains("-seedHealthKit")
        self.intelligence = MockIntelligence()
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
    }

    func makeTranscriber() -> any Transcriber {
        useMockSpeech ? MockTranscriber() : LiveTranscriber()
    }

    /// One-shot authorization (plus optional seeding), shared by every caller.
    /// Screens must await this before querying: a `.task` that queries HealthKit
    /// before access is granted gets an empty result and caches it forever.
    @ObservationIgnored private var readyTask: Task<Void, Never>?

    func healthDataReady() async {
        if readyTask == nil {
            readyTask = Task { @MainActor [healthProvider, shouldSeedHealthKit, persona] in
                do {
                    try await healthProvider.requestAuthorization()
                    if shouldSeedHealthKit {
                        try await healthProvider.seedDemoData(persona.metrics)
                    }
                } catch {
                    // Denied or unavailable: screens fall back to their empty states.
                    Self.log.error("HealthKit unavailable: \(error.localizedDescription)")
                }
            }
        }
        await readyTask?.value
    }

    /// Kicks off authorization at launch so the prompt appears promptly.
    func prepareHealthData() async {
        await healthDataReady()
    }

    /// The single entry point screens use for lifestyle data — always correctly ordered.
    func loadDailyMetrics() async -> [DailyMetrics] {
        await healthDataReady()
        do {
            let metrics = try await healthProvider.dailyMetrics(from: .distantPast, to: .now)
            Self.log.info("loaded \(metrics.count) days of metrics")
            return metrics
        } catch {
            Self.log.error("dailyMetrics failed: \(error.localizedDescription)")
            return []
        }
    }

    func loadContributingSources() async -> [String] {
        await healthDataReady()
        return (try? await healthProvider.contributingSources()) ?? []
    }
}
