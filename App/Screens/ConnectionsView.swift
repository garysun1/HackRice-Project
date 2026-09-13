import SwiftUI
import HealthCore

/// Level 1 of the Connections drill-down: the three health categories, then the real
/// non-health integrations.
///
/// Nothing aspirational is listed. A source appears only when it is genuinely supplying
/// data — Interim has no direct API for Fitbit, Oura or Garmin, so they can only ever show
/// up as sources detected inside Apple Health. Google Health is the single exception: it is
/// a routing path the user configures on their phone, so it gets a row with instructions.
struct ConnectionsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var contributions: [SourceContribution] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
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
                } footer: {
                    Text("Apple Health is the hub — anything writing into it shows up here automatically, credited to the app or device that supplied it.")
                }

                Section {
                    ConnectionRow(
                        icon: "location.fill",
                        iconColor: .brandTeal,
                        title: "Air quality (Open-Meteo)",
                        subtitle: "Snapshot attached to every entry — no account needed",
                        status: .connected
                    )
                    ConnectionRow(
                        icon: "calendar",
                        iconColor: .red,
                        title: "Calendar",
                        subtitle: "Detects upcoming appointments to prep your briefing",
                        status: .connected
                    )
                } header: {
                    Text("Also connected")
                }

                Section {
                    Label {
                        Text("Your health data never leaves your phone. Interim stores everything on-device.")
                            .font(.rounded(.footnote))
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color.brandTeal)
                    }
                }
            }
            .navigationTitle("Connections")
            .task {
                contributions = await appEnvironment.loadSourceContributions()
                isLoading = false
            }
        }
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
    case connected, available, comingSoon
}

struct ConnectionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(status == .comingSoon ? .gray : iconColor)
                .frame(width: 34, height: 34)
                .background((status == .comingSoon ? Color.gray : iconColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.rounded(.body, weight: .medium))
                    .foregroundStyle(status == .comingSoon ? .secondary : .primary)
                Text(subtitle)
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch status {
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.brandTeal)
            case .available:
                Text("Set up")
                    .font(.rounded(.caption, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.brandTeal.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.brandTeal)
            case .comingSoon:
                Text("Soon")
                    .font(.rounded(.caption2))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
