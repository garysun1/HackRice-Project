import Foundation
import AVFoundation
import Speech
import HealthCore

/// Real speech-to-text via SFSpeechRecognizer. Authorization is requested lazily,
/// on first use only — overnight runs and UI tests always use MockTranscriber
/// (`--mock-speech`), so the permission prompt can never block an unattended run.
final class LiveTranscriber: NSObject, Transcriber, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Set when the user intentionally stops; any recognizer error after this
    /// point is post-stop noise ("no speech detected" etc.), not a failure.
    private var stopping = false
    /// Hands-free mode: end the turn automatically after end-of-speech silence.
    private let autoStopOnSilence: Bool
    private var vad = VoiceActivityDetector()

    init(autoStopOnSilence: Bool = false) {
        self.autoStopOnSilence = autoStopOnSilence
    }

    enum TranscriberError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized: "Speech recognition permission was not granted."
            case .recognizerUnavailable: "Speech recognition is unavailable on this device."
            }
        }
    }

    func transcribe() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else {
                    continuation.finish(throwing: TranscriberError.notAuthorized)
                    return
                }
                DispatchQueue.main.async {
                    do {
                        try self.start(continuation: continuation)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    private func start(continuation: AsyncThrowingStream<String, Error>.Continuation) throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let self, self.autoStopOnSilence, !self.stopping else { return }
            if self.vad.shouldStop(after: buffer) {
                DispatchQueue.main.async { self.stop() }
            }
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                continuation.yield(result.bestTranscription.formattedString)
                if result.isFinal {
                    continuation.finish()
                }
            }
            if let error {
                // After an intentional stop, or on cancellation codes, the
                // recognizer's trailing error is expected — finish cleanly.
                let code = (error as NSError).code
                if self.stopping || code == 301 || code == 216 {
                    continuation.finish()
                } else {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func stop() {
        stopping = true
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
    }
}
