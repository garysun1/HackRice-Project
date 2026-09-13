import SwiftUI
import HealthCore

/// Level 2: which apps and devices supply this category of data.
///
/// Every row here is backed by data that actually arrived — there are no "available" or
/// "coming soon" placeholders. The one exception is Google Health under General Health,
/// which is a sync path the user enables on their phone rather than an API Interim calls.
struct CategoryConnectionsView: View {
    let category: HealthDataCategory
    let sources: [SourceContribution]

    var body: some View {
        List {
            if sources.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing connected yet",
                        systemImage: category.systemImage,
                        description: Text("Once an app or device writes \(category.displayName.lowercased()) data into Apple Health, it will appear here.")
                    )
                }
            } else {
                Section {
                    ForEach(sources) { source in
                        NavigationLink {
                            SourceDetailView(source: source)
                        } label: {
                            SourceRow(source: source, category: category)
                        }
                        .accessibilityIdentifier("connections.source.\(source.id)")
                    }
                } header: {
                    Text("Supplying data")
                } footer: {
                    Text("Detected in Apple Health and credited to the app or device that wrote it.")
                }
            }

            if category == .general {
                Section {
                    NavigationLink {
                        GoogleHealthSetupView()
                    } label: {
                        ConnectionRow(
                            icon: "arrow.triangle.swap",
                            iconColor: .green,
                            title: "Google Health",
                            subtitle: "Route Fitbit data into Apple Health",
                            status: .available
                        )
                    }
                    .accessibilityIdentifier("connections.source.googleHealth")
                } header: {
                    Text("Set up")
                } footer: {
                    Text("Google Health has no iOS API, so Interim can't connect to it directly — but it can forward your Fitbit data into Apple Health, where Interim picks it up automatically.")
                }
            }
        }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SourceRow: View {
    let source: SourceContribution
    let category: HealthDataCategory

    /// What this source contributes *to this category*, so the Sleep screen doesn't
    /// advertise a device's step count.
    private var summary: String {
        source.dataTypes(in: category)
            .map(\.kind.displayName)
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: SourceIcon.symbol(for: source.sourceName))
                .font(.system(size: 17))
                .foregroundStyle(Color.brandTeal)
                .frame(width: 34, height: 34)
                .background(Color.brandTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.sourceName)
                    .font(.rounded(.body, weight: .medium))
                Text(summary)
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandTeal)
        }
        .padding(.vertical, 2)
    }
}

/// Picks a glyph for a source name. Purely cosmetic — what a source actually *provides*
/// is always read from its real contributions, never guessed from its name.
enum SourceIcon {
    static func symbol(for sourceName: String) -> String {
        switch true {
        case sourceName.contains("Watch"): "applewatch"
        case sourceName.contains("Strava"), sourceName.contains("Nike"): "figure.run"
        case sourceName.contains("Fitbit"), sourceName.contains("Google"): "figure.walk"
        case sourceName.contains("MyFitnessPal"), sourceName.contains("Cronometer"): "fork.knife"
        case sourceName.contains("Oura"), sourceName.contains("Whoop"): "bed.double.fill"
        case sourceName.contains("Interim"): "waveform.and.mic"
        default: "square.stack.3d.up.fill"
        }
    }
}

/// The one non-API "connection" we surface, because the user has to configure it themselves.
struct GoogleHealthSetupView: View {
    private let steps = [
        "Open the Google Health app on your phone.",
        "Go to Profile → Partner apps.",
        "Choose Apple Health and turn on sharing.",
        "Enable steps, sleep, heart rate, and workouts."
    ]

    var body: some View {
        List {
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.rounded(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.brandTeal, in: Circle())
                        Text(step)
                            .font(.rounded(.callout))
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Connect Fitbit through Google Health")
            } footer: {
                Text("Interim never talks to Google Health or Fitbit directly — there is no iOS API for either. Once this sync is on, their data lands in Apple Health and shows up here on its own.")
            }
        }
        .navigationTitle("Google Health")
        .navigationBarTitleDisplayMode(.inline)
    }
}
