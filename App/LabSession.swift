import Foundation
import AVFoundation
import UIKit
import SwiftUI

@MainActor final class LabSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    enum Phase: Equatable { case idle, arming, recording, recognizing, translating, preparingVoice, playing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var held: String?
    @Published private(set) var message = "Удерживай кнопку нужного языка"
    @Published var source = ""
    @Published private(set) var translation = ""
    @Published private(set) var language = "ru"
    @Published private(set) var partner = PartnerLanguage.current(UserDefaults.standard.string(forKey: "lab.partnerLanguage") ?? "de")
    @Published private(set) var levels = Array(repeating: 0.0, count: 40)
    @Published private(set) var visualBands: LabAudioBands = .silence
    @Published private(set) var elapsed = 0.0
    @Published private(set) var detail = ""
    @Published private(set) var keySaved = false
    // Prefer account subscription; paid API is optional.
    @Published var authSource: String = UserDefaults.standard.string(forKey: "lab.authSource") ?? "chatgpt" {
        didSet { UserDefaults.standard.set(authSource, forKey: "lab.authSource") }
    }
    @Published private(set) var chatGPTAccount = ""
    @Published private(set) var chatGPTModels: [ModelChoice] = []
    @Published var chatGPTModel: String = UserDefaults.standard.string(forKey: "lab.chatGPTModel") ?? "" {
        didSet { UserDefaults.standard.set(chatGPTModel, forKey: "lab.chatGPTModel") }
    }
    @Published var modelID: String = UserDefaults.standard.string(forKey: "lab.model") ?? "gpt-4.1-mini" {
        didSet { UserDefaults.standard.set(modelID, forKey: "lab.model") }
    }
    @Published var autoSpeak: Bool = (UserDefaults.standard.object(forKey: "lab.autoSpeak") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoSpeak, forKey: "lab.autoSpeak") }
    }
    @Published var selectedPartnerVoiceID = "" {
        didSet { UserDefaults.standard.set(selectedPartnerVoiceID, forKey: "lab.voice.\(partner.rawValue)") }
    }
    @Published var russianVoiceID: String = UserDefaults.standard.string(forKey: "lab.voice.ru") ?? "" {
        didSet { UserDefaults.standard.set(russianVoiceID, forKey: "lab.voice.ru") }
    }

    private let capture = LabSpeechCapture()
    private let speaker = AVSpeechSynthesizer()
    private let renderedSpeech = LabSpeechExporter()
    private var currentUtterance: AVSpeechUtterance?
    private var outputPlayer: AVAudioPlayer?
    private var outputSpectrum: LabPlaybackSpectrum?
    private var playbackMeter: Task<Void, Never>?
    private var cachedSpeech: (text: String, voiceID: String, url: URL, spectrum: LabPlaybackSpectrum)?
    private var watchdog: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var recordingStarted = Date()
    private var lastMicrophoneVisualUpdate = 0.0
    private var pendingMicrophoneBands: LabAudioBands = .silence
    private var translationTarget = "de"

    var busy: Bool { phase != .idle && phase != .playing }
    var canBegin: Bool { phase == .idle || phase == .playing }
    var canReplay: Bool { !translation.isEmpty && phase == .idle }
    var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Interpreter Lab \(version) (\(build))"
    }

    override init() {
        super.init()
        selectedPartnerVoiceID = UserDefaults.standard.string(forKey: "lab.voice.\(partner.rawValue)") ?? ""
        speaker.delegate = self
        refreshKey()
        chatGPTAccount = (try? SessionStore.load())?.email ?? ""
    }

    func loadChatGPTModels() async throws {
        guard let saved = try SessionStore.load() else {
            throw Failure.message("Сначала войди через ChatGPT.")
        }
        let current = try await OpenAI.refresh(saved)
        let available = try await OpenAI.models(current)
        chatGPTAccount = current.email
        chatGPTModels = available
        if !available.contains(where: { $0.id == chatGPTModel }) {
            chatGPTModel = available.first?.id ?? ""
        }
        if chatGPTModel.isEmpty { throw Failure.message("Для этого аккаунта нет доступных текстовых моделей.") }
    }

    func disconnectChatGPT() throws {
        try SessionStore.clear()
        chatGPTAccount = ""
        chatGPTModels = []
        chatGPTModel = ""
    }

    func refreshKey() { keySaved = (try? LabKeychain.load()) != nil }
    func saveKey(_ key: String) throws { try LabKeychain.save(key); refreshKey() }
    func deleteKey() throws { try LabKeychain.delete(); refreshKey() }

    func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(language) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // Language selection remains disabled during recording, translation and playback,
    // exactly as in Interpreter Live's orbit picker.
    func setPartner(_ choice: PartnerLanguage) {
        guard phase == .idle && held == nil else { return }
        guard choice != partner else { return }
        partner = choice
        selectedPartnerVoiceID = UserDefaults.standard.string(forKey: "lab.voice.\(choice.rawValue)") ?? ""
        language = "ru"
        source = ""
        translation = ""
        detail = ""
        translationTarget = choice.rawValue
        message = "Готово · \(choice.name) ↔ Русский"
    }

    func begin(_ lang: String) {
        guard canBegin && held == nil && (lang == "ru" || lang == partner.rawValue) else { return }
        haltPlayback()
        operation?.cancel()
        capture.cancel()
        generation = UUID()
        let token = generation
        language = lang
        held = lang
        source = ""
        translation = ""
        detail = ""
        levels = Array(repeating: 0, count: 40)
        visualBands = .silence
        lastMicrophoneVisualUpdate = 0
        pendingMicrophoneBands = .silence
        clearCachedSpeech()
        elapsed = 0
        phase = .arming
        message = "Готовлю микрофон · пока не говори"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.capture.start(
                    locale: lang == "ru" ? "ru-RU" : partner.speechLocale,
                    onText: { [weak self] value in
                        guard let self, self.generation == token else { return }
                        self.source = value
                    },
                    onLevel: { [weak self] value in
                        guard let self, self.generation == token && self.phase == .recording else { return }
                        // Avoid re-rendering the entire SwiftUI screen at mic tap rate.
                        // 20 Hz is enough for expressive light while Core Animation stays smooth.
                        let now = ProcessInfo.processInfo.systemUptime
                        guard now - self.lastMicrophoneVisualUpdate >= 0.05 else { return }
                        self.lastMicrophoneVisualUpdate = now
                        self.levels.removeFirst()
                        self.levels.append(value)
                        self.visualBands = self.pendingMicrophoneBands
                        self.elapsed = Date().timeIntervalSince(self.recordingStarted)
                    },
                    onBands: { [weak self] bands in
                        guard let self, self.generation == token && self.phase == .recording else { return }
                        self.pendingMicrophoneBands = bands
                    },
                    onFinish: { [weak self] result in
                        guard let self, self.generation == token else { return }
                        self.held = nil
                        switch result {
                        case .success(let text):
                            self.source = text
                            self.phase = .idle
                            self.translate()
                        case .failure(let error):
                            self.phase = .idle
                            self.message = "Распознавание: \(error.localizedDescription)"
                        }
                    }
                )
                guard self.generation == token && self.held == lang else {
                    self.capture.cancel()
                    return
                }
                self.recordingStarted = Date()
                self.phase = .recording
                self.message = "Говори → отпусти для перевода"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                guard self.generation == token else { return }
                self.held = nil
                self.capture.cancel()
                self.phase = .idle
                self.message = "Микрофон: \(error.localizedDescription)"
            }
        }
    }

    func end(_ lang: String) {
        guard held == lang else { return }
        held = nil
        if phase == .arming {
            stopAll(message: "Запись не началась. Удерживай до вибросигнала.")
            return
        }
        guard phase == .recording else { return }
        elapsed = Date().timeIntervalSince(recordingStarted)
        phase = .recognizing
        visualBands = .silence
        message = "Микрофон выключен · завершаю распознавание"
        capture.finish()
    }

    func abort(_ lang: String) {
        guard held == lang else { return }
        stopAll(message: "Запись отменена")
    }

    func translate() {
        guard phase == .idle, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if phase == .idle { message = "Нет текста для перевода" }
            return
        }
        if authSource == "chatgpt" {
            guard (try? SessionStore.load()) != nil else {
                message = "Текст распознан. Войди через ChatGPT в настройках."
                return
            }
            guard !chatGPTModel.isEmpty else {
                message = "Выбери модель ChatGPT в настройках."
                return
            }
        } else if !keySaved {
            message = "Текст распознан. Добавь API-ключ OpenAI в настройках."
            return
        }
        operation?.cancel()
        generation = UUID()
        let token = generation
        let input = source
        let from = language
        let selectedSource = authSource
        let model = selectedSource == "chatgpt" ? chatGPTModel : modelID
        translationTarget = from == "ru" ? partner.rawValue : "ru"
        translation = ""
        clearCachedSpeech()
        phase = .translating
        message = "OpenAI · перевожу готовую фразу"
        detail = "\(from == "ru" ? "Русский → \(partner.name)" : "\(partner.name) → Русский") · \(model) · \(selectedSource == "chatgpt" ? "ChatGPT" : "API")"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let bearer: String
                if selectedSource == "chatgpt" {
                    guard let saved = try SessionStore.load() else {
                        throw Failure.message("Войди через ChatGPT в настройках.")
                    }
                    let session = try await OpenAI.refresh(saved)
                    bearer = session.accessToken
                } else {
                    guard let key = try LabKeychain.load() else {
                        throw Failure.message("Добавь API-ключ OpenAI в настройках.")
                    }
                    bearer = key
                }
                let value = try await LabTranslator.translate(input, source: from, target: self.translationTarget, model: model, bearerToken: bearer)
                guard self.generation == token && !Task.isCancelled else { return }
                self.translation = value
                self.phase = .idle
                self.message = "Перевод готов · \(self.autoSpeak ? "озвучиваю" : "нажми «Прослушать»")"
                if self.autoSpeak { self.speak() }
            } catch {
                guard self.generation == token else { return }
                self.phase = .idle
                self.message = "Перевод: \(error.localizedDescription)"
            }
        }
    }

    func replay() {
        guard canReplay else { return }
        speak()
    }

    private func speak() {
        guard !translation.isEmpty else { return }
        haltPlayback()
        let utterance = AVSpeechUtterance(string: translation)
        let storedID = translationTarget == "ru" ? russianVoiceID :
            UserDefaults.standard.string(forKey: "lab.voice.\(translationTarget)") ?? ""
        utterance.voice = AVSpeechSynthesisVoice(identifier: storedID)
            ?? AVSpeechSynthesisVoice(language: PartnerLanguage.voiceLocale(for: translationTarget))
        guard let voice = utterance.voice else {
            phase = .idle
            message = "Голос Apple для этого языка недоступен. Установи его в настройках iPhone."
            return
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        visualBands = .silence

        // Exact rendered Apple speech PCM drives both the sound and the animation.
        // Keep the original speak() API as a safe fallback if offline rendering fails.
        phase = .preparingVoice
        message = "Apple TTS · подготавливаю звук для визуализации"
        let token = generation
        let text = translation
        operation?.cancel()
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                let url: URL
                let spectrum: LabPlaybackSpectrum
                if let cached = self.cachedSpeech,
                   cached.text == text && cached.voiceID == voice.identifier {
                    url = cached.url
                    spectrum = cached.spectrum
                } else {
                    url = try await self.renderedSpeech.render(utterance)
                    guard self.generation == token && !Task.isCancelled else {
                        try? FileManager.default.removeItem(at: url)
                        return
                    }
                    spectrum = try LabPlaybackSpectrum(url: url)
                    self.clearCachedSpeech()
                    self.cachedSpeech = (text, voice.identifier, url, spectrum)
                }
                guard self.generation == token && !Task.isCancelled else { return }
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try audioSession.setActive(true)
                let player = try AVAudioPlayer(contentsOf: url)
                player.isMeteringEnabled = true
                player.delegate = self
                guard player.prepareToPlay(), player.play() else {
                    throw Failure.message("Не удалось запустить воспроизведение аудиофайла Apple.")
                }
                self.outputPlayer = player
                self.outputSpectrum = spectrum
                self.phase = .playing
                self.message = "Звучит перевод · Graphite реагирует на Apple TTS"
                self.startPlaybackMeter(token: token, player: player, spectrum: spectrum)
            } catch {
                guard self.generation == token && !Task.isCancelled else { return }
                self.playRegularAppleVoice(utterance, token: token)
            }
        }
    }

    private func startPlaybackMeter(token: UUID, player: AVAudioPlayer,
                                    spectrum: LabPlaybackSpectrum) {
        playbackMeter?.cancel()
        playbackMeter = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == token,
                      self.phase == .playing, self.outputPlayer === player else { return }
                if !player.isPlaying { return }
                player.updateMeters()
                let loudness = pow(10, Double(player.averagePower(forChannel: 0)) / 20) * 9
                let current = spectrum.bands(at: player.currentTime)
                let factor = min(1, max(0, loudness))
                // File spectrum gives timbre; AVAudioPlayer meter gates real silence.
                self.visualBands = LabAudioBands(
                    low: current.low * factor,
                    mid: current.mid * factor,
                    high: current.high * factor
                )
                self.levels.removeFirst()
                self.levels.append(self.visualBands.overall)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func playRegularAppleVoice(_ utterance: AVSpeechUtterance, token: UUID) {
        renderedSpeech.cancel()
        guard generation == token else { return }
        visualBands = .silence
        currentUtterance = utterance
        phase = .playing
        message = "Звучит перевод · Apple TTS (резервное воспроизведение)"
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            phase = .idle
            currentUtterance = nil
            message = "Не удалось включить динамик: \(error.localizedDescription)"
            return
        }
        speaker.speak(utterance)
        watchdog?.cancel()
        let timeout = max(45, min(240, Double(translation.count) * 0.24))
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, let self, self.generation == token,
                  self.currentUtterance === utterance else { return }
            self.haltPlayback()
            self.phase = .idle
            self.message = "Озвучивание остановлено по тайм-ауту. Можно прослушать снова."
        }
    }

    private func clearCachedSpeech() {
        if let cachedSpeech {
            try? FileManager.default.removeItem(at: cachedSpeech.url)
        }
        cachedSpeech = nil
    }

    private func haltPlayback() {
        watchdog?.cancel()
        watchdog = nil
        playbackMeter?.cancel()
        playbackMeter = nil
        renderedSpeech.cancel()
        currentUtterance = nil
        outputPlayer?.stop()
        outputPlayer = nil
        outputSpectrum = nil
        visualBands = .silence
        if speaker.isSpeaking || speaker.isPaused { speaker.stopSpeaking(at: .immediate) }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard outputPlayer === player else { return }
        playbackMeter?.cancel()
        playbackMeter = nil
        outputPlayer = nil
        outputSpectrum = nil
        visualBands = .silence
        levels = Array(repeating: 0, count: 40)
        phase = .idle
        message = flag ? "Готово · удерживай кнопку языка" : "Воспроизведение прервалось · можно повторить"
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard outputPlayer === player else { return }
        haltPlayback()
        phase = .idle
        message = "Ошибка воспроизведения звука · повтори прослушивание"
    }

    func stopAll(message newMessage: String = "Остановлено · удерживай кнопку языка") {
        generation = UUID()
        operation?.cancel()
        operation = nil
        capture.cancel()
        haltPlayback()
        clearCachedSpeech()
        held = nil
        levels = Array(repeating: 0, count: 40)
        phase = .idle
        message = newMessage
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        watchdog?.cancel()
        watchdog = nil
        currentUtterance = nil
        phase = .idle
        message = "Готово · удерживай кнопку языка"
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        watchdog?.cancel()
        watchdog = nil
        currentUtterance = nil
        phase = .idle
        message = "Озвучивание остановлено"
    }
}
