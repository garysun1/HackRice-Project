import SwiftUI
import SwiftData
import HealthCore

/// Voice-first entry: tap the mic, speak, watch the transcript, save.
/// If the note leaves high-value fields empty, the app asks up to two
/// model-phrased follow-ups — spoken aloud (Elise / ElevenLabs), answered
/// hands-free: it listens after asking and detects when you stop talking.
/// Always skippable, never blocks the save.
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

    enum FollowUpStage {
        case speaking, listening, thinking, manual
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
    @State private var currentQuestionText: String?
    @State private var currentQuestionKind: String?
    /// Kinds already asked (answered OR skipped) — never re-ask the same field.
    @State private var askedKinds: Set<String> = []
    @State private var followUpStage: FollowUpStage = .manual
    /// Set only when Submit is tapped mid-listen; the stream's end then
    /// advances. A stream that ends any other way (recognizer finalized on a
    /// pause, engine error) must NOT advance — only Submit ever does.
    @State private var followUpSubmitRequested = false
    @State private var followUpAnswer = ""
    @State private var questionsAsked = 0
    @State private var loggedAt = Date()
    @State private var prompter: VoicePrompter?

    private let previewIntelligence = MockIntelligence()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                if phase == .followUp, let question = currentQuestionText {
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

    private func followUpCard(_ question: String) -> some View {
        VStack(spacing: 16) {
            Label("Quick follow-up", systemImage: "waveform.badge.mic")
                .font(.rounded(.caption, weight: .semibold))
                .foregroundStyle(Color.brandTeal)

            Text(question)
                .font(.rounded(.title3, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("followup.question")

            HStack(spacing: 12) {
                Button {
                    if followUpStage == .listening {
                        finishFollowUpTurn()
                    } else {
                        followUpStage = .listening
                        startRecording()
                    }
                } label: {
                    Image(systemName: followUpStage == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(followUpStage == .listening ? Color.red : Color.brandTeal))
                }
                .disabled(followUpStage == .thinking)
                .accessibilityIdentifier("followup.mic")

                TextField("…or type your answer", text: $followUpAnswer, axis: .vertical)
                    .font(.rounded(.body))
                    .lineLimit(1...3)
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("followup.answer")
                    .onSubmit { submitFollowUp() }
            }

            Button {
                submitFollowUp()
            } label: {
                Group {
                    if followUpStage == .thinking {
                        ProgressView().tint(.white)
                    } else {
                        Text("Submit")
                            .font(.rounded(.headline, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(followUpStage == .thinking)
            .accessibilityIdentifier("followup.submit")
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Submit ends the turn — and ONLY Submit. While listening it flags the
    /// intent and stops the transcriber; the stream's end then advances with
    /// the final text (cloud STT arrives after stop). Otherwise it advances
    /// with whatever is in the field. An empty answer counts as a skip.
    private func submitFollowUp() {
        if followUpStage == .listening {
            followUpSubmitRequested = true
            followUpStage = .thinking
            transcriber?.stop()
        } else {
            Task { await advanceFollowUps(merging: followUpAnswer) }
        }
    }

    private func finishFollowUpTurn() {
        // Mic stop: end the listen without submitting; the stream's end drops
        // us back to manual with the captured text still in the field.
        followUpStage = .thinking
        transcriber?.stop()
    }

    private var statusLine: String {
        switch phase {
        case .idle: "Tap to record"
        case .recording: "Listening… tap to stop"
        case .review: transcript.isEmpty ? "Transcribing…" : "Review and save"
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
        let intoFollowUp = currentQuestionText != nil
        if !intoFollowUp {
            transcript = ""
            loggedAt = Date()
            phase = .recording
        }
        // No silence auto-stop: the turn ends when the user taps Submit
        // (or the mic's stop button).
        let transcriber = appEnvironment.makeTranscriber()
        self.transcriber = transcriber
        listenTask = Task {
            do {
                for try await partial in transcriber.transcribe() {
                    if intoFollowUp { followUpAnswer = partial } else { transcript = partial }
                }
                if intoFollowUp {
                    let answer = followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if followUpSubmitRequested {
                        followUpSubmitRequested = false
                        // Fresh task: advanceFollowUps cancels listenTask,
                        // which is what's running this continuation.
                        Task { await advanceFollowUps(merging: answer.isEmpty ? nil : answer) }
                    } else {
                        // Stream ended on its own (recognizer pause-finalized,
                        // mic stop tapped) — keep the text, wait for Submit.
                        followUpStage = .manual
                    }
                } else if phase == .recording {
                    phase = .review
                }
            } catch {
                if intoFollowUp {
                    // STT hiccup on a follow-up: if Submit was already tapped,
                    // advance with whatever text we have; otherwise just fall
                    // back to manual and wait for the user.
                    let answer = followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if followUpSubmitRequested {
                        followUpSubmitRequested = false
                        Task { await advanceFollowUps(merging: answer.isEmpty ? nil : answer) }
                    } else {
                        followUpStage = .manual
                    }
                    return
                }
                // If we already captured text, a trailing recognizer error is
                // noise — keep the transcript and stay quiet.
                if transcript.isEmpty {
                    let nsError = error as NSError
                    if nsError.domain.contains("SFSpeech") || nsError.domain.hasPrefix("kAF")
                        || nsError.localizedDescription.localizedCaseInsensitiveContains("recognizer") {
                        errorMessage = "Voice input isn't available here — type your note below instead."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
                if phase == .recording { phase = transcript.isEmpty ? .idle : .review }
            }
        }
    }

    private func finishRecording() {
        // Ask the transcriber to stop, but DON'T cancel the listen task:
        // cloud transcribers (Simulator/ElevenLabs) deliver the final text
        // after stop. Safety timeout cancels a hung stream.
        transcriber?.stop()
        if phase == .recording { phase = .review }
        let task = listenTask
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            task?.cancel()
        }
    }

    private func stopListening() {
        transcriber?.stop()
        listenTask?.cancel()
        listenTask = nil
    }

    // MARK: - Save + conversational follow-up loop

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
        guard let question = currentQuestionText, var event = pendingEvent else { return }
        prompter?.stop()
        stopListening()
        questionsAsked += 1
        if let kind = currentQuestionKind { askedKinds.insert(kind) }
        currentQuestionKind = nil
        currentQuestionText = nil
        followUpStage = .thinking
        phase = .followUp  // keep the card up while thinking

        if let answer, !answer.isEmpty {
            currentQuestionText = question  // keep question visible during merge
            followUpStage = .thinking
            // One code path: append the Q/A to the transcript and re-extract the
            // whole event so every field can benefit from the new information.
            let combined = event.transcript + "\nFollow-up — \(question)\nPatient answer: \(answer)"
            event = (try? await appEnvironment.intelligence.extractEvent(from: combined, at: loggedAt))
                ?? previewIntelligence.extractEvent(from: combined, at: loggedAt)
            pendingEvent = event
            currentQuestionText = nil
        }
        followUpAnswer = ""
        await presentNextFollowUpOrFinish()
    }

    private func presentNextFollowUpOrFinish() async {
        guard let event = pendingEvent else { return }
        let missing = FollowUpQuestion.questions(for: event)
        guard questionsAsked < 2,
              let template = missing.first(where: { !askedKinds.contains(questionKind($0)) }) else {
            await finalize(event)
            return
        }
        // Model-phrased question when it targets the field we're asking about
        // (keeps phrasing conversational); template phrasing otherwise, so a
        // stray off-topic question can never mislabel the answer.
        let modelQuestion = (template == missing.first ? event.suggestedFollowUp : nil)
            .flatMap { questionMatchesTopic($0, template) ? $0 : nil }
        let text = modelQuestion ?? template.prompt(for: event)
        currentQuestionKind = questionKind(template)
        currentQuestionText = text
        phase = .followUp
        followUpStage = .speaking

        // Speak, then open the mic hands-free (unless in deterministic test mode).
        if let key = appEnvironment.elevenLabsKey {
            let prompter = self.prompter ?? VoicePrompter(apiKey: key)
            self.prompter = prompter
            await prompter.speak(text)
        }
        guard currentQuestionText == text else { return }  // skipped mid-speech
        if appEnvironment.autoConversation {
            followUpStage = .listening
            startRecording()
        } else {
            followUpStage = .manual
        }
    }

    /// Loose topical check that a model-phrased question actually asks about
    /// the field the completeness check selected.
    private func questionMatchesTopic(_ text: String, _ template: FollowUpQuestion) -> Bool {
        let t = text.lowercased()
        return switch template {
        case .bodyRegion: t.contains("where") || t.contains("which") || t.contains("side") || t.contains("part")
        case .severity: t.contains("10") || t.contains("how bad") || t.contains("scale") || t.contains("rate") || t.contains("severe")
        case .medicationEffect: t.contains("help") || t.contains("relie") || t.contains("work") || t.contains("better") || t.contains("ease")
        case .duration: t.contains("long") || t.contains("last") || t.contains("still")
        }
    }

    private func questionKind(_ question: FollowUpQuestion) -> String {
        switch question {
        case .bodyRegion: "region"
        case .severity: "severity"
        case .medicationEffect: "medication"
        case .duration: "duration"
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

            // No severity badge here: the rating is patient-stated and isn't
            // known until the follow-up is answered.
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.symptom.capitalized)
                        .font(.rounded(.body, weight: .semibold))
                    HStack(spacing: 6) {
                        Chip(text: event.bodyRegion.displayName, tint: .brandTeal)
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
