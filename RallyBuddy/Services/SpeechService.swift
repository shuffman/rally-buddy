import AVFoundation

/// Speaks co-driver style callouts, ducking any music or podcast audio.
///
/// The audio session is activated when speech starts and deactivated once the
/// queue drains — leaving it active permanently kept background audio ducked
/// for the lifetime of the app after the very first callout.
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    /// The ObjC delegate surface lives in a shim so SpeechService stays a
    /// plain Swift class.
    private let speechDelegate = SpeechDelegate()

    init() {
        synthesizer.delegate = speechDelegate
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

/// Releases the audio session once the synthesizer goes quiet, handing audio
/// back to whatever was playing. Stateless — the synthesizer arrives as a
/// callback parameter, so there is nothing to store or synchronize.
private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        releaseSessionIfIdle(synthesizer)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        releaseSessionIfIdle(synthesizer)
    }

    /// Only deactivate once nothing else is queued — callouts often arrive in
    /// quick succession, and releasing between them would make the driver's
    /// music stutter.
    private func releaseSessionIfIdle(_ synthesizer: AVSpeechSynthesizer) {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
    }
}
