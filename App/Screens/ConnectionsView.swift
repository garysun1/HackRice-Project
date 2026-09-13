import SwiftUI
import HealthCore

/// The integrations showcase: what's connected (with live source attribution),
/// what's available with setup, and what's on the roadmap.
struct ConnectionsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var sources: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionRow(
                        icon: "heart.fill",
                        iconColor: .pink,
                        title: "Apple Health",
                        subtitle: "One hub for your whole ecosystem",
                        status: .connected
                    )
                    if !sources.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Contributing sources")
                                .font(.rounded(.caption, weight: .semibold))
                                .foregroundStyle(.secondary)
                            FlowChips(items: sources.map { sourceBadge($0) })
                        }
                        .padding(.vertical, 4)
                    }
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
                    Text("Connected")
                }

                Section {
                    ConnectionRow(
                        icon: "figure.walk",
                        iconColor: .green,
                        title: "Fitbit — via Google Health",
                        subtitle: "Google Health app → Profile → Partner apps → Apple Health",
                        status: .available
                    )
                } header: {
                    Text("Available")
                } footer: {
                    Text("As of Aug 2026, Google Health syncs Fitbit steps, sleep, heart rate, and workouts into Apple Health — Interim picks them up automatically.")
                }

                Section {
                    ConnectionRow(icon: "circle.circle", iconColor: .gray, title: "Oura", subtitle: "Readiness & sleep scores", status: .comingSoon)
                    ConnectionRow(icon: "bolt.heart", iconColor: .gray, title: "Whoop", subtitle: "Recovery & strain", status: .comingSoon)
                    ConnectionRow(icon: "drop", iconColor: .gray, title: "Dexcom CGM", subtitle: "Glucose & metabolic health", status: .comingSoon)
                    ConnectionRow(icon: "building.columns", iconColor: .gray, title: "MyChart records", subtitle: "Labs & medications via FHIR", status: .comingSoon)
                    ConnectionRow(icon: "leaf", iconColor: .gray, title: "Pollen", subtitle: "Allergen forecasts", status: .comingSoon)
                } header: {
                    Text("Coming soon")
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
                sources = await appEnvironment.loadContributingSources()
            }
        }
    }

    private func sourceBadge(_ source: String) -> String {
        switch true {
        case source.contains("Fitbit"), source.contains("Google"): "👟 Steps · \(source)"
        case source.contains("Strava"): "🏃 Workouts · \(source)"
        case source.contains("MyFitnessPal"): "🍎 Nutrition · \(source)"
        case source.contains("Watch"): "❤️ Heart · \(source)"
        default: "📊 \(source)"
        }
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

/// Simple wrapping chip layout.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        FlexibleHStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Chip(text: item, tint: .brandTeal)
            }
        }
    }
}

/// Minimal wrapping layout (iOS 16+ Layout protocol).
struct FlexibleHStack: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
