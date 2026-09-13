import Foundation
import AVFoundation

/// Speaks follow-up questions aloud via ElevenLabs TTS. Every failure is
/// silent — the question always appears as on-screen text regardless, so
/// audio is pure garnish and can never block the flow.
final class VoicePrompter: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let apiKey: String
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    /// "Elise — Warm, Natural and Engaging" (ElevenLabs voice library):
    /// warm clinical register without the stock-AI sound.
    private let voiceID = "EST9Ui6982FZPSi7gCHi"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    /// Fetches and plays the spoken question; returns when playback ends
    /// (or immediately on any failure). Uses flash for lowest latency —
    /// questions are dynamic now, so there's nothing to cache.
    func speak(_ text: String) async {
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)?output_format=mp3_44100_128") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "voice_settings": [
                "stability": 0.55,
                "similarity_boost": 0.8,
                "speed": 1.04
            ]
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty
        else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard let player = try? AVAudioPlayer(data: data) else {
                continuation.resume()
                return
            }
            self.player = player
            self.finished = continuation
            player.delegate = self
            player.play()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finished?.resume()
        finished = nil
    }

    func stop() {
        player?.stop()
        finished?.resume()
        finished = nil
    }
}
