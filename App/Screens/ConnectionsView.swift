import SwiftUI
import UIKit
import HealthCore

/// Level 1 of the Connections drill-down: the three health categories, then the real
/// non-health integrations.
///
/// Nothing aspirational is listed. A source appears only when it is genuinely supplying
/// data — Breathing Room has no direct API for Fitbit, Oura or Garmin, so they can only ever show
/// up as sources detected inside Apple Health. Google Health is the single exception: it is
/// a routing path the user configures on their phone, so it gets a row with instructions.
struct ConnectionsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var contributions: [SourceContribution] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionRow(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Apple Health",
                        subtitle: appleHealthSubtitle,
                        status: appEnvironment.connectionStatus.health.rowStatus,
                        action: appleHealthAction,
                        actionIdentifier: "connections.appleHealth.connect"
                    )
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Apple Health is the hub — anything writing into it shows up here automatically, credited to the app or device that supplied it.")
                }

                Section {
                    NavigationLink {
                        ManualMetricsView()
                    } label: {
                        ConnectionRow(
                            icon: "square.and.pencil",
                            iconColor: .brandTeal,
                            title: "Manual entry",
                            subtitle: "Log sleep, steps, nutrition and more for any day",
                            status: .available
                        )
                    }
                    .accessibilityIdentifier("connections.manualEntry")
                } header: {
                    Text("Your data")
                }

                Section {
                    ForEach(HealthDataCategory.allCases) { category in
                        NavigationLink {
                            CategoryConnectionsView(
                                category: category,
                                sources: contributions.supplying(category)
                            )
                        } label: {
                            CategoryRow(
                                category: category,
                                sourceCount: contributions.supplying(category).count,
                                isLoading: isLoading
                            )
                        }
                        .accessibilityIdentifier("connections.category.\(category.rawValue)")
                    }
                } header: {
                    Text("Your health data")
                }

                Section {
                    ConnectionRow(
                        icon: "location.fill",
                        iconColor: .brandTeal,
                        title: "Air quality (Open-Meteo)",
                        subtitle: locationSubtitle,
                        status: appEnvironment.connectionStatus.location.rowStatus,
                        action: locationAction
                    )
                    ConnectionRow(
                        icon: "calendar",
                        iconColor: .red,
                        title: "Calendar",
                        subtitle: calendarSubtitle,
                        status: appEnvironment.connectionStatus.calendar.rowStatus,
                        action: calendarAction
                    )
                } header: {
                    Text("Also uses")
                }

                Section {
                    Label {
                        Text("Your health data never leaves your phone. Breathing Room stores everything on-device.")
                            .font(.rounded(.footnote))
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }
            .navigationTitle("Connections")
            .task(id: appEnvironment.metricsVersion) {
                await appEnvironment.refreshConnectionStatus()
                contributions = await appEnvironment.loadSourceContributions()
                isLoading = false
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await appEnvironment.refreshConnectionStatus()
                }
            }
        }
    }

    private var appleHealthSubtitle: String {
        switch appEnvironment.connectionStatus.health {
        case .notConnected:
            "Connect to import steps, sleep, heart rate, workouts and nutrition"
        case .connected:
            "Connected — if nothing appears, check Settings › Health › Data Access"
        case .denied:
            "Access denied — open Settings to allow"
        case .unavailable:
            "Not available on this device"
        }
    }

    private var locationSubtitle: String {
        switch appEnvironment.connectionStatus.location {
        case .notConnected:
            "Using default location (Houston) — connect to use yours"
        case .connected:
            "Using your location"
        case .denied:
            "Location access denied — using default location (Houston)"
        case .unavailable:
            "Location not available — using default location (Houston)"
        }
    }

    private var calendarSubtitle: String {
        switch appEnvironment.connectionStatus.calendar {
        case .notConnected:
            "Connect to detect upcoming appointments to prep your briefing"
        case .connected:
            "Detects upcoming appointments to prep your briefing"
        case .denied:
            "Access denied — open Settings to allow"
        case .unavailable:
            "Not available on this device"
        }
    }

    private var appleHealthAction: (() -> Void)? {
        switch appEnvironment.connectionStatus.health {
        case .notConnected:
            return {
                Task {
                    await appEnvironment.connectAppleHealth()
                    contributions = await appEnvironment.loadSourceContributions()
                    isLoading = false
                }
            }
        case .denied:
            return openSettings
        case .connected, .unavailable:
            return nil
        }
    }

    private var calendarAction: (() -> Void)? {
        switch appEnvironment.connectionStatus.calendar {
        case .notConnected:
            return {
                Task {
                    await appEnvironment.connectCalendar()
                }
            }
        case .denied:
            return openSettings
        case .connected, .unavailable:
            return nil
        }
    }

    private var locationAction: (() -> Void)? {
        switch appEnvironment.connectionStatus.location {
        case .notConnected:
            return appEnvironment.connectLocation
        case .denied:
            return openSettings
        case .connected, .unavailable:
            return nil
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct CategoryRow: View {
    let category: HealthDataCategory
    let sourceCount: Int
    let isLoading: Bool

    private var detail: String {
        if isLoading { return "Checking…" }
        return switch sourceCount {
        case 0: "No sources yet"
        case 1: "1 source"
        default: "\(sourceCount) sources"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.systemImage)
                .font(.system(size: 17))
                .foregroundStyle(Color.brandTeal)
                .frame(width: 34, height: 34)
                .background(Color.brandTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.rounded(.body, weight: .medium))
                Text(category.subtitle)
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(detail)
                .font(.rounded(.caption, weight: .medium))
                .foregroundStyle(sourceCount > 0 && !isLoading ? Color.brandTeal : .secondary)
        }
        .padding(.vertical, 2)
    }
}

enum ConnectionStatus {
    case connected, available, denied, unavailable, comingSoon
}

private extension ConnectionState {
    var rowStatus: ConnectionStatus {
        switch self {
        case .notConnected: .available
        case .connected: .connected
        case .denied: .denied
        case .unavailable: .unavailable
        }
    }
}

struct ConnectionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let status: ConnectionStatus
    var action: (() -> Void)? = nil
    var actionIdentifier: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(isMuted ? .gray : iconColor)
                .frame(width: 34, height: 34)
                .background((isMuted ? Color.gray : iconColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rounded(.body, weight: .medium))
                    .foregroundStyle(isMuted ? .secondary : .primary)
                Text(subtitle)
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailingControl
        }
        .padding(.vertical, 2)
    }

    private var isMuted: Bool {
        status == .comingSoon || status == .unavailable
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch status {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandTeal)
        case .available:
            if let action {
                actionButton("Connect", action: action, tint: .brandTeal)
            } else {
                Text("Set up")
                    .font(.rounded(.caption, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.brandTeal.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.brandTeal)
            }
        case .denied:
            if let action {
                actionButton("Open Settings", action: action, tint: .orange)
            }
        case .unavailable:
            Text("Unavailable")
                .font(.rounded(.caption2))
                .foregroundStyle(.tertiary)
        case .comingSoon:
            Text("Soon")
                .font(.rounded(.caption2))
                .foregroundStyle(.tertiary)
        }
    }

    private func actionButton(_ title: String, action: @escaping () -> Void, tint: Color) -> some View {
        Button(title, action: action)
            .font(.rounded(.caption, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .buttonStyle(.plain)
            .accessibilityIdentifier(actionIdentifier ?? "")
    }
}
