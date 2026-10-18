import Foundation
import AVFoundation
import UIKit
import SwiftUI

@MainActor final class LabSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Phase: Equatable { case idle, arming, recording, recognizing, translating, playing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var held: String?
    @Published private(set) var message = "Удерживай кнопку нужного языка"
    @Published var source = ""
    @Published private(set) var translation = ""
    @Published private(set) var language = "ru"
    @Published private(set) var levels = Array(repeating: 0.0, count: 40)
    @Published private(set) var elapsed = 0.0
    @Published private(set) var detail = ""
    @Published private(set) var keySaved = false
    @Published var modelID: String = UserDefaults.standard.string(forKey: "lab.model") ?? "gpt-4.1-mini" {
        didSet { UserDefaults.standard.set(modelID, forKey: "lab.model") }
    }
    @Published var autoSpeak: Bool = (UserDefaults.standard.object(forKey: "lab.autoSpeak") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(autoSpeak, forKey: "lab.autoSpeak") }
    }
    @Published var germanVoiceID: String = UserDefaults.standard.string(forKey: "lab.voice.de") ?? "" {
        didSet { UserDefaults.standard.set(germanVoiceID, forKey: "lab.voice.de") }
    }
    @Published var russianVoiceID: String = UserDefaults.standard.string(forKey: "lab.voice.ru") ?? "" {
        didSet { UserDefaults.standard.set(russianVoiceID, forKey: "lab.voice.ru") }
    }

    private let capture = LabSpeechCapture()
    private let speaker = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var watchdog: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var recordingStarted = Date()
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
        speaker.delegate = self
        refreshKey()
    }

    func refreshKey() { keySaved = (try? LabKeychain.load()) != nil }
    func saveKey(_ key: String) throws { try LabKeychain.save(key); refreshKey() }
    func deleteKey() throws { try LabKeychain.delete(); refreshKey() }

    func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(language) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func begin(_ lang: String) {
        guard canBegin && held == nil && ["ru", "de"].contains(lang) else { return }
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
        elapsed = 0
        phase = .arming
        message = "Готовлю микрофон · пока не говори"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.capture.start(
                    locale: lang == "ru" ? "ru-RU" : "de-DE",
                    onText: { [weak self] value in
                        guard let self, self.generation == token else { return }
                        self.source = value
                    },
                    onLevel: { [weak self] value in
                        guard let self, self.generation == token && self.phase == .recording else { return }
                        self.levels.removeFirst()
                        self.levels.append(value)
                        self.elapsed = Date().timeIntervalSince(self.recordingStarted)
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
        guard keySaved else {
            message = "Текст распознан. Добавь API-ключ OpenAI в настройках для перевода."
            return
        }
        operation?.cancel()
        generation = UUID()
        let token = generation
        let input = source
        let from = language
        let model = modelID
        translationTarget = from == "ru" ? "de" : "ru"
        translation = ""
        phase = .translating
        message = "OpenAI · перевожу готовую фразу"
        detail = "\(from == "ru" ? "Русский → Deutsch" : "Deutsch → Русский") · \(model)"
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                guard let key = try LabKeychain.load() else {
                    throw LabTranslator.TranslationError.http(401, "Ключ отсутствует")
                }
                let value = try await LabTranslator.translate(input, source: from, model: model, apiKey: key)
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
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            phase = .idle
            message = "Не удалось включить динамик: \(error.localizedDescription)"
            return
        }
        let utterance = AVSpeechUtterance(string: translation)
        let storedID = translationTarget == "de" ? germanVoiceID : russianVoiceID
        utterance.voice = AVSpeechSynthesisVoice(identifier: storedID)
            ?? AVSpeechSynthesisVoice(language: translationTarget == "de" ? "de-DE" : "ru-RU")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        currentUtterance = utterance
        phase = .playing
        message = "Звучит перевод · Apple TTS"
        speaker.speak(utterance)
        // A guarded fallback avoids a permanently muted interface if a TTS callback is lost.
        watchdog?.cancel()
        let token = generation
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

    private func haltPlayback() {
        watchdog?.cancel()
        watchdog = nil
        currentUtterance = nil
        if speaker.isSpeaking || speaker.isPaused { speaker.stopSpeaking(at: .immediate) }
    }

    func stopAll(message newMessage: String = "Остановлено · удерживай кнопку языка") {
        generation = UUID()
        operation?.cancel()
        operation = nil
        capture.cancel()
        haltPlayback()
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
