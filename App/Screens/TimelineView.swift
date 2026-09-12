import SwiftUI
import SwiftData
import HealthCore

struct TimelineView: View {
    @Query(sort: \StoredEvent.timestamp, order: .reverse) private var events: [StoredEvent]
    @State private var showingRecord = false

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
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section {
                                ForEach(group.events) { event in
                                    EventRow(event: event)
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
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(events.count) entries")
                        .font(.rounded(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                recordButton
            }
            .sheet(isPresented: $showingRecord) {
                RecordView()
            }
        }
    }

    private var recordButton: some View {
        Button {
            showingRecord = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.brandTeal)
                    .frame(width: 62, height: 62)
                    .shadow(color: Color.brandTeal.opacity(0.4), radius: 10, y: 4)
                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, 12)
        .accessibilityLabel("Record a new entry")
        .accessibilityIdentifier("timeline.record")
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
            SeverityBadge(severity: event.severity)

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
                        Chip(text: "💊 \(event.medications[0])", tint: .purple)
                    }
                    if let aqi = event.aqi {
                        Chip(text: "AQI \(aqi)", tint: aqi > 100 ? .red : (aqi > 50 ? .orange : .green))
                    }
                    ForEach(event.tags.prefix(2), id: \.self) { tag in
                        Chip(text: tag, tint: .gray)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct SeverityBadge: View {
    let severity: Int

    var body: some View {
        Text("\(severity)")
            .font(.rounded(.subheadline, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color.severity(severity), in: Circle())
            .accessibilityLabel("Severity \(severity) out of 10")
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
