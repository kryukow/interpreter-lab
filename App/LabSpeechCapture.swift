import AVFoundation
import Speech

/// Audio tap runs on the audio thread; recognizing segments may be replaced
/// while recording. The relay serializes append/endAudio without blocking UI.
private final class LabSpeechAudioRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var active: SFSpeechAudioBufferRecognitionRequest?

    func send(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        active?.append(buffer)
        lock.unlock()
    }

    func replace(with next: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        let old = active
        active = next
        lock.unlock()
        old?.endAudio()
    }
}

/// Never treats Apple's partial text as an append-only transcript.
/// A single Apple Speech recognition task may restart or finalize before the
/// finger is released. We preserve completed segments and start a fresh request
/// on an existing live audio engine, rotating proactively every 42 seconds.
@MainActor final class LabSpeechCapture {
    enum CaptureError: LocalizedError {
        case permission, unavailable, microphone, noSpeech, tooLong
        var errorDescription: String? {
            switch self {
            case .permission: return "Разреши доступ к микрофону и распознаванию речи в настройках iPhone."
            case .unavailable: return "Apple Speech сейчас недоступен для выбранного языка."
            case .microphone: return "Не удалось запустить микрофон."
            case .noSpeech: return "Речь не распознана. Повтори фразу."
            case .tooLong: return "Достигнут предел непрерывной записи — четыре минуты."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let audioRelay = LabSpeechAudioRelay()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var installedTap = false
    private var generation = UUID()
    private var recognitionSegment = UUID()
    private var completion: ((Result<String, Error>) -> Void)?
    private var onTextHandler: ((String) -> Void)?
    private var fallback: Task<Void, Never>?
    private var duration: Task<Void, Never>?
    private var rotation: Task<Void, Never>?
    private var assembler = LabTranscriptAssembler()
    private var finishing = false
    private var restartAttempts = 0

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
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        self.recognizer = recognizer
        completion = onFinish
        onTextHandler = onText
        assembler.reset()
        finishing = false
        beginRecognitionSegment(token: token)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            cancel()
            throw CaptureError.microphone
        }
        // The tap ALWAYS sends to the current request, not the request from
        // the start() call. Otherwise a restart would keep feeding the old task.
        let relay = audioRelay
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            relay.send(buffer)
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
                guard let self, self.generation == token, !self.finishing else { return }
                onBands(bands)
                onLevel(level)
            }
        }
        installedTap = true
        do { engine.prepare(); try engine.start() }
        catch { cancel(); throw error }

        // Apple limits an individual recognition request, not our recording
        // session: active requests roll every 42 s while the microphone stays on.
        // Hard safety cap prevents abandoned push-to-talk from running forever.
        duration = Task { [weak self] in
            try? await Task.sleep(for: .seconds(240))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.finish()
        }
    }

    private func beginRecognitionSegment(token: UUID) {
        guard generation == token, !finishing, let recognizer else { return }
        let id = UUID()
        recognitionSegment = id
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true
        next.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        next.taskHint = .dictation
        let previousRecognition = recognition
        request = next
        audioRelay.replace(with: next)
        recognition = recognizer.recognitionTask(with: next) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token,
                      self.recognitionSegment == id else { return }
                if let phrase = result?.bestTranscription.formattedString, !phrase.isEmpty {
                    let text = self.assembler.accept(phrase)
                    self.onTextHandler?(text)
                    self.restartAttempts = 0
                }
                if result?.isFinal == true {
                    if self.finishing {
                        self.deliverText()
                    } else {
                        self.rotateSegment(token: token)
                    }
                } else if let error {
                    if self.finishing {
                        self.deliverAvailableText(or: error)
                    } else if self.restartAttempts < 3 {
                        self.restartAttempts += 1
                        self.rotateSegment(token: token)
                    } else {
                        self.deliverAvailableText(or: error)
                    }
                }
            }
        }
        previousRecognition?.cancel()
        rotation?.cancel()
        rotation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(42))
            guard !Task.isCancelled, let self,
                  self.generation == token, self.recognitionSegment == id,
                  !self.finishing else { return }
            self.rotateSegment(token: token)
        }
    }

    private func rotateSegment(token: UUID) {
        guard generation == token, !finishing else { return }
        assembler.commitActive()
        onTextHandler?(assembler.text)
        beginRecognitionSegment(token: token)
    }

    func finish() {
        guard !finishing, completion != nil else { return }
        finishing = true
        rotation?.cancel()
        rotation = nil
        stopMicrophone()
        let token = generation
        fallback?.cancel()
        fallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.deliverText()
        }
    }

    func cancel() {
        generation = UUID()
        fallback?.cancel(); fallback = nil
        duration?.cancel(); duration = nil
        rotation?.cancel(); rotation = nil
        stopMicrophone()
        recognition?.cancel(); recognition = nil
        request = nil
        recognizer = nil
        completion = nil
        onTextHandler = nil
        assembler.reset()
        finishing = false
        restartAttempts = 0
    }

    private func stopMicrophone() {
        engine.stop()
        if installedTap {
            engine.inputNode.removeTap(onBus: 0)
            installedTap = false
        }
        audioRelay.replace(with: nil)
    }

    private func deliverText() {
        let text = assembler.text
        deliver(text.isEmpty ? .failure(CaptureError.noSpeech) : .success(text))
    }

    private func deliverAvailableText(or error: Error) {
        let text = assembler.text
        deliver(text.isEmpty ? .failure(error) : .success(text))
    }

    private func deliver(_ result: Result<String, Error>) {
        guard let completion else { return }
        cancel()
        if case .success(let text) = result,
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(.failure(CaptureError.noSpeech))
        } else {
            completion(result)
        }
    }
}
