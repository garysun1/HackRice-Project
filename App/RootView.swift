import SwiftUI
import SwiftData
import HealthCore

enum AppTab: String {
    case timeline, trends, briefing, connections
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \StoredEvent.timestamp) private var events: [StoredEvent]
    @State private var selection: AppTab = {
        // `-openTab briefing` jumps straight to a tab (screenshot loop + demo staging).
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-openTab"), index + 1 < args.count,
           let tab = AppTab(rawValue: args[index + 1]) {
            return tab
        }
        return .timeline
    }()
    @State private var showingRecord = false

    var body: some View {
        Group {
            switch selection {
            case .timeline: TimelineView()
            case .trends: TrendsView()
            case .briefing: BriefingView()
            case .connections: ConnectionsView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
        }
        .sheet(isPresented: $showingRecord) {
            RecordView()
        }
        // Regenerate the briefing in the background the moment the data it
        // summarizes changes (new/edited/deleted event, metrics entry), so the
        // Briefing tab opens instantly on an up-to-date cache.
        .task(id: briefingFingerprint) {
            appEnvironment.refreshBriefing(
                events: events.map(\.asHealthEvent),
                fingerprint: briefingFingerprint
            )
        }
    }

    /// Snapshot identity of everything the briefing consumes.
    private var briefingFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(events.count)
        for event in events {
            hasher.combine(event.id)
            hasher.combine(event.timestamp)
            hasher.combine(event.symptom)
            hasher.combine(event.severity)
            hasher.combine(event.bodyRegionRaw)
            hasher.combine(event.duration)
            hasher.combine(event.medications)
            hasher.combine(event.medicationHelped)
        }
        hasher.combine(appEnvironment.metricsVersion)
        return hasher.finalize()
    }

    /// Custom bar: four tabs around a raised central log button,
    /// macro-tracker style.
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.timeline, "Log", "waveform.and.mic")
            tabButton(.trends, "Trends", "chart.xyaxis.line")
            recordButton
            tabButton(.briefing, "Briefing", "doc.text.magnifyingglass")
            tabButton(.connections, "Connect", "link")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
        .overlay(
            RoundedRectangle(cornerRadius: 30)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppTab, _ title: String, _ icon: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                Text(title)
                    .font(.rounded(.caption2, weight: .medium))
            }
            .foregroundStyle(selection == tab ? Color.brandTeal : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }

    /// The central log action — vivid teal +, raised above the bar.
    private var recordButton: some View {
        Button {
            showingRecord = true
        } label: {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.brandTeal, Color.brandTeal.opacity(0.82)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 58, height: 58)
                    .shadow(color: Color.brandTeal.opacity(0.45), radius: 10, y: 4)
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            .offset(y: -14)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Log a new entry")
        .accessibilityIdentifier("tab.record")
    }
}

struct PlaceholderScreen: View {
    let title: String
    let note: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.brandTeal)
                Text(note)
                    .font(.rounded(.callout))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle(title)
            .background(Color.appBackground)
        }
    }
}

#Preview {
    RootView()
}
