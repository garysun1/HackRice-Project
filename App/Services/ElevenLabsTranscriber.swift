import Foundation
import AVFoundation
import HealthCore

/// Cloud speech-to-text via ElevenLabs Scribe. Records the microphone to a
/// temp WAV, uploads on stop, and yields the final transcript. Used where
/// Apple's SFSpeechRecognizer can't run (the Simulator); the iPhone build
/// keeps on-device recognition.
final class ElevenLabsTranscriber: NSObject, Transcriber, @unchecked Sendable {
    private let apiKey: String
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var stopped = false
    /// Hands-free mode: end the turn automatically after end-of-speech silence.
    private let autoStopOnSilence: Bool
    private var vad = VoiceActivityDetector()

    enum STTError: LocalizedError {
        case recordingFailed
        case httpError(Int, String)
        case emptyTranscript
        var errorDescription: String? {
            switch self {
            case .recordingFailed: "Couldn't start the microphone."
            case .httpError(let code, let body): "Transcription failed (\(code)): \(body.prefix(120))"
            case .emptyTranscript: "Didn't catch that — try again or type below."
            }
        }
    }

    init(apiKey: String, autoStopOnSilence: Bool = false) {
        self.apiKey = apiKey
        self.autoStopOnSilence = autoStopOnSilence
    }

    func transcribe() -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            do {
                try startRecording()
            } catch {
                continuation.finish(throwing: error)
            }
            continuation.onTermination = { [weak self] _ in
                self?.teardownEngine()
            }
        }
    }

    private func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw STTError.recordingFailed }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("note-\(UUID().uuidString).wav")
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        _ = settings // (kept explicit for clarity)
        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        self.file = audioFile
        self.fileURL = url

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            try? self.file?.write(from: buffer)
            if self.autoStopOnSilence, !self.stopped, self.vad.shouldStop(after: buffer) {
                DispatchQueue.main.async { self.stop() }
            }
        }
        engine.prepare()
        try engine.start()
    }

    private func teardownEngine() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        teardownEngine()
        file = nil  // flush/close

        guard let url = fileURL, let continuation else { return }
        Task {
            do {
                let text = try await Self.transcribeFile(at: url, apiKey: apiKey)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continuation.finish(throwing: STTError.emptyTranscript)
                } else {
                    continuation.yield(trimmed)
                    continuation.finish()
                }
            } catch {
                continuation.finish(throwing: error)
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func transcribeFile(at url: URL, apiKey: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.timeoutInterval = 30

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model_id", "scribe_v1")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"note.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: url))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw STTError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        struct Result: Decodable { let text: String }
        return try JSONDecoder().decode(Result.self, from: data).text
    }
}
