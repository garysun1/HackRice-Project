import SwiftUI
import SwiftData
import HealthCore

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredEvent.timestamp, order: .reverse) private var events: [StoredEvent]
    // Declaration order = segment order: Body first (left), and the default.
    enum ViewMode: String, CaseIterable, Identifiable {
        case body = "Body"
        case list = "List"
        var id: String { rawValue }
    }
    // Body view is the default lens; `-listView` opens on the list (tests/demos).
    @State private var viewMode: ViewMode =
        ProcessInfo.processInfo.arguments.contains("-listView") ? .list : .body
    /// Tap a row to fix or complete an entry (voice extraction included).
    @State private var editingEvent: StoredEvent?

    private var groupedByDay: [(day: Date, events: [StoredEvent])] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.timestamp) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, events: $0.value.sorted { $0.timestamp > $1.timestamp }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    emptyState
                } else if viewMode == .body {
                    BodyMapView(events: events)
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section {
                                ForEach(group.events) { event in
                                    Button {
                                        editingEvent = event
                                    } label: {
                                        EventRow(event: event)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("timeline.event.\(event.id.uuidString)")
                                    .swipeActions(edge: .trailing) {
                                        Button("Delete", role: .destructive) {
                                            modelContext.delete(event)
                                            try? modelContext.save()
                                        }
                                    }
                                }
                            } header: {
                                Text(group.day, format: .dateTime.weekday(.wide).month().day())
                                    .font(.rounded(.footnote, weight: .semibold))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $viewMode) {
                        ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(events.count) entries")
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(item: $editingEvent) { event in
                EpisodeEditorView(.edit(event))
            }
        }
    }


    private var emptyState: some View {
        ContentUnavailableView(
            "Your healthspan record starts here",
            systemImage: "waveform.and.mic",
            description: Text("Tap Record to log how you're feeling — a few seconds of voice is enough.")
        )
    }
}

struct EventRow: View {
    let event: StoredEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SeverityBadge(severity: event.ratedSeverity)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.symptom.capitalized)
                        .font(.rounded(.body, weight: .semibold))
                    Spacer()
                    Text(event.timestamp, format: .dateTime.hour().minute())
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                }

                Text(event.transcript)
                    .font(.rounded(.callout))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if !event.medications.isEmpty {
                        let med = event.medications[0]
                        let effect = event.medicationHelped.map { $0 ? " ✓" : " ✗" } ?? ""
                        Chip(text: "💊 \(med)\(effect)", tint: event.medicationHelped == false ? .red : .purple)
                    }
                    if let aqi = event.aqi {
                        Chip(text: "AQI \(aqi)", tint: aqi > 100 ? .red : (aqi > 50 ? .orange : .green))
                    }
                    ForEach(event.triggers.prefix(2), id: \.self) { trigger in
                        Chip(text: trigger.displayName, tint: .gray)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct SeverityBadge: View {
    let severity: Int?

    var body: some View {
        Text(severity.map(String.init) ?? "–")
            .font(.rounded(.subheadline, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color.severity(severity), in: Circle())
            .accessibilityLabel(severity.map { "Severity \($0) out of 10" } ?? "Severity not rated")
    }
}

struct Chip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.rounded(.caption2, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}
