import SwiftUI
import SwiftData
import HealthCore

/// Voice-first entry: tap the mic, speak, watch the live transcript, save.
/// The same transcript field accepts typed text — the stage-safe fallback.
struct RecordView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Phase {
        case idle
        case recording
        case review
    }

    @State private var phase: Phase = .idle
    @State private var transcript = ""
    @State private var extracted: HealthEvent?
    @State private var errorMessage: String?
    @State private var transcriber: (any Transcriber)?
    @State private var listenTask: Task<Void, Never>?
    @State private var isSaving = false
    private let previewIntelligence = MockIntelligence()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                micButton

                Text(statusLine)
                    .font(.rounded(.footnote))
                    .foregroundStyle(.secondary)

                transcriptEditor

                if let extracted {
                    ExtractedPreview(event: extracted)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.rounded(.footnote))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                saveButton
            }
            .padding()
            .background(Color.appBackground)
            .navigationTitle("New entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        stopListening()
                        dismiss()
                    }
                }
            }
            .onChange(of: transcript) {
                guard !transcript.isEmpty else { extracted = nil; return }
                // Live preview stays on the instant local extractor; the real
                // intelligence (Claude when available) runs once, on save.
                withAnimation(.snappy) {
                    extracted = previewIntelligence.extractEvent(from: transcript, at: Date())
                }
            }
        }
    }

    private var statusLine: String {
        switch phase {
        case .idle: "Tap to record — or type below"
        case .recording: "Listening… tap to stop"
        case .review: "Review and save"
        }
    }

    private var micButton: some View {
        Button {
            phase == .recording ? finishRecording() : startRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(phase == .recording ? Color.red : Color.brandTeal)
                    .frame(width: 96, height: 96)
                    .shadow(color: (phase == .recording ? Color.red : .brandTeal).opacity(0.35), radius: 14, y: 6)
                Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
            .scaleEffect(phase == .recording ? 1.08 : 1.0)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: phase == .recording)
        }
        .accessibilityLabel(phase == .recording ? "Stop recording" : "Start recording")
        .accessibilityIdentifier("record.mic")
    }

    private var transcriptEditor: some View {
        TextField("How are you feeling?", text: $transcript, axis: .vertical)
            .font(.rounded(.body))
            .lineLimit(3...6)
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("record.transcript")
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text("Save to timeline")
                        .font(.rounded(.headline, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSaving || transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("record.save")
    }

    private func startRecording() {
        errorMessage = nil
        transcript = ""
        phase = .recording
        let transcriber = appEnvironment.makeTranscriber()
        self.transcriber = transcriber
        listenTask = Task {
            do {
                for try await partial in transcriber.transcribe() {
                    transcript = partial
                }
                if phase == .recording { phase = .review }
            } catch {
                errorMessage = error.localizedDescription
                phase = transcript.isEmpty ? .idle : .review
            }
        }
    }

    private func finishRecording() {
        stopListening()
        phase = .review
    }

    private func stopListening() {
        transcriber?.stop()
        listenTask?.cancel()
        listenTask = nil
    }

    private func save() {
        stopListening()
        guard let preview = extracted else { return }
        isSaving = true
        Task {
            // Final extraction via the real intelligence (Claude when a key is
            // present); the local preview is the guaranteed fallback.
            var event = (try? await appEnvironment.intelligence.extractEvent(
                from: transcript, at: preview.timestamp
            )) ?? preview
            if let snapshot = try? await appEnvironment.environmentService.currentSnapshot() {
                event.environment = snapshot
            }
            modelContext.insert(StoredEvent(from: event))
            try? modelContext.save()
            isSaving = false
            dismiss()
        }
    }
}

/// Live preview of what the intelligence layer extracted from the transcript.
struct ExtractedPreview: View {
    let event: HealthEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Understood", systemImage: "sparkles")
                .font(.rounded(.caption, weight: .semibold))
                .foregroundStyle(Color.brandTeal)

            HStack(spacing: 8) {
                SeverityBadge(severity: event.severity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.symptom.capitalized)
                        .font(.rounded(.body, weight: .semibold))
                    HStack(spacing: 6) {
                        if !event.medications.isEmpty {
                            Chip(text: "💊 \(event.medications[0])", tint: .purple)
                        }
                        ForEach(event.tags.prefix(3), id: \.self) { tag in
                            Chip(text: tag, tint: .gray)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("record.preview")
    }
}
