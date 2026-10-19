import AVFoundation
import Combine
import Foundation

/// Auditions are isolated from selected voices and translation playback.
/// Remote auditions only GET a provider's existing recording; never generate TTS.
@MainActor final class LabVoicePreview: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published private(set) var activeID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let speaker = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var download: Task<Void, Never>?
    private var generation = UUID()
    private var utterance: AVSpeechUtterance?
    private var ownsAudioSession = false

    override init() {
        super.init()
        speaker.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func audioInterrupted(_ notification: Notification) {
        // Never resume a sample unexpectedly after a call or Siri interruption.
        stop()
    }

    func stop() {
        generation = UUID()
        download?.cancel()
        download = nil
        player?.stop()
        player = nil
        utterance = nil
        speaker.stopSpeaking(at: .immediate)
        activeID = nil
        isLoading = false
        releaseAudio()
    }

    func playApple(voiceID: String, language: String) {
        let id = "apple:" + voiceID
        if activeID == id { stop(); return }
        stop()
        errorMessage = nil
        let availableVoice = voiceID.isEmpty
            ? AVSpeechSynthesisVoice(language: PartnerLanguage.voiceLocale(for: language))
            : AVSpeechSynthesisVoice(identifier: voiceID)
        guard let voice = availableVoice else {
            errorMessage = "Этот голос Apple больше недоступен. Обнови список голосов."
            return
        }
        do {
            try prepareAudio()
            let sample = AVSpeechUtterance(string: Self.sampleText(for: language))
            sample.voice = voice
            sample.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance = sample
            activeID = id
            speaker.speak(sample)
        } catch {
            releaseAudio()
            errorMessage = "Не удалось включить пробу голоса: \(error.localizedDescription)"
        }
    }

    func playRecorded(url: URL?, id: String) {
        if activeID == id { stop(); return }
        stop()
        errorMessage = nil
        guard let url, url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else {
            errorMessage = "У этого голоса нет готовой пробы. Выбери другой голос для прослушивания."
            return
        }
        let token = generation
        activeID = id
        isLoading = true
        download = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                // No API key is sent to preview storage/CDNs.
                let (bytes, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      bytes.count > 100, bytes.count < 20_000_000 else {
                    throw PreviewError.unavailable
                }
                let player = try AVAudioPlayer(data: bytes)
                player.delegate = self
                try self.prepareAudio()
                guard player.prepareToPlay(), player.play() else { throw PreviewError.unavailable }
                self.player = player
                self.isLoading = false
                self.download = nil
            } catch {
                guard let self, self.generation == token else { return }
                self.stop()
                if !(error is CancellationError) {
                    self.errorMessage = "Проба не воспроизвелась. Проверь подключение и попробуй ещё раз."
                }
            }
        }
    }

    private enum PreviewError: Error { case unavailable }
    private func prepareAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        ownsAudioSession = true
    }

    private func releaseAudio() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    static func sampleText(for language: String) -> String {
        switch language.lowercased().prefix(2) {
        case "ru": return "Привет! Так звучит мой голос в Interpreter Lab. Давай поговорим."
        case "de": return "Hallo! So klingt meine Stimme in Interpreter Lab. Lass uns sprechen."
        case "pl": return "Cześć! Tak brzmi mój głos w Interpreter Lab. Porozmawiajmy."
        case "es": return "¡Hola! Así suena mi voz en Interpreter Lab. Vamos a conversar."
        case "ro": return "Bună! Așa sună vocea mea în Interpreter Lab. Hai să vorbim."
        default: return "Hello! This is my voice in Interpreter Lab. Let's have a conversation."
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard self.utterance === utterance else { return }
        self.utterance = nil
        activeID = nil
        releaseAudio()
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard self.utterance === utterance else { return }
        self.utterance = nil
        activeID = nil
        releaseAudio()
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player else { return }
        self.player = nil
        activeID = nil
        releaseAudio()
        if !flag { errorMessage = "Не удалось воспроизвести пробу целиком." }
    }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player else { return }
        stop()
        errorMessage = "Запись пробы повреждена или недоступна."
    }
}
