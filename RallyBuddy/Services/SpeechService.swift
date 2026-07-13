import AVFoundation

/// Speaks co-driver style callouts, ducking any music or podcast audio.
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    init() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .voicePrompt,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
    }

    func say(_ text: String) {
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        synthesizer.speak(utterance)
    }
}
