import SwiftUI
import SwiftData
import HealthCore

/// Voice-first entry: tap the mic, speak, watch the live transcript, save.
/// If the note leaves high-value fields empty (did the med help? how long?),
/// the app asks up to two targeted follow-ups — spoken aloud via ElevenLabs,
/// always skippable, never blocking the save.
struct RecordView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    enum Phase {
        case idle
        case recording
        case review
        case followUp
    }

    @State private var phase: Phase = .idle
    @State private var transcript = ""
    @State private var extracted: HealthEvent?
    @State private var errorMessage: String?
    @State private var transcriber: (any Transcriber)?
    @State private var listenTask: Task<Void, Never>?
    @State private var isSaving = false

    // Follow-up state
    @State private var pendingEvent: HealthEvent?
    @State private var currentQuestion: FollowUpQuestion?
    @State private var followUpAnswer = ""
    @State private var questionsAsked = 0
    @State private var loggedAt = Date()
    @State private var prompter: VoicePrompter?

    private let previewIntelligence = MockIntelligence()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                if phase == .followUp, let question = currentQuestion {
                    followUpCard(question)
                } else {
                    micButton
                    Text(statusLine)
                        .font(.rounded(.footnote))
                        .foregroundStyle(.secondary)
                    transcriptEditor
                    if let extracted {
                        ExtractedPreview(event: extracted)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.rounded(.footnote))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                if phase != .followUp {
                    saveButton
                }
            }
            .padding()
            .background(Color.appBackground)
            .navigationTitle(phase == .followUp ? "One more thing" : "New entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        stopListening()
                        prompter?.stop()
                        dismiss()
                    }
                }
            }
            .onChange(of: transcript) {
                guard !transcript.isEmpty else { extracted = nil; return }
                // Live preview stays on the instant local extractor; the real
                // intelligence (Azure/Claude when available) runs once, on save.
                withAnimation(.snappy) {
                    extracted = previewIntelligence.extractEvent(from: transcript, at: loggedAt)
                }
            }
        }
    }

    // MARK: - Follow-up UI

    private func followUpCard(_ question: FollowUpQuestion) -> some View {
        VStack(spacing: 16) {
            Label("Quick follow-up", systemImage: "waveform.badge.mic")
                .font(.rounded(.caption, weight: .semibold))
                .foregroundStyle(Color.brandTeal)

            Text(question.prompt)
                .font(.rounded(.title3, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("followup.question")

            HStack(spacing: 12) {
                Button {
                    phase == .recording ? finishRecording() : startRecording()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.brandTeal))
                }
                .accessibilityIdentifier("followup.mic")

                TextField("Answer…", text: $followUpAnswer, axis: .vertical)
                    .font(.rounded(.body))
                    .lineLimit(1...3)
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("followup.answer")
            }

            HStack(spacing: 12) {
                Button("Skip") {
                    Task { await advanceFollowUps(merging: nil) }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("followup.skip")

                Button("Submit") {
                    Task { await advanceFollowUps(merging: followUpAnswer) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("followup.submit")
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusLine: String {
        switch phase {
        case .idle: "Tap to record — or type below"
        case .recording: "Listening… tap to stop"
        case .review: "Review and save"
        case .followUp: ""
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

    // MARK: - Recording

    private func startRecording() {
        errorMessage = nil
        if phase != .followUp {
            transcript = ""
            loggedAt = Date()
            phase = .recording
        }
        let transcriber = appEnvironment.makeTranscriber()
        self.transcriber = transcriber
        let intoFollowUp = currentQuestion != nil
        listenTask = Task {
            do {
                for try await partial in transcriber.transcribe() {
                    if intoFollowUp { followUpAnswer = partial } else { transcript = partial }
                }
                if phase == .recording { phase = .review }
            } catch {
                errorMessage = error.localizedDescription
                if phase == .recording { phase = transcript.isEmpty ? .idle : .review }
            }
        }
    }

    private func finishRecording() {
        stopListening()
        if phase == .recording { phase = .review }
    }

    private func stopListening() {
        transcriber?.stop()
        listenTask?.cancel()
        listenTask = nil
    }

    // MARK: - Save + follow-up loop

    private func save() {
        stopListening()
        guard let preview = extracted else { return }
        isSaving = true
        Task {
            // Final extraction via the real intelligence; local preview is the fallback.
            let event = (try? await appEnvironment.intelligence.extractEvent(
                from: transcript, at: loggedAt
            )) ?? preview
            pendingEvent = event
            isSaving = false
            await presentNextFollowUpOrFinish()
        }
    }

    private func advanceFollowUps(merging answer: String?) async {
        prompter?.stop()
        stopListening()
        guard let question = currentQuestion, var event = pendingEvent else { return }
        questionsAsked += 1
        currentQuestion = nil

        if let answer, !answer.isEmpty {
            // One code path: append the Q/A to the transcript and re-extract the
            // whole event so every field can benefit from the new information.
            let combined = event.transcript + "\nFollow-up — \(question.prompt)\nPatient answer: \(answer)"
            event = (try? await appEnvironment.intelligence.extractEvent(from: combined, at: loggedAt))
                ?? previewIntelligence.extractEvent(from: combined, at: loggedAt)
            pendingEvent = event
        }
        followUpAnswer = ""
        await presentNextFollowUpOrFinish()
    }

    private func presentNextFollowUpOrFinish() async {
        guard let event = pendingEvent else { return }
        let remaining = FollowUpQuestion.questions(for: event)
        if questionsAsked < 2, let next = remaining.first {
            currentQuestion = next
            phase = .followUp
            // Speak the question via ElevenLabs — pure garnish; failures are silent.
            if let key = appEnvironment.elevenLabsKey {
                let prompter = self.prompter ?? VoicePrompter(apiKey: key)
                self.prompter = prompter
                Task { await prompter.speak(next.prompt) }
            }
        } else {
            await finalize(event)
        }
    }

    private func finalize(_ event: HealthEvent) async {
        var event = event
        if let snapshot = try? await appEnvironment.environmentService.currentSnapshot() {
            event.environment = snapshot
        }
        modelContext.insert(StoredEvent(from: event))
        try? modelContext.save()
        dismiss()
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
                        Chip(text: event.bodyRegion == .systemic ? "General" : event.bodyRegion.displayName, tint: .brandTeal)
                        if !event.medications.isEmpty {
                            Chip(text: "💊 \(event.medications[0])", tint: .purple)
                        }
                        ForEach(event.triggers.prefix(2), id: \.self) { trigger in
                            Chip(text: trigger.displayName, tint: .gray)
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
