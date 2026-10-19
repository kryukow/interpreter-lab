import Foundation
import AVFoundation

enum LabSpeechRenderError: LocalizedError {
    case empty, timeout, cancelled, unsupportedBuffer
    var errorDescription: String? {
        switch self {
        case .empty: return "Apple не вернул аудиофрагменты"
        case .timeout: return "Подготовка голосового звука заняла слишком много времени"
        case .cancelled: return "Озвучивание отменено"
        case .unsupportedBuffer: return "Apple вернул неподдерживаемый формат звука"
        }
    }
}

/// Writes the exact Apple synthesizer PCM to a CAF file, then AVAudioPlayer
/// plays that SAME audio so the graphical spectrum is locked to real playback.
/// The separate regular AVSpeechSynthesizer remains a fallback.
private final class LabRenderCollector {
    let url: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var file: AVAudioFile?
    private var finished = false
    private var frames: Int64 = 0

    init(url: URL, continuation: CheckedContinuation<URL, Error>) {
        self.url = url
        self.continuation = continuation
    }

    func append(_ buffer: AVAudioBuffer) {
        var result: Result<URL, Error>?
        var resume: CheckedContinuation<URL, Error>?
        lock.lock()
        if !finished {
            if let pcm = buffer as? AVAudioPCMBuffer {
                if pcm.frameLength == 0 {
                    finished = true
                    file = nil
                    result = frames > 0 ? .success(url) : .failure(LabSpeechRenderError.empty)
                } else {
                    do {
                        if file == nil {
                            file = try AVAudioFile(
                                forWriting: url,
                                settings: pcm.format.settings,
                                commonFormat: pcm.format.commonFormat,
                                interleaved: pcm.format.isInterleaved
                            )
                        }
                        try file?.write(from: pcm)
                        frames += Int64(pcm.frameLength)
                    } catch {
                        finished = true
                        file = nil
                        result = .failure(error)
                    }
                }
            } else {
                finished = true
                file = nil
                result = .failure(LabSpeechRenderError.unsupportedBuffer)
            }
            if finished {
                resume = continuation
                continuation = nil
            }
        }
        lock.unlock()
        if let result, let resume { resume.resume(with: result) }
    }

    func cancel(_ error: Error = LabSpeechRenderError.cancelled) {
        lock.lock()
        let pending = continuation
        continuation = nil
        finished = true
        file = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}

@MainActor final class LabSpeechExporter {
    private var synthesizer: AVSpeechSynthesizer?
    private var current: LabRenderCollector?
    private var timeout: Task<Void, Never>?

    func render(_ utterance: AVSpeechUtterance) async throws -> URL {
        cancel()
        let synth = AVSpeechSynthesizer()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lab-speech-\(UUID().uuidString)")
            .appendingPathExtension("caf")
        synthesizer = synth
        let seconds = max(25.0, min(90.0, Double(utterance.speechString.count) * 0.30))
        defer {
            timeout?.cancel()
            timeout = nil
            current = nil
            synthesizer = nil
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let collector = LabRenderCollector(url: url, continuation: continuation)
                current = collector
                timeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { return }
                    self?.current?.cancel(LabSpeechRenderError.timeout)
                    self?.synthesizer?.stopSpeaking(at: .immediate)
                }
                synth.write(utterance) { [weak collector] buffer in
                    collector?.append(buffer)
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.cancel() }
        }
    }

    func cancel() {
        timeout?.cancel()
        timeout = nil
        current?.cancel()
        current = nil
        if synthesizer?.isSpeaking == true {
            synthesizer?.stopSpeaking(at: .immediate)
        }
        synthesizer = nil
    }
}

/// Pre-sampled energy envelopes from the same CAF that will be played.
/// 25 measurements per second; querying by AVAudioPlayer.currentTime keeps
/// even consonant attacks aligned with actual spoken playback.
struct LabPlaybackSpectrum: Sendable {
    private let frames: [LabAudioBands]
    private let samplesPerSecond: Double = 25

    init(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let sampleRate = file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(max(256, Int(sampleRate / samplesPerSecond)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else {
            throw LabSpeechRenderError.unsupportedBuffer
        }
        var measurements: [LabAudioBands] = []
        measurements.reserveCapacity(Int(min(10000, Double(file.length) / Double(capacity) + 1)))
        // Audio is only analyzed, never modified or resampled.
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: capacity)
            let count = Int(buffer.frameLength)
            guard count > 0 else { break }
            guard let channel = buffer.floatChannelData?[0] else {
                throw LabSpeechRenderError.unsupportedBuffer
            }
            measurements.append(LabAudioBands.measure(samples: channel, count: count, sampleRate: sampleRate))
        }
        guard !measurements.isEmpty else { throw LabSpeechRenderError.empty }
        frames = measurements
    }

    func bands(at time: TimeInterval) -> LabAudioBands {
        guard time.isFinite, time >= 0 else { return .silence }
        let i = min(frames.count - 1, max(0, Int(time * samplesPerSecond)))
        return frames[i]
    }
}
