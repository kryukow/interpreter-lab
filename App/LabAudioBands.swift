import Foundation

/// Three energy bands calculated from real PCM, shared by microphone and rendered Apple speech.
/// Filter split points are ~250 Hz and ~2200 Hz. This is display-only DSP, never an audio effect.
struct LabAudioBands: Equatable {
    let low: Double
    let mid: Double
    let high: Double

    static let silence = LabAudioBands(low: 0, mid: 0, high: 0)

    var overall: Double { min(1, max(low, max(mid, high))) }

    func scaled(_ factor: Double) -> LabAudioBands {
        LabAudioBands(low: min(1, low * factor), mid: min(1, mid * factor),
                      high: min(1, high * factor))
    }

    static func measure(samples: UnsafePointer<Float>, count: Int, sampleRate: Double) -> LabAudioBands {
        guard count > 0, sampleRate > 0 else { return .silence }
        let lowAlpha = 1 - exp(-2 * Double.pi * 250 / sampleRate)
        let upperAlpha = 1 - exp(-2 * Double.pi * 2200 / sampleRate)
        var lower = 0.0
        var upper = 0.0
        var lowPower = 0.0
        var midPower = 0.0
        var highPower = 0.0

        for i in 0..<count {
            let sample = Double(samples[i])
            lower += lowAlpha * (sample - lower)
            upper += upperAlpha * (sample - upper)
            let middle = upper - lower
            let treble = sample - upper
            lowPower += lower * lower
            midPower += middle * middle
            highPower += treble * treble
        }
        let n = Double(count)
        // Nonlinear response makes speech consonants visible while retaining silence.
        func gain(_ power: Double, _ multiplier: Double) -> Double {
            let rms = sqrt(max(0, power / n))
            return min(1, pow(rms * multiplier, 0.78))
        }
        return LabAudioBands(low: gain(lowPower, 10), mid: gain(midPower, 13),
                             high: gain(highPower, 18))
    }
}
