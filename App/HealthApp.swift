import SwiftUI
import os
import SwiftData
import OSLog
import HealthKit
import EventKit
import CoreLocation
import HealthCore

@main
struct HealthApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appEnvironment: AppEnvironment
    private let container: ModelContainer

    init() {
        let environment = AppEnvironment()
        let container = DataStore.makeContainer(inMemory: environment.usesInMemoryStore)
        environment.attach(container: container)
        _appEnvironment = State(initialValue: environment)
        self.container = container
    }

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
                    } else {
                        DataStore.removeSeededEvents(context: container.mainContext)
                        await appEnvironment.refreshAirQualityHistory()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, !appEnvironment.isDemoMode else { return }
                    Task { await appEnvironment.refreshAirQualityHistory() }
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
    let isOffline: Bool
    private let ignoresHealthKitData: Bool
    let usesInMemoryStore: Bool
    let useMockSpeech: Bool
    let intelligence: any IntelligenceService
    let environmentService: any EnvironmentService
    /// Seeded demo persona; backs MockHealthProvider in demo mode.
    let persona: AsthmaPersona.Output
    @ObservationIgnored private(set) var healthProvider: any HealthDataProvider
    @ObservationIgnored private(set) var localMetrics: LocalMetricStore?
    @ObservationIgnored private(set) var airQualityHistory: AirQualityHistoryStore?
    let appointmentProvider: any AppointmentProvider
    /// ElevenLabs key for spoken follow-up questions (nil → text-only).
    let elevenLabsKey: String?
    /// Hands-free conversational follow-ups (spoken question → auto-listen).
    /// Disabled in UI tests so the manual tap path stays deterministic.
    let autoConversation: Bool
    /// `-seedHealthKit` writes the persona into HealthKit so the real read path
    /// has data to return on a simulator or a fresh device.
    let shouldSeedHealthKit: Bool
    let locationService: LocationService
    var metricsVersion = 0
    var connectionStatus = ConnectionStatusSnapshot()

    @ObservationIgnored private let healthKitProvider: HealthKitProvider?
    @ObservationIgnored private let calendarStore = EKEventStore()

    init(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        useMockData: Bool = AppConfig.useMockData
    ) {
        let isDemoMode = arguments.contains("-demoMode") || useMockData

        self.isDemoMode = isDemoMode
        self.isOffline = arguments.contains("-offline")
        self.ignoresHealthKitData = arguments.contains("-ignoreHealthKitData")
        self.usesInMemoryStore = isDemoMode || arguments.contains("-inMemoryStore")
        self.useMockSpeech = arguments.contains("--mock-speech")
        self.shouldSeedHealthKit = arguments.contains("-seedHealthKit")
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
        self.elevenLabsKey = arguments.contains("--mock-intelligence") ? nil : Secrets.elevenLabsAPIKey
        self.autoConversation = !arguments.contains("--mock-intelligence")
        self.persona = AsthmaPersona.generate()
        let locationService = LocationService()
        self.locationService = locationService
        self.environmentService = isDemoMode
            ? CannedEnvironmentService()
            : OpenMeteoEnvironmentService(coordinateProvider: { [locationService] in
                let coordinate = await locationService.currentCoordinate()
                return (lat: coordinate.latitude, lon: coordinate.longitude)
            })
        self.localMetrics = nil
        self.airQualityHistory = nil

        if isDemoMode {
            self.healthKitProvider = nil
            self.healthProvider = MockHealthProvider(metrics: persona.metrics)
            self.appointmentProvider = DemoAppointmentProvider()
        } else {
            let healthKitProvider = HealthKitProvider()
            healthKitProvider.includeWriteOnAuthorize = shouldSeedHealthKit
            self.healthKitProvider = healthKitProvider
            self.healthProvider = healthKitProvider
            self.appointmentProvider = CalendarAppointmentProvider()
        }

        locationService.authorizationDidChange = { [weak self] in
            Task { @MainActor in
                await self?.refreshConnectionStatus()
                await self?.refreshAirQualityHistory()
            }
        }
    }

    func attach(container: ModelContainer) {
        let localMetrics = LocalMetricStore(context: container.mainContext)
        let personaPeaks = Dictionary(
            persona.metrics.compactMap { day in
                day.peakAQI.map { (day.date, $0) }
            },
            uniquingKeysWith: { _, last in last }
        )
        let historyService: any AirQualityHistoryService
        if isDemoMode {
            historyService = CannedAirQualityHistory(peaks: personaPeaks)
        } else if isOffline {
            historyService = CannedAirQualityHistory(peaks: [:])
        } else {
            historyService = OpenMeteoAirQualityHistory()
        }
        let airQualityHistory = AirQualityHistoryStore(
            context: container.mainContext,
            service: historyService,
            location: locationService
        )
        self.localMetrics = localMetrics
        self.airQualityHistory = airQualityHistory
        if let healthKitProvider {
            healthProvider = CompositeHealthProvider(
                healthKit: healthKitProvider,
                local: localMetrics,
                airQuality: airQualityHistory,
                includeHealthKitData: !ignoresHealthKitData
            )
        }
    }

    func refreshAirQualityHistory() async {
        guard let airQualityHistory else { return }
        let count = airQualityHistory.rowCount
        await airQualityHistory.refreshIfStale()
        if airQualityHistory.rowCount != count { metricsVersion += 1 }
    }

    func recordLocalMetricsChanged() {
        metricsVersion += 1
    }

    func makeTranscriber(autoStopOnSilence: Bool = false) -> any Transcriber {
        if useMockSpeech { return MockTranscriber() }
        #if targetEnvironment(simulator)
        // Apple's speech engine can't initialize in the Simulator; use
        // ElevenLabs Scribe (cloud STT) there when a key is available.
        if let key = elevenLabsKey {
            return ElevenLabsTranscriber(apiKey: key, autoStopOnSilence: autoStopOnSilence)
        }
        #endif
        return LiveTranscriber(autoStopOnSilence: autoStopOnSilence)
    }

    /// Requests HealthKit access (and seeds if `-seedHealthKit`). Only ever called from the Connect button.
    func connectAppleHealth() async {
        do {
            try await healthProvider.requestAuthorization()
            if shouldSeedHealthKit {
                try await healthProvider.seedDemoData(persona.metrics)
            }
        } catch {
            Self.log.error("HealthKit unavailable: \(error.localizedDescription)")
        }
        await refreshConnectionStatus()
        metricsVersion += 1
    }

    func connectCalendar() async {
        do {
            _ = try await calendarStore.requestFullAccessToEvents()
        } catch {
            Self.log.error("Calendar authorization failed: \(error.localizedDescription)")
        }
        await refreshConnectionStatus()
    }

    func connectLocation() {
        locationService.requestWhenInUse()
    }

    func refreshConnectionStatus() async {
        if isDemoMode {
            connectionStatus = ConnectionStatusSnapshot(
                health: .connected,
                calendar: .connected,
                location: .connected
            )
            return
        }

        let health: ConnectionState
        guard let healthKitProvider,
              let healthStatus = await healthKitProvider.authorizationRequestStatus() else {
            health = .unavailable
            connectionStatus = statusSnapshot(health: health)
            return
        }
        switch healthStatus {
        case .shouldRequest, .unknown:
            health = .notConnected
        case .unnecessary:
            health = .connected
        @unknown default:
            health = .notConnected
        }
        connectionStatus = statusSnapshot(health: health)
    }

    private func statusSnapshot(health: ConnectionState) -> ConnectionStatusSnapshot {
        let calendar: ConnectionState = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .connected
        case .notDetermined: .notConnected
        default: .denied
        }

        let location: ConnectionState = switch locationService.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: .connected
        case .notDetermined: .notConnected
        default: .denied
        }

        return ConnectionStatusSnapshot(health: health, calendar: calendar, location: location)
    }

    // MARK: - Briefing cache

    /// The latest generated briefing, regenerated in the BACKGROUND whenever
    /// events or metrics change (watched from RootView) — so the Briefing tab
    /// renders instantly instead of re-running the ~10s generation on open.
    private(set) var briefing: VisitBriefing?
    private(set) var briefingInFlight = false
    @ObservationIgnored private var briefingTask: Task<Void, Never>?
    @ObservationIgnored private var briefingFingerprint: Int?

    /// Kick off (or skip, if nothing changed) a background regeneration.
    /// `fingerprint` identifies the data snapshot; bursts of changes (seeding)
    /// are coalesced by the debounce + task cancellation.
    func refreshBriefing(events: [HealthEvent], fingerprint: Int) {
        guard fingerprint != briefingFingerprint else { return }
        briefingFingerprint = fingerprint
        briefingTask?.cancel()
        guard !events.isEmpty else {
            briefing = nil
            briefingInFlight = false
            return
        }
        briefingInFlight = true
        briefingTask = Task { [weak self] in
            // Debounce: let a burst of inserts settle before spending an API call.
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            let metrics = await self.loadDailyMetrics()
            // ResilientIntelligence falls back to the mock internally; the extra
            // ?? MockIntelligence pass covers the bare-mock configuration too.
            let result = (try? await self.intelligence.generateBriefing(events: events, metrics: metrics, now: Date()))
                ?? MockIntelligence().generateBriefing(events: events, metrics: metrics, now: Date())
            guard !Task.isCancelled else { return }
            self.briefing = result
            self.briefingInFlight = false
        }
    }

    func loadDailyMetrics() async -> [DailyMetrics] {
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
        (try? await healthProvider.contributingSources()) ?? []
    }

    func loadSourceContributions() async -> [SourceContribution] {
        do {
            return try await healthProvider.sourceContributions()
        } catch {
            Self.log.error("sourceContributions failed: \(error.localizedDescription)")
            return []
        }
    }
}
