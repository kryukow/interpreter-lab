import SwiftUI

/// Audio updates invalidate only the two decorative views, not the language
/// carousel, text editor, settings, and the rest of LabView.
@MainActor final class LabVisualSignal: ObservableObject {
    @Published var levels = Array(repeating: 0.0, count: 40)
    @Published var bands: LabAudioBands = .silence
}

struct LabGraphiteSignalView: View {
    @ObservedObject var signal: LabVisualSignal
    let phase: LabResonancePhase
    let orbitActive: Bool

    var body: some View {
        LabGraphiteResonance(phase: phase, bands: signal.bands, orbitActive: orbitActive)
    }
}

struct LabWaveformSignalView: View {
    @ObservedObject var signal: LabVisualSignal
    let recording: Bool

    var body: some View {
        MicrophoneWaveform(levels: signal.levels, recording: recording)
    }
}
