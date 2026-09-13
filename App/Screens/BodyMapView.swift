import SwiftUI
import SwiftData
import HealthCore

/// The anatomical lens on the log: a 3D mannequin you can swipe around,
/// one marker per body region — size = episode count, color = worst severity.
struct BodyMapView: View {
    let events: [StoredEvent]

    enum TimeRange: String, CaseIterable, Identifiable {
        case week = "7d"
        case month = "30d"
        case all = "All"
        var id: String { rawValue }

        var cutoff: Date? {
            switch self {
            case .week: Calendar.current.date(byAdding: .day, value: -7, to: .now)
            case .month: Calendar.current.date(byAdding: .day, value: -30, to: .now)
            case .all: nil
            }
        }
    }

    @State private var range: TimeRange = .all
    @State private var selectedRegion: BodyRegion?

    private var filtered: [StoredEvent] {
        guard let cutoff = range.cutoff else { return events }
        return events.filter { $0.timestamp >= cutoff }
    }

    private var byRegion: [BodyRegion: [StoredEvent]] {
        Dictionary(grouping: filtered, by: \.bodyRegion)
    }

    private var markerData: [BodyRegion: (count: Int, maxSeverity: Int)] {
        byRegion.mapValues { (count: $0.count, maxSeverity: $0.map(\.severity).max() ?? 1) }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(TimeRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Body3DView(regionData: markerData) { region in
                selectedRegion = region
            }
            .accessibilityLabel(accessibilitySummary)
            .accessibilityIdentifier("bodymap.scene")

            Text("Swipe to rotate · tap a marker for details")
                .font(.rounded(.caption2))
                .foregroundStyle(.tertiary)

            diffuseChips
        }
        .sheet(item: $selectedRegion) { region in
            RegionDetailSheet(region: region, events: byRegion[region] ?? [])
                .presentationDetents([.medium, .large])
        }
    }

    private var accessibilitySummary: String {
        markerData
            .sorted { $0.value.count > $1.value.count }
            .map { "\($0.key.displayName): \($0.value.count) episodes, worst severity \($0.value.maxSeverity)" }
            .joined(separator: ". ")
    }

    /// Skin + systemic don't belong on anatomy — they get chips below the figure.
    private var diffuseChips: some View {
        HStack(spacing: 10) {
            ForEach([BodyRegion.systemic, .skin], id: \.self) { region in
                if let regionEvents = byRegion[region], !regionEvents.isEmpty {
                    Button {
                        selectedRegion = region
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.severity(regionEvents.map(\.severity).max() ?? 1))
                                .frame(width: 10, height: 10)
                            Text("\(region == .systemic ? "General" : "Skin") · \(regionEvents.count)")
                                .font(.rounded(.footnote, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.background, in: Capsule())
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }
}

extension BodyRegion: Identifiable {
    public var id: String { rawValue }
}

private struct RegionDetailSheet: View {
    let region: BodyRegion
    let events: [StoredEvent]

    var body: some View {
        NavigationStack {
            List(events.sorted { $0.timestamp > $1.timestamp }) { event in
                EventRow(event: event)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("\(region == .systemic ? "General" : region.displayName) · \(events.count)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
