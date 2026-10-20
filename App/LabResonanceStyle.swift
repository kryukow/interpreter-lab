import Foundation

enum LabResonancePhase: CaseIterable, Equatable, Sendable {
    case idle, input, processing, output

    var style: LabResonanceStyle {
        switch self {
        case .idle: return .init(lap: 12, tail: 0.10, light: 0.38, halo: 0.14, cloud: 0.10, breath: 6)
        case .input: return .init(lap: 3.8, tail: 0.18, light: 0.88, halo: 0.26, cloud: 0.18, breath: 2.8)
        case .processing: return .init(lap: 2.6, tail: 0.28, light: 0.80, halo: 0.32, cloud: 0.15, breath: 2.2)
        case .output: return .init(lap: -5.2, tail: 0.24, light: 0.94, halo: 0.22, cloud: 0.20, breath: 3.8)
        }
    }
}

/// Motion direction and tempo distinguish phases even in silent passages.
/// Shared stage tempo and contrast for the graphite orbital renderer.
struct LabResonanceStyle {
    let lap: Double
    let tail: Double
    let light: Float
    let halo: Float
    let cloud: Float
    let breath: Double
}
