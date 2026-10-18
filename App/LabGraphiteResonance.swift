import SwiftUI

enum LabResonancePhase: Equatable {
    case idle, input, processing, output
}

/// Graphite · Expressive — approved Infinity Resonance design.
/// The symbol and softly blurred monochrome clouds react to three REAL audio
/// frequency bands. Idle/processing have gentle ambient motion only.
struct LabGraphiteResonance: View {
    let phase: LabResonancePhase
    let bands: LabAudioBands
    let orbitActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let active = phase == .input || phase == .output
            let bass = active ? min(1, bands.low * 1.7) : 0.0
            let mids = active ? min(1, bands.mid * 1.7) : 0.0
            let highs = active ? min(1, bands.high * 1.7) : 0.0
            let energy = max(bass, max(mids, highs))
            let drift = reduceMotion ? 0.0 : time
            let breath = reduceMotion ? 1.0 : (1.0 + 0.012 * sin(drift * 0.64))
            let scaleX = breath + bass * 0.075
            let scaleY = breath + mids * 0.050
            let glow = 0.20 + energy * 0.62 + (phase == .processing ? 0.12 : 0)
            let motion = orbitActive ? 0.08 : 1.0

            GeometryReader { geometry in
                let size = geometry.size
                let diameter = max(size.width * 0.33, 128.0)
                let centerY = size.height * 0.49

                ZStack {
                    // Slow, feathered monochrome nebula — no colored palette.
                    // They grow on bass attacks instead of flashing or jittering.
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.66, green: 0.70, blue: 0.77).opacity(0.30 + bass * 0.44), .clear],
                            center: .center, startRadius: 6, endRadius: diameter * 0.55))
                        .frame(width: diameter * (1.2 + bass * 0.35), height: diameter * 0.87)
                        .blur(radius: 24)
                        .offset(x: -size.width * 0.20 + CGFloat(sin(drift * 0.31) * 17),
                                y: CGFloat(sin(drift * 0.38) * 7) - 8)
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.86, green: 0.88, blue: 0.94).opacity(0.23 + mids * 0.49), .clear],
                            center: .center, startRadius: 5, endRadius: diameter * 0.56))
                        .frame(width: diameter * (1.35 + mids * 0.32), height: diameter * 0.90)
                        .blur(radius: 27)
                        .offset(x: size.width * 0.19 + CGFloat(cos(drift * 0.27) * 15),
                                y: CGFloat(sin(drift * 0.29) * 11) - 11)
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [Color(red: 0.48, green: 0.53, blue: 0.61).opacity(0.20 + highs * 0.49), .clear],
                            center: .center, startRadius: 4, endRadius: diameter * 0.55))
                        .frame(width: diameter * 1.26, height: diameter * 0.72)
                        .blur(radius: 31)
                        .offset(x: CGFloat(sin(drift * 0.23) * 14),
                                y: size.height * 0.25 - CGFloat(highs * 15))
                    // Diffuse center pulse follows real speech envelope.
                    Ellipse()
                        .fill(Color(white: 0.78).opacity(0.10 + energy * 0.19))
                        .frame(width: diameter * (0.95 + energy * 0.50),
                               height: diameter * (0.46 + energy * 0.26))
                        .blur(radius: 31)
                        .offset(y: -4)

                    // The original Live orbit owns the language controls;
                    // this is visual-only and cannot intercept their gestures.
                    ZStack {
                        InfinityRibbon()
                            .stroke(Color(red: 0.67, green: 0.70, blue: 0.79).opacity(glow),
                                    style: StrokeStyle(lineWidth: 15 + bass * 20, lineCap: .round))
                            .blur(radius: 13 + energy * 8)

                        InfinityRibbon()
                            .stroke(Color(white: 0.22).opacity(0.90),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round))

                        InfinityRibbon()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.66, green: 0.70, blue: 0.78),
                                        .white,
                                        Color(red: 0.78, green: 0.81, blue: 0.88),
                                        .white,
                                        Color(red: 0.70, green: 0.73, blue: 0.81)
                                    ],
                                    startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: 8.5 + mids * 2.6, lineCap: .round))

                        InfinityRibbon()
                            .stroke(Color.white.opacity(0.23 + highs * 0.50),
                                    style: StrokeStyle(lineWidth: 1.7 + highs * 1.4,
                                                       lineCap: .round,
                                                       dash: [18 + highs * 23, 280],
                                                       dashPhase: drift * (phase == .processing ? -42 : -76)))
                    }
                    .frame(width: size.width * 0.72, height: size.height * 0.73)
                    .scaleEffect(x: scaleX, y: scaleY)
                    .offset(y: -3)
                    .shadow(color: Color(white: 0.85).opacity(0.06 + energy * 0.22),
                            radius: 17 + energy * 12)
                }
                .frame(width: size.width, height: size.height)
                .position(x: size.width / 2, y: centerY)
                .opacity(motion)
                .scaleEffect(orbitActive ? 1.22 : 1)
                .animation(.spring(response: 0.33, dampingFraction: 0.83), value: orbitActive)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        switch phase {
        case .idle: return "Символ бесконечности, ожидание"
        case .input: return "Реакция на входящую речь"
        case .processing: return "Формирование перевода"
        case .output: return "Реакция на звучащий перевод"
        }
    }
}

/// One elegant hand-shaped ribbon, not an SF Symbol distorted by amplitude.
/// Voice moves the whole ribbon by < 8%; the main contour remains legible.
private struct InfinityRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            CGPoint(x: x + px * w, y: y + py * h)
        }
        var path = Path()
        path.move(to: point(0.50, 0.50))
        path.addCurve(to: point(0.25, 0.25),
                      control1: point(0.40, 0.32), control2: point(0.35, 0.25))
        path.addCurve(to: point(0.07, 0.50),
                      control1: point(0.14, 0.25), control2: point(0.07, 0.37))
        path.addCurve(to: point(0.25, 0.75),
                      control1: point(0.07, 0.64), control2: point(0.14, 0.75))
        path.addCurve(to: point(0.50, 0.50),
                      control1: point(0.38, 0.75), control2: point(0.44, 0.60))
        path.addCurve(to: point(0.75, 0.25),
                      control1: point(0.56, 0.40), control2: point(0.63, 0.25))
        path.addCurve(to: point(0.93, 0.50),
                      control1: point(0.86, 0.25), control2: point(0.93, 0.37))
        path.addCurve(to: point(0.75, 0.75),
                      control1: point(0.93, 0.64), control2: point(0.86, 0.75))
        path.addCurve(to: point(0.50, 0.50),
                      control1: point(0.63, 0.75), control2: point(0.56, 0.60))
        return path
    }
}
