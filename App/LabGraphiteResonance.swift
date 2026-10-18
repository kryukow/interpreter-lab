import SwiftUI
import UIKit
import QuartzCore

enum LabResonancePhase: Equatable {
    case idle, input, processing, output
}

/// Approved Graphite / Expressive theme.
///
/// No TimelineView, Canvas, per-frame SwiftUI rendering, .blur modifiers, or
/// software filters. The monochrome blobs drift via Core Animation on their
/// own composited layers. Only small layer properties change when mic / actual
/// Apple TTS samples arrive (capped to ~20 Hz in LabSession).
struct LabGraphiteResonance: UIViewRepresentable {
    let phase: LabResonancePhase
    let bands: LabAudioBands
    let orbitActive: Bool

    func makeUIView(context: Context) -> GraphiteResonanceSurface {
        let view = GraphiteResonanceSurface()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.update(phase: phase, bands: bands, orbitActive: orbitActive)
        return view
    }

    func updateUIView(_ uiView: GraphiteResonanceSurface, context: Context) {
        uiView.update(phase: phase, bands: bands, orbitActive: orbitActive)
    }
}

/// CA-native renderer: 3 feathered radial-gradient blobs and one compact,
/// balanced infinity ribbon. Purely decorative; never touches microphone,
/// network, translation, or audio playback.
final class GraphiteResonanceSurface: UIView {
    private let cloudLeft = CAGradientLayer()
    private let cloudRight = CAGradientLayer()
    private let cloudBottom = CAGradientLayer()
    private let ribbon = CALayer()
    private let aura = CAShapeLayer()
    private let underside = CAShapeLayer()
    private let mainStroke = CAShapeLayer()
    private let glint = CAShapeLayer()
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
        layer.addSublayer(cloudLeft)
        layer.addSublayer(cloudRight)
        layer.addSublayer(cloudBottom)

        ribbon.masksToBounds = false
        layer.addSublayer(ribbon)
        setupStroke(aura, color: UIColor(white: 0.83, alpha: 1), width: 16)
        aura.opacity = 0.18
        aura.shadowColor = UIColor(white: 0.88, alpha: 1).cgColor
        aura.shadowRadius = 9
        aura.shadowOpacity = 0.26
        aura.shadowOffset = .zero
        setupStroke(underside, color: UIColor(white: 0.23, alpha: 1), width: 10)
        setupStroke(mainStroke, color: UIColor(white: 0.95, alpha: 1), width: 6.5)
        setupStroke(glint, color: .white, width: 2.1)
        glint.opacity = 0.25
        glint.lineDashPattern = [22, 360]
        [aura, underside, mainStroke, glint].forEach(ribbon.addSublayer)
        startAmbientMovement()
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
        let path = makeInfinityPath(in: ribbon.bounds)
        for item in [aura, underside, mainStroke, glint] {
            item.frame = ribbon.bounds
            item.path = path
        }
        CATransaction.commit()
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
        return path.cgPath
    }

    // Individual composited layers drift slowly without triggering SwiftUI
    // body or layout recalculations. Paused by Core Animation automatically.
    private func startAmbientMovement() {
        addDrift(cloudLeft, dx: 15, dy: -6, seconds: 11)
        addDrift(cloudRight, dx: -18, dy: 7, seconds: 13)
        addDrift(cloudBottom, dx: 7, dy: -9, seconds: 16)
        let light = CABasicAnimation(keyPath: "lineDashPhase")
        light.fromValue = 0
        light.toValue = 390
        light.duration = 7.5
        light.repeatCount = .infinity
        glint.add(light, forKey: "quietGlint")
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

    func update(phase: LabResonancePhase, bands: LabAudioBands, orbitActive: Bool) {
        currentPhase = phase
        let active = phase == .input || phase == .output
        // User-approved preset: Graphite + Expressive.
        let low = active ? min(1, bands.low * 1.7) : 0
        let mid = active ? min(1, bands.mid * 1.7) : 0
        let high = active ? min(1, bands.high * 1.7) : 0
        let energy = max(low, max(mid, high))

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        cloudLeft.opacity = Float(0.38 + low * 0.51)
        cloudRight.opacity = Float(0.38 + mid * 0.54)
        cloudBottom.opacity = Float(0.29 + high * 0.61)
        aura.opacity = Float(0.16 + energy * 0.60 + (phase == .processing ? 0.11 : 0))
        aura.lineWidth = 15 + CGFloat(low) * 12
        glint.opacity = Float(0.22 + high * 0.58)
        mainStroke.lineWidth = 6.5 + CGFloat(mid) * 1.3
        // The form stays legible; dynamic change < 6%, unlike old 280px symbol.
        ribbon.transform = CATransform3DMakeScale(
            CGFloat(1 + low * 0.049), CGFloat(1 + mid * 0.048), 1)
        let fade: Float = orbitActive ? 0.08 : 1.0
        ribbon.opacity = fade
        CATransaction.commit()
    }
}
