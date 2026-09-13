import Foundation
import Testing
import HealthCore
@testable import HealthApp

@MainActor
@Suite struct AppEnvironmentTests {
    @Test func parsesLaunchArguments() {
        let env = AppEnvironment(arguments: ["app", "-demoMode", "--mock-speech"])
        #expect(env.isDemoMode)
        #expect(env.useMockSpeech)
    }

    @Test func defaultsToLiveMode() {
        let env = AppEnvironment(arguments: ["app"])
        #expect(!env.isDemoMode)
        #expect(!env.useMockSpeech)
    }

    @Test func demoModeUsesCannedEnvironment() async throws {
        let env = AppEnvironment(arguments: ["app", "-demoMode"])
        let snapshot = try await env.environmentService.currentSnapshot()
        #expect(snapshot.provider == "Demo")
    }
}
