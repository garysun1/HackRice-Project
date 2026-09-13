import SwiftUI
import SwiftData
import HealthCore

/// "Prep my visit": one generator, two renderings — a clinician-style note and
/// a plain-language patient view, with share-sheet export.
struct BriefingView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Query(sort: \StoredEvent.timestamp) private var stored: [StoredEvent]

    enum Audience: String, CaseIterable, Identifiable {
        case clinician = "For your doctor"
        case patient = "For you"
        var id: String { rawValue }
    }

    @State private var audience: Audience = .clinician

    /// Generated in the background by AppEnvironment whenever data changes
    /// (see RootView's fingerprint watcher) — this view only renders the cache.
    private var briefing: VisitBriefing? { appEnvironment.briefing }

    var body: some View {
        NavigationStack {
            Group {
                if stored.isEmpty {
                    ContentUnavailableView(
                        "Nothing to brief yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Log a few entries and Breathing Room will prepare a visit summary.")
                    )
                } else if let briefing {
                    // Stale-while-revalidate: show the last ready briefing
                    // instantly; a refresh indicator marks an in-flight update.
                    briefingContent(briefing)
                } else {
                    // Only reachable when data changed and generation hasn't
                    // finished its first pass yet.
                    ProgressView("Preparing your briefing…")
                }
            }
            .navigationTitle("Prep my visit")
            .toolbar {
                if appEnvironment.briefingInFlight, briefing != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("Updating…")
                                .font(.rounded(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let briefing {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: exportText(briefing)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share briefing")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func briefingContent(_ briefing: VisitBriefing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Audience", selection: $audience) {
                    ForEach(Audience.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text("Covers \(briefing.periodStart, format: .dateTime.month().day()) – \(briefing.periodEnd, format: .dateTime.month().day())")
                    .font(.rounded(.caption))
                    .foregroundStyle(.secondary)

                switch audience {
                case .clinician: clinicianSections(briefing.clinicianNote)
                case .patient: patientSections(briefing.patientView)
                }
            }
            .padding()
        }
        .background(Color.appBackground)
    }

    @ViewBuilder
    private func clinicianSections(_ note: VisitBriefing.ClinicianNote) -> some View {
        BriefingCard(title: "Chief concerns", systemImage: "exclamationmark.bubble") {
            Text(note.chiefConcerns)
        }
        BriefingCard(title: "Frequency & severity", systemImage: "gauge.with.needle") {
            Text(note.frequencyAndSeverity)
        }
        BriefingCard(title: "Correlations", systemImage: "arrow.triangle.branch") {
            ForEach(note.correlations, id: \.self) { line in
                Label(line, systemImage: "circle.fill")
                    .labelStyle(BulletLabelStyle())
            }
        }
        BriefingCard(title: "Medication", systemImage: "pills") {
            Text(note.medicationNotes)
        }
        BriefingCard(title: "Episode timeline", systemImage: "list.bullet.rectangle") {
            ForEach(note.episodeTimeline, id: \.self) { line in
                Text(line)
                    .font(.rounded(.footnote))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func patientSections(_ view: VisitBriefing.PatientView) -> some View {
        BriefingCard(title: "The last few months", systemImage: "calendar") {
            Text(view.summary)
        }
        BriefingCard(title: "Bring these up", systemImage: "bubble.left.and.text.bubble.right") {
            ForEach(view.talkingPoints, id: \.self) { line in
                Label(line, systemImage: "circle.fill")
                    .labelStyle(BulletLabelStyle())
            }
        }
        BriefingCard(title: "Questions to ask", systemImage: "questionmark.circle") {
            ForEach(view.questions, id: \.self) { line in
                Label(line, systemImage: "circle.fill")
                    .labelStyle(BulletLabelStyle())
            }
        }
    }

    private func exportText(_ briefing: VisitBriefing) -> String {
        let note = briefing.clinicianNote
        return """
        BREATHING ROOM — VISIT BRIEFING
        Covers \(briefing.periodStart.formatted(date: .abbreviated, time: .omitted)) – \(briefing.periodEnd.formatted(date: .abbreviated, time: .omitted))

        CHIEF CONCERNS
        \(note.chiefConcerns)

        FREQUENCY & SEVERITY
        \(note.frequencyAndSeverity)

        CORRELATIONS
        \(note.correlations.map { "• \($0)" }.joined(separator: "\n"))

        MEDICATION
        \(note.medicationNotes)

        EPISODE TIMELINE
        \(note.episodeTimeline.map { "• \($0)" }.joined(separator: "\n"))

        Generated by Breathing Room — data stays on device.
        """
    }
}

struct BriefingCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.rounded(.subheadline, weight: .semibold))
                .foregroundStyle(Color.brandTeal)
            content
                .font(.rounded(.callout))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon
                .font(.system(size: 5))
                .foregroundStyle(Color.brandTeal)
            configuration.title
        }
    }
}
