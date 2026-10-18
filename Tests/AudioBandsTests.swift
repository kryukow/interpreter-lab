import Foundation

@main
struct AudioBandsTests {
    static func main() {
        let rate = 48_000.0
        let n = 4800
        func makeWave(_ hertz: Double, _ volume: Double) -> [Float] {
            (0..<n).map { Float(volume * sin(2.0 * .pi * hertz * Double($0) / rate)) }
        }
        func bands(_ samples: [Float]) -> LabAudioBands {
            samples.withUnsafeBufferPointer {
                LabAudioBands.measure(samples: $0.baseAddress!, count: $0.count, sampleRate: rate)
            }
        }
        let silent = bands(Array(repeating: 0, count: n))
        assert(silent == .silence)
        let bass = bands(makeWave(120, 0.06))
        let mid = bands(makeWave(800, 0.06))
        let high = bands(makeWave(4600, 0.06))
        assert(bass.low > bass.high, "Bass must favor low energy")
        assert(mid.mid > mid.low, "Mid must favor middle energy")
        assert(high.high > high.low, "Treble must favor high energy")
        assert(bass.overall > 0 && bass.overall <= 1)
        assert(high.overall > 0 && high.overall <= 1)
        let quiet = bands(makeWave(120, 0.012))
        assert(quiet.overall < bass.overall, "Stronger voice should glow more")
        print("Graphite audio frequency tests: silence, low/mid/high, energy passed")
    }
}
