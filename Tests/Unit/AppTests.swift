import Foundation
import Testing
import HealthCore
@testable import HealthApp

@MainActor
@Suite struct AppEnvironmentTests {
    @Test func parsesLaunchArguments() {
        let env = AppEnvironment(
            arguments: ["app", "-demoMode", "--mock-speech"],
            useMockData: false
        )
        #expect(env.isDemoMode)
        #expect(env.usesInMemoryStore)
        #expect(env.useMockSpeech)
    }

    @Test func defaultsToLiveMode() {
        let env = AppEnvironment(arguments: ["app"], useMockData: false)
        #expect(!env.isDemoMode)
        #expect(!env.usesInMemoryStore)
        #expect(!env.useMockSpeech)
    }

    @Test func mockConfigUsesDemoModeAndInMemoryStore() {
        let env = AppEnvironment(arguments: ["app"], useMockData: true)
        #expect(env.isDemoMode)
        #expect(env.usesInMemoryStore)
    }

    @Test func inMemoryStoreDoesNotEnableDemoMode() {
        let env = AppEnvironment(
            arguments: ["app", "-inMemoryStore"],
            useMockData: false
        )
        #expect(!env.isDemoMode)
        #expect(env.usesInMemoryStore)
    }

    @Test func offlineModeAvoidsNetworkAQIHistory() {
        let env = AppEnvironment(arguments: ["app", "-offline"], useMockData: false)
        #expect(env.isOffline)
    }

    @Test func demoModeUsesCannedEnvironment() async throws {
        let env = AppEnvironment(arguments: ["app", "-demoMode"], useMockData: false)
        let snapshot = try await env.environmentService.currentSnapshot()
        #expect(snapshot.provider == "Demo")
    }
}
