import AVFoundation
import Speech

// Captures until finger release, then waits briefly for the last recognition result.
// The microphone is NEVER sent to OpenAI; Speech can use Apple's service when
// on-device recognition is unavailable for the chosen language.
@MainActor final class LabSpeechCapture {
    enum CaptureError: LocalizedError {
        case permission, unavailable, microphone, noSpeech
        var errorDescription: String? {
            switch self {
            case .permission: return "Разреши доступ к микрофону и распознаванию речи в настройках iPhone."
            case .unavailable: return "Apple Speech сейчас недоступен для выбранного языка."
            case .microphone: return "Не удалось запустить микрофон."
            case .noSpeech: return "Речь не распознана. Повтори фразу."
            }
        }
    }

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var installedTap = false
    private var generation = UUID()
    private var completion: ((Result<String, Error>) -> Void)?
    private var fallback: Task<Void, Never>?
    private var duration: Task<Void, Never>?
    private var currentText = ""
    private var finishing = false

    func start(locale: String,
               onText: @escaping (String) -> Void,
               onLevel: @escaping (Double) -> Void,
               onBands: @escaping (LabAudioBands) -> Void,
               onFinish: @escaping (Result<String, Error>) -> Void) async throws {
        cancel()
        let token = generation
        let permission = await withCheckedContinuation { (next: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { next.resume(returning: $0) }
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        guard generation == token else { throw CancellationError() }
        guard permission == .authorized && microphone else { throw CaptureError.permission }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
              recognizer.isAvailable else { throw CaptureError.unavailable }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .dictation
        self.request = request
        self.recognizer = recognizer
        self.completion = onFinish
        recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    self.currentText = text
                    onText(text)
                }
                if result?.isFinal == true {
                    self.deliver(.success(self.currentText))
                } else if let error {
                    if self.finishing && !self.currentText.isEmpty {
                        self.deliver(.success(self.currentText))
                    } else {
                        self.deliver(.failure(error))
                    }
                }
            }
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            cancel(); throw CaptureError.microphone
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var total = 0.0
            for i in 0..<Int(buffer.frameLength) {
                total += Double(channel[i]) * Double(channel[i])
            }
            let level = min(1, sqrt(total / Double(buffer.frameLength)) * 9)
            let bands = LabAudioBands.measure(
                samples: channel, count: Int(buffer.frameLength),
                sampleRate: format.sampleRate
            )
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                onBands(bands)
                onLevel(level)
            }
        }
        installedTap = true
        do { engine.prepare(); try engine.start() }
        catch { cancel(); throw error }

        duration = Task { [weak self] in
            try? await Task.sleep(for: .seconds(55))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.finish()
        }
    }

    func finish() {
        guard !finishing, completion != nil else { return }
        finishing = true
        stopMicrophone()
        request?.endAudio()
        let token = generation
        fallback?.cancel()
        fallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.deliver(self.currentText.isEmpty
                ? .failure(CaptureError.noSpeech) : .success(self.currentText))
        }
    }

    func cancel() {
        generation = UUID()
        fallback?.cancel(); fallback = nil
        duration?.cancel(); duration = nil
        stopMicrophone()
        recognition?.cancel(); recognition = nil
        request = nil
        recognizer = nil
        completion = nil
        currentText = ""
        finishing = false
    }

    private func stopMicrophone() {
        engine.stop()
        if installedTap {
            engine.inputNode.removeTap(onBus: 0)
            installedTap = false
        }
    }

    private func deliver(_ result: Result<String, Error>) {
        guard let completion else { return }
        cancel()
        if case .success(let text) = result, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(.failure(CaptureError.noSpeech))
        } else {
            completion(result)
        }
    }
}
