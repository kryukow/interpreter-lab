import Foundation

enum LabResonancePhase: CaseIterable {
    case idle, input, processing, output

    var style: LabResonanceStyle {
        switch self {
        case .idle: return .init(lap: 12, tail: 0.10, light: 0.38, halo: 0.16, cloud: 0.40, breath: 9)
        case .input: return .init(lap: 3.8, tail: 0.18, light: 0.88, halo: 0.30, cloud: 0.58, breath: 6)
        case .processing: return .init(lap: 2.6, tail: 0.28, light: 0.80, halo: 0.38, cloud: 0.62, breath: 3.4)
        case .output: return .init(lap: -5.2, tail: 0.24, light: 0.94, halo: 0.25, cloud: 0.66, breath: 7)
        }
    }
}

/// Motion direction and tempo distinguish phases even in silent passages.
/// These are provisional until the original CONCEPT 03 source is available.
struct LabResonanceStyle {
    let lap: Double
    let tail: Double
    let light: Float
    let halo: Float
    let cloud: Float
    let breath: Double
}
