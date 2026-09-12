import Foundation

/// Streaming speech-to-text seam. The app target provides `LiveTranscriber`
/// (SFSpeechRecognizer, lazy permission request); this package provides
/// `MockTranscriber` so every overnight/UI-test path is deterministic and the
/// speech permission prompt is never triggered.
public protocol Transcriber: Sendable {
    /// Emits growing partial transcripts, finishing with the final text.
    func transcribe() -> AsyncThrowingStream<String, Error>
    func stop()
}

public final class MockTranscriber: Transcriber {
    private let script: [String]
    private let interval: TimeInterval

    /// Emits each element of `script` in order, `interval` seconds apart.
    public init(
        script: [String] = MockTranscriber.defaultScript,
        interval: TimeInterval = 0.35
    ) {
        self.script = script
        self.interval = interval
    }

    public static let defaultScript: [String] = [
        "Used my",
        "Used my rescue inhaler",
        "Used my rescue inhaler twice this morning,",
        "Used my rescue inhaler twice this morning, chest tightness",
        "Used my rescue inhaler twice this morning, chest tightness after walking outside for about an hour."
    ]

    public func transcribe() -> AsyncThrowingStream<String, Error> {
        let script = self.script
        let interval = self.interval
        return AsyncThrowingStream { continuation in
            let task = Task {
                for line in script {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    continuation.yield(line)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func stop() {}
}
