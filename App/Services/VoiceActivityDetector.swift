import Foundation
import AVFoundation

/// End-of-speech detection over raw mic buffers: speech must start first
/// (thinking pauses don't cut you off), then ~1.8s of silence ends the turn.
/// Also enforces a no-speech timeout and a hard cap.
struct VoiceActivityDetector {
    private(set) var speechStarted = false
    private var lastVoice = Date()
    private let began = Date()

    let voiceThreshold: Float = 0.015      // RMS amplitude ≈ -36 dB
    let silenceWindow: TimeInterval = 1.8
    let noSpeechTimeout: TimeInterval = 12
    let maxDuration: TimeInterval = 30

    /// Feed each tap buffer; returns true when listening should stop.
    mutating func shouldStop(after buffer: AVAudioPCMBuffer) -> Bool {
        if Self.rms(buffer) > voiceThreshold {
            speechStarted = true
            lastVoice = Date()
        }
        let now = Date()
        if now.timeIntervalSince(began) > maxDuration { return true }
        if speechStarted {
            return now.timeIntervalSince(lastVoice) > silenceWindow
        }
        return now.timeIntervalSince(began) > noSpeechTimeout
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return (sum / Float(n)).squareRoot()
    }
}
