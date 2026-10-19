import SwiftUI
import UIKit
import QuartzCore

/// Graphite / Expressive renderer; exact CONCEPT 03 parity is pending its source.
///
/// No TimelineView, Canvas, per-frame SwiftUI rendering, .blur modifiers, or
/// software filters. The monochrome blobs drift via Core Animation on their
/// own composited layers. Only small layer properties change when mic / actual
/// Apple TTS samples arrive (capped to ~20 Hz in LabSession).
struct LabGraphiteResonance: UIViewRepresentable {
    let phase: LabResonancePhase
    let bands: LabAudioBands
    let orbitActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> GraphiteResonanceSurface {
        let view = GraphiteResonanceSurface()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.update(phase: phase, bands: bands, orbitActive: orbitActive, reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ uiView: GraphiteResonanceSurface, context: Context) {
        uiView.update(phase: phase, bands: bands, orbitActive: orbitActive, reduceMotion: reduceMotion)
    }
}

/// CA-native renderer: 3 feathered radial-gradient blobs and one compact,
/// balanced infinity ribbon. Purely decorative; never touches microphone,
/// network, translation, or audio playback.
final class GraphiteResonanceSurface: UIView {
    private let cloudLeft = CAGradientLayer()
    private let cloudRight = CAGradientLayer()
    private let cloudBottom = CAGradientLayer()
    private let artwork = CALayer()
    private let halo = CAShapeLayer()
    private let ribbon = CALayer()
    private let aura = CAShapeLayer()
    private let underside = CAShapeLayer()
    private let mainStroke = CAShapeLayer()
    private let metal = CAGradientLayer()
    private let glint = CAShapeLayer()
    private let lightTail = CAShapeLayer()
    private var contourLength: CGFloat = 1
    private var motionEnabled = false
    private var configuredPhase: LabResonancePhase?
    private var reduceMotion = false
    private var previousSize = CGSize.zero

    // 188 x 108: around a third narrower than the initial oversized version.
    // Actual painted contour ratio is ~2.2:1, no elongated stretched loops.
    private let ribbonWidth: CGFloat = 188
    private let ribbonHeight: CGFloat = 108
    private var currentPhase: LabResonancePhase = .idle

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        configureCloud(cloudLeft, white: 0.65, alpha: 0.40)
        configureCloud(cloudRight, white: 0.87, alpha: 0.32)
        configureCloud(cloudBottom, white: 0.54, alpha: 0.29)
        layer.addSublayer(artwork)
        artwork.addSublayer(cloudLeft)
        artwork.addSublayer(cloudRight)
        artwork.addSublayer(cloudBottom)
        setupStroke(halo, color: UIColor(white: 0.77, alpha: 1), width: 0.65)
        artwork.addSublayer(halo)

        ribbon.masksToBounds = false
        artwork.addSublayer(ribbon)
        setupStroke(aura, color: UIColor(white: 0.83, alpha: 1), width: 16)
        aura.opacity = 0.18
        aura.shadowColor = UIColor(white: 0.88, alpha: 1).cgColor
        aura.shadowRadius = 9
        aura.shadowOpacity = 0.26
        aura.shadowOffset = .zero
        setupStroke(underside, color: UIColor(white: 0.23, alpha: 1), width: 10)
        setupStroke(mainStroke, color: UIColor(white: 0.64, alpha: 1), width: 6.5)
        setupStroke(lightTail, color: UIColor(white: 0.90, alpha: 1), width: 7.5)
        setupStroke(glint, color: .white, width: 2.1)
        glint.opacity = 0.25
        glint.lineDashPattern = [22, 360]
        [aura, underside].forEach(ribbon.addSublayer)
        metal.colors = [UIColor(white: 0.42, alpha: 1).cgColor,
                        UIColor(white: 0.91, alpha: 1).cgColor,
                        UIColor(white: 0.57, alpha: 1).cgColor,
                        UIColor(white: 0.98, alpha: 1).cgColor,
                        UIColor(white: 0.46, alpha: 1).cgColor]
        metal.locations = [0, 0.28, 0.52, 0.74, 1]
        metal.startPoint = CGPoint(x: 0, y: 0)
        metal.endPoint = CGPoint(x: 1, y: 1)
        mainStroke.strokeColor = UIColor.white.cgColor
        metal.mask = mainStroke
        ribbon.addSublayer(metal)
        [lightTail, glint].forEach(ribbon.addSublayer)

    }

    required init?(coder: NSCoder) {
        fatalError("GraphiteResonanceSurface is code-only")
    }

    private func configureCloud(_ cloud: CAGradientLayer, white: CGFloat, alpha: CGFloat) {
        cloud.type = .radial
        cloud.startPoint = CGPoint(x: 0.5, y: 0.5)
        cloud.endPoint = CGPoint(x: 1.0, y: 1.0)
        cloud.colors = [
            UIColor(white: white, alpha: alpha).cgColor,
            UIColor(white: white, alpha: alpha * 0.31).cgColor,
            UIColor(white: white, alpha: 0).cgColor
        ]
        cloud.locations = [0, 0.40, 1]
        cloud.opacity = 0.50
        cloud.drawsAsynchronously = true
    }

    private func setupStroke(_ shape: CAShapeLayer, color: UIColor, width: CGFloat) {
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = width
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.contentsScale = UIScreen.main.scale
        shape.drawsAsynchronously = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        guard size.width > 0, size.height > 0, size != previousSize else { return }
        previousSize = size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artwork.frame = bounds
        halo.frame = bounds
        halo.path = UIBezierPath(ovalIn: CGRect(x: size.width * 0.065, y: size.height * 0.10,
                                              width: size.width * 0.87, height: size.height * 0.80)).cgPath
        cloudLeft.frame = CGRect(
            x: -size.width * 0.10, y: size.height * 0.12,
            width: size.width * 0.67, height: size.height * 0.82)
        cloudRight.frame = CGRect(
            x: size.width * 0.39, y: size.height * 0.02,
            width: size.width * 0.72, height: size.height * 0.88)
        cloudBottom.frame = CGRect(
            x: size.width * 0.18, y: size.height * 0.30,
            width: size.width * 0.69, height: size.height * 0.85)

        let width = min(ribbonWidth, size.width * 0.56)
        let height = width * ribbonHeight / ribbonWidth
        ribbon.frame = CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5 - 1,
            width: width, height: height)
        metal.frame = ribbon.bounds
        let path = makeInfinityPath(in: ribbon.bounds)
        for item in [aura, underside, mainStroke, lightTail, glint] {
            item.frame = ribbon.bounds
            item.path = path
        }
        aura.shadowPath = path.copy(strokingWithWidth: 16, lineCap: .round, lineJoin: .round, miterLimit: 10)
        // The closed contour has a single dash period, so the light wraps without a seam.
        contourLength = length(of: path)
        CATransaction.commit()
        configureMotion(force: true)
    }

    private func length(of path: CGPath) -> CGFloat {
        var last = CGPoint.zero
        var first = CGPoint.zero
        var total: CGFloat = 0
        func add(_ point: CGPoint) {
            total += hypot(point.x - last.x, point.y - last.y)
            last = point
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: last = element.points[0]; first = last
            case .addLineToPoint: add(element.points[0])
            case .addCurveToPoint:
                let start = last
                let a = element.points[0], b = element.points[1], end = element.points[2]
                for step in 1...48 {
                    let t = CGFloat(step) / 48, u = 1 - t
                    add(CGPoint(x: u*u*u*start.x + 3*u*u*t*a.x + 3*u*t*t*b.x + t*t*t*end.x,
                                y: u*u*u*start.y + 3*u*u*t*a.y + 3*u*t*t*b.y + t*t*t*end.y))
                }
            case .closeSubpath: add(first)
            default: break
            }
        }
        return max(1, total)
    }

    // Rounded, balanced 2:1 infinity. Sized to 188 x 108 points in the view.
    // Only the contour, not its geometry, responds to expressive voice energy.
    private func makeInfinityPath(in rect: CGRect) -> CGPath {
        let w = rect.width, h = rect.height
        let path = UIBezierPath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x * w, y: y * h)
        }
        path.move(to: pt(0.50, 0.50))
        path.addCurve(to: pt(0.27, 0.18),
                      controlPoint1: pt(0.42, 0.33), controlPoint2: pt(0.38, 0.18))
        path.addCurve(to: pt(0.08, 0.50),
                      controlPoint1: pt(0.16, 0.18), controlPoint2: pt(0.08, 0.31))
        path.addCurve(to: pt(0.27, 0.82),
                      controlPoint1: pt(0.08, 0.69), controlPoint2: pt(0.16, 0.82))
        path.addCurve(to: pt(0.50, 0.50),
                      controlPoint1: pt(0.38, 0.82), controlPoint2: pt(0.42, 0.67))
        path.addCurve(to: pt(0.73, 0.18),
                      controlPoint1: pt(0.58, 0.33), controlPoint2: pt(0.62, 0.18))
        path.addCurve(to: pt(0.92, 0.50),
                      controlPoint1: pt(0.84, 0.18), controlPoint2: pt(0.92, 0.31))
        path.addCurve(to: pt(0.73, 0.82),
                      controlPoint1: pt(0.92, 0.69), controlPoint2: pt(0.84, 0.82))
        path.addCurve(to: pt(0.50, 0.50),
                      controlPoint1: pt(0.62, 0.82), controlPoint2: pt(0.58, 0.67))
        path.close()
        return path.cgPath
    }

    // Individual composited layers drift slowly without triggering SwiftUI
    // body or layout recalculations. Paused by Core Animation automatically.
    private func startAmbientMovement() {
        addDrift(cloudLeft, dx: 15, dy: -6, seconds: 11)
        addDrift(cloudRight, dx: -18, dy: 7, seconds: 13)
        addDrift(cloudBottom, dx: 7, dy: -9, seconds: 16)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureMotion(force: true)
    }

    private func configureMotion(force: Bool = false) {
        let enabled = window != nil && !reduceMotion
        guard force || motionEnabled != enabled || configuredPhase != currentPhase else { return }
        motionEnabled = enabled
        configuredPhase = currentPhase
        let style = currentPhase.style
        let headPosition = (glint.presentation() as? CAShapeLayer)?.lineDashPhase ?? glint.lineDashPhase
        let tailPosition = (lightTail.presentation() as? CAShapeLayer)?.lineDashPhase ?? lightTail.lineDashPhase
        for item in [cloudLeft, cloudRight, cloudBottom, halo, glint, lightTail] {
            item.removeAllAnimations()
        }
        glint.lineDashPattern = [NSNumber(value: Double(contourLength) * 0.045),
                                NSNumber(value: Double(contourLength) * 0.955)]
        lightTail.lineDashPattern = [NSNumber(value: Double(contourLength) * style.tail),
                                    NSNumber(value: Double(contourLength) * (1 - style.tail))]
        guard enabled else { return }
        startAmbientMovement()
        for (item, position) in [(glint, headPosition), (lightTail, tailPosition)] {
            item.lineDashPhase = position
            let light = CABasicAnimation(keyPath: "lineDashPhase")
            light.fromValue = position
            light.toValue = position + (style.lap > 0 ? -contourLength : contourLength)
            light.duration = abs(style.lap)
            light.repeatCount = .infinity
            item.add(light, forKey: "contourLight")
        }
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 0.985
        breath.toValue = 1.015
        breath.duration = style.breath
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        halo.add(breath, forKey: "breathing")
    }

    private func addDrift(_ cloud: CALayer, dx: CGFloat, dy: CGFloat, seconds: CFTimeInterval) {
        for (axis, distance) in [("x", dx), ("y", dy)] {
            let animation = CABasicAnimation(keyPath: "transform.translation." + axis)
            animation.fromValue = -distance
            animation.toValue = distance
            animation.duration = seconds
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cloud.add(animation, forKey: "ambientDrift." + axis)
        }
    }

    func update(phase: LabResonancePhase, bands: LabAudioBands, orbitActive: Bool, reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        currentPhase = phase
        configureMotion()
        let style = phase.style
        let active = phase == .input || phase == .output
        // User-approved preset: Graphite + Expressive.
        let low = active ? min(1, bands.low * 1.7) : 0
        let mid = active ? min(1, bands.mid * 1.7) : 0
        let high = active ? min(1, bands.high * 1.7) : 0
        let energy = max(low, max(mid, high))

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        cloudLeft.opacity = style.cloud + Float(low * 0.38)
        cloudRight.opacity = style.cloud + Float(mid * 0.38)
        cloudBottom.opacity = style.cloud * 0.8 + Float(high * 0.44)
        aura.opacity = Float(0.16 + energy * 0.60 + (phase == .processing ? 0.11 : 0))
        aura.lineWidth = 15 + CGFloat(low) * 12
        glint.opacity = min(1, style.light + Float(high * 0.25))
        lightTail.opacity = 0.23 + Float(mid * 0.33)
        halo.opacity = style.halo + Float(energy * 0.22)
        mainStroke.lineWidth = 6.5 + CGFloat(mid) * 1.3
        // The form stays legible; dynamic change < 6%, unlike old 280px symbol.
        ribbon.transform = CATransform3DMakeScale(
            CGFloat(1 + low * 0.049), CGFloat(1 + mid * 0.048), 1)
        let fade: Float = orbitActive ? 0.08 : 1.0
        artwork.opacity = fade
        CATransaction.commit()
    }
}
