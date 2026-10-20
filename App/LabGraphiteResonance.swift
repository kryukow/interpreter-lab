import SwiftUI
import UIKit
import QuartzCore

/// The approved graphite sphere, rendered independently of SwiftUI state updates.
struct LabGraphiteResonance: UIViewRepresentable {
    let phase: LabResonancePhase
    let bands: LabAudioBands
    let orbitActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> GraphiteResonanceSurface {
        let view = GraphiteResonanceSurface()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.update(phase: phase, bands: bands, orbitActive: orbitActive,
                    reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ view: GraphiteResonanceSurface, context: Context) {
        view.update(phase: phase, bands: bands, orbitActive: orbitActive,
                    reduceMotion: reduceMotion)
    }
}

enum LabSphereFramePolicy {
    /// Request the display's native rate; conserve energy under system pressure.
    static func requestedRate(screenMaximum: Int, lowPower: Bool,
                              thermalState: ProcessInfo.ThermalState) -> Int {
        let native = min(120, max(1, screenMaximum > 0 ? screenMaximum : 60))
        if lowPower || thermalState == .serious || thermalState == .critical {
            return min(30, native)
        }
        return native
    }
}

/// Native port of the approved graphite-orb paintOrb. An adaptive display link lives
/// entirely in this UIKit surface: no timers, published state or SwiftUI redraws.
/// Its weak target prevents retention; offscreen/background/reduced motion stops it.
final class GraphiteResonanceSurface: UIView {
    private final class TickTarget: NSObject {
        weak var surface: GraphiteResonanceSurface?
        @objc func tick(_ link: CADisplayLink) { surface?.tick(link) }
    }
    private let tickTarget = TickTarget()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var active = UIApplication.shared.applicationState != .background
    private var reducedMotion = false
    private var phase: LabResonancePhase = .idle
    private var targetEnergy: CGFloat = 0
    private var energy: CGFloat = 0
    private var clock: CGFloat = 3
    private var rotationClock: CGFloat = 3
    private var speed: CGFloat = 0.55
    private var direction: CGFloat = 1
    private var particleClock: CGFloat = 0
    private var particleDirection: CGFloat = 1
    private var particleVisibility: CGFloat = 0
    private var tailDirection: CGFloat = 1
    private var dimmed = false
    private(set) var requestedFrameRate = 60
    private(set) var renderedFrames = 0
    var isAnimating: Bool { displayLink != nil }
    var sphereRadius: CGFloat { 61 * min(bounds.width / 395, bounds.height / 235) }
    private static let body = gradient([
        (0x364351, 1), (0x202c39, 1), (0x111a25, 1), (0x05090f, 1)
    ], stops: [0, 0.32, 0.65, 1])
    private static let fog = gradient([
        (0xadc1da, 0.10), (0x8fa8c0, 0.098), (0x8fa8c0, 0)
    ], stops: [0, 0.38, 1])
    private static let atmosphere = gradient([(0x90abce, 0.12), (0x8da9ce, 0)], stops: [0, 1])
    private static let shade = gradient([
        (0x000000, 0), (0x02060c, 0.03), (0x01040b, 0.77)
    ], stops: [0, 0.55, 1])

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        tickTarget.surface = self
        NotificationCenter.default.addObserver(self, selector: #selector(suspend), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(systemPressureChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(systemPressureChanged), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Code-only sphere") }
    deinit {
        displayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    override func didMoveToWindow() { super.didMoveToWindow(); configureMotion() }
    @objc private func suspend() { active = false; configureMotion() }
    @objc private func resume() { active = true; configureMotion() }
    @objc private func systemPressureChanged() {
        if Thread.isMainThread { configureMotion() }
        else { DispatchQueue.main.async { [weak self] in self?.configureMotion() } }
    }
    private func configureMotion() {
        let rate = LabSphereFramePolicy.requestedRate(
            screenMaximum: window?.screen.maximumFramesPerSecond ?? 60,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: ProcessInfo.processInfo.thermalState)
        if requestedFrameRate != rate { lastTimestamp = 0 }
        requestedFrameRate = rate
        let enabled = window != nil && active && !reducedMotion && !dimmed
        if enabled && displayLink == nil {
            lastTimestamp = 0
            let link = CADisplayLink(target: tickTarget, selector: #selector(TickTarget.tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !enabled {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
        }
        displayLink?.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(min(60, rate)), maximum: Float(rate), preferred: Float(rate))
        // Audio updates may arrive between display ticks. The link exclusively
        // owns invalidation while moving. Sheets pause it to free the main thread.
        if displayLink == nil && !dimmed { setNeedsDisplay() }
    }
    func update(phase: LabResonancePhase, bands: LabAudioBands, orbitActive: Bool, reduceMotion: Bool) {
        self.phase = phase
        reducedMotion = reduceMotion
        dimmed = orbitActive
        let audio = CGFloat(max(0, min(1, bands.low * 0.45 + bands.mid * 0.38 + bands.high * 0.17)))
        switch phase {
        case .idle: targetEnergy = 0
        case .input: targetEnergy = 0.12 + audio * 0.78
        case .processing: targetEnergy = 0.33
        case .output: targetEnergy = 0.22 + audio * 0.78
        }
        // A static, meaningful state is still rendered for Reduce Motion.
        if reduceMotion { energy = targetEnergy }
        configureMotion()
    }
    private func tick(_ link: CADisplayLink) {
        let dt = CGFloat(lastTimestamp == 0 ? 1.0 / Double(requestedFrameRate) : min(0.05, link.timestamp - lastTimestamp))
        lastTimestamp = link.timestamp
        let targetSpeed: CGFloat = phase == .idle ? 0.55 : phase == .input ? 1.4 : phase == .processing ? 2 : 1
        let blend = min(1, dt * 3)
        energy += (targetEnergy - energy) * blend
        speed += (targetSpeed - speed) * blend
        direction += ((phase == .output ? -1 : 1) - direction) * blend
        clock += dt * speed
        rotationClock += dt * speed * direction
        particleDirection += ((phase == .output ? -1 : 1) - particleDirection) * (1 - exp(-dt * 2.8))
        particleClock += dt * particleDirection
        let visible: CGFloat = phase == .input || phase == .output ? 1 : 0
        particleVisibility += (visible - particleVisibility) * (1 - exp(-dt * 3))
        tailDirection += (tanh(direction * speed * 4) - tailDirection) * (1 - exp(-dt * 4))
        setNeedsDisplay()
    }
    private static func color(_ hex: UInt32, _ alpha: CGFloat) -> CGColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha).cgColor
    }
    private static func gradient(_ colors: [(UInt32, CGFloat)], stops: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                   colors: colors.map { color($0.0, $0.1) } as CFArray, locations: stops)!
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        renderedFrames += 1
        context.saveGState()
        context.setAlpha(dimmed ? 0.08 : 1)
        context.translateBy(x: bounds.midX, y: bounds.midY)
        let scale = min(bounds.width / 395, bounds.height / 235)
        context.scaleBy(x: scale, y: scale)
        let t = clock, e = energy, r: CGFloat = 61 * (1 + 0.014 * e * sin(t * 2.2))
        let glow: CGFloat = 0.85 + e * 0.2
        for i in 0..<36 {
            let a = CGFloat(i) * 2.399963 + t * (0.006 + CGFloat(i % 4) * 0.003)
            let radial = 1 + CGFloat(i % 6) * 0.08
            let diameter: CGFloat = i % 8 == 0 ? 1.9 : 0.9
            context.setFillColor(Self.color(0xb6c7da, 0.11 + CGFloat(i % 5) * 0.045))
            context.fillEllipse(in: CGRect(x: cos(a) * 136 * radial, y: sin(a) * 74 * radial, width: diameter, height: diameter))
        }
        if particleVisibility > 0.003 && !reducedMotion {
            context.saveGState()
            context.setBlendMode(.screen)
            for i in 0..<23 {
                let raw = particleClock * (0.23 + CGFloat(i % 4) * 0.025) + CGFloat(i) * 0.6180339887
                let travel = raw - floor(raw)
                let angle = CGFloat(i) * 2.399963 + 0.12 * sin(t * 0.25 + CGFloat(i))
                let start = 138 + CGFloat(i % 5) * 12
                let end = 43 + CGFloat(i % 3) * 5
                let radius = start + (end - start) * travel
                let alpha = sin(.pi * travel) * particleVisibility
                let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius * 0.68)
                let length = (3 + travel * 11) * tanh(particleDirection * 3)
                let tail = CGPoint(x: point.x + cos(angle) * length, y: point.y + sin(angle) * length * 0.68)
                context.setLineWidth(0.65)
                for segment in 0..<6 {
                    let f = CGFloat(segment) / 6, g = CGFloat(segment + 1) / 6
                    context.beginPath()
                    context.move(to: CGPoint(x: tail.x + (point.x - tail.x) * f, y: tail.y + (point.y - tail.y) * f))
                    context.addLine(to: CGPoint(x: tail.x + (point.x - tail.x) * g, y: tail.y + (point.y - tail.y) * g))
                    context.setStrokeColor(Self.color(0xc8def6, alpha * g * 0.47)); context.strokePath()
                }
                let size: CGFloat = i % 7 == 0 ? 2.2 : 1.3
                context.setFillColor(Self.color(0xe2eefc, alpha * 0.75))
                context.fillEllipse(in: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size))
            }
            let fall = (t * 0.32).truncatingRemainder(dividingBy: 1)
            let alpha = sin(.pi * fall) * particleVisibility * max(0, particleDirection)
            let head = CGPoint(x: -126 + fall * 99, y: -88 + fall * 66)
            for i in 0..<10 {
                let f = CGFloat(i) / 10, g = CGFloat(i + 1) / 10
                context.beginPath()
                context.move(to: CGPoint(x: head.x - 26 * (1 - f), y: head.y - 20 * (1 - f)))
                context.addLine(to: CGPoint(x: head.x - 26 * (1 - g), y: head.y - 20 * (1 - g)))
                context.setLineWidth(1); context.setStrokeColor(Self.color(0xdaebfe, alpha * g * 0.65)); context.strokePath()
            }
            context.setFillColor(Self.color(0xebf6ff, alpha * 0.85))
            context.setShadow(offset: .zero, blur: 5, color: Self.color(0xc1ddfa, alpha))
            context.fillEllipse(in: CGRect(x: head.x - 1.2, y: head.y - 1.2, width: 2.4, height: 2.4))
            context.restoreGState()
        }
        context.saveGState()
        context.rotate(by: -0.1)
        context.setStrokeColor(Self.color(0xafc4dc, 0.41)); context.setLineWidth(0.8)
        context.strokeEllipse(in: CGRect(x: -148, y: -77, width: 296, height: 154))
        let orbitAngle = rotationClock * 0.34
        for i in 0..<60 {
            let q = orbitAngle - CGFloat(i) * 0.008 * tailDirection
            context.beginPath()
            context.move(to: CGPoint(x: cos(q) * 148, y: sin(q) * 77))
            context.addLine(to: CGPoint(x: cos(q + 0.011) * 148, y: sin(q + 0.011) * 77))
            context.setStrokeColor(Self.color(0xd9e8f9, (1 - CGFloat(i) / 60) * 0.88 * glow))
            context.setLineWidth(0.9 + (1 - CGFloat(i) / 60) * 0.8)
            context.strokePath()
        }
        context.restoreGState()
        context.drawRadialGradient(Self.atmosphere, startCenter: .zero, startRadius: r - 2,
                                   endCenter: .zero, endRadius: r + 12, options: [])
        context.saveGState()
        context.addEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)); context.clip()
        context.drawRadialGradient(Self.body, startCenter: CGPoint(x: -24, y: -30), startRadius: 0,
                                   endCenter: CGPoint(x: 16, y: 20), endRadius: r * 1.5, options: [.drawsAfterEndLocation])
        context.saveGState()
        context.setBlendMode(.screen)
        for i in 0..<7 {
            let u = t * 0.16 + CGFloat(i) * 1.9
            context.saveGState()
            context.translateBy(x: sin(u) * r * 0.3, y: cos(u * 0.8 + CGFloat(i)) * r * 0.39)
            context.rotate(by: u * 0.55 + CGFloat(i))
            context.scaleBy(x: 1, y: 0.33 + 0.09 * sin(u))
            context.setAlpha((dimmed ? 0.08 : 1) * (0.65 + e * 0.45))
            context.drawRadialGradient(Self.fog, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 0.95, options: [])
            context.restoreGState()
        }
        context.restoreGState()
        let yaw = rotationClock * 0.15, tilt = -0.42 + 0.1 * sin(t * 0.14)
        let ct = cos(tilt), st = sin(tilt)
        func project(_ lat: CGFloat, _ lon: CGFloat) -> (point: CGPoint, z: CGFloat) {
            let swirl = 0.1 * sin(lon * 3 + t * 0.6) + (0.025 + e * 0.025) * sin(lon * 7 - t * 0.8)
            let la = lat + swirl * cos(lat), lo = lon + yaw
            let x = r * 0.96 * cos(la) * sin(lo), y = r * 0.96 * sin(la)
            return (CGPoint(x: x * ct - y * st, y: x * st + y * ct), cos(la) * cos(lo))
        }
        for j in 0..<22 {
            let lat = -1.43 + CGFloat(j) / 21 * 2.86
            let front = CGMutablePath(), back = CGMutablePath()
            var wasFront: Bool?
            for k in 0...112 {
                let p = project(lat, CGFloat(k) / 112 * .pi * 2)
                let isFront = p.z > 0, path = isFront ? front : back
                if wasFront != isFront { path.move(to: p.point) } else { path.addLine(to: p.point) }
                wasFront = isFront
            }
            context.addPath(front); context.setLineWidth(3.8 + e * 2)
            context.setStrokeColor(Self.color(0x99b7d8, (0.028 + e * 0.018) * glow)); context.strokePath()
            context.addPath(back); context.setLineWidth(0.46)
            context.setStrokeColor(Self.color(0x8da6c0, 0.063)); context.strokePath()
            context.addPath(front); context.setStrokeColor(Self.color(0xb7cfea, (0.18 + e * 0.14) * glow)); context.strokePath()
        }
        for i in 0..<105 {
            let sequence = (CGFloat(i) * 0.6180339887).truncatingRemainder(dividingBy: 1)
            let p = project(asin(-0.96 + 1.92 * sequence), CGFloat(i) * 2.399963 + t * 0.025)
            guard p.z >= -0.1 else { continue }
            let radius: CGFloat = i % 11 == 0 ? 1.05 : 0.48
            context.setFillColor(Self.color(0xd5e5f8, (0.14 + e * 0.25) * max(0.12, p.z) * glow))
            context.fillEllipse(in: CGRect(x: p.point.x - radius, y: p.point.y - radius, width: radius * 2, height: radius * 2))
        }
        context.drawLinearGradient(Self.shade, start: CGPoint(x: -r, y: -r), end: CGPoint(x: r, y: r * 0.7), options: [.drawsAfterEndLocation])
        context.restoreGState()
        context.setLineWidth(0.55); context.setStrokeColor(Self.color(0x99adc4, 0.22))
        context.strokeEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        context.beginPath(); context.addArc(center: .zero, radius: r, startAngle: .pi * 0.91, endAngle: .pi * 1.86, clockwise: false)
        context.setLineWidth(0.8); context.setStrokeColor(Self.color(0xd0e3f9, (0.48 + e * 0.22) * glow))
        context.setShadow(offset: .zero, blur: 3 + e * 3, color: Self.color(0xc0deff, 0.5))
        context.strokePath()
        context.restoreGState()
    }
}
