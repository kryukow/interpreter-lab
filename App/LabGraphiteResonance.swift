import SwiftUI
import UIKit
import QuartzCore

/// The accepted RESONANCE / CONCEPT 03, palette Graphite, preset Expressive.
/// Canonical SVG path/control points, 4 soft monochrome clouds, 65% x 48%
/// thin oval halo, and 40-unit traveling highlight are carried over from the
/// actual approved interactive prototype. No alternative drawing is used.
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

/// Compositor-only rendering:
/// - Blurred radial light fields are drawn into 256px textures ONCE, not blurred
///   or repainted every frame.
/// - Core Animation drifts cloud holders independently from their voice scales.
/// - A CAShapeLayer animates dashPhase for the continuously traveling ∞ highlight.
/// - Audio-driven changes touch only opacity/transform/stroke width at <=20 Hz.
final class GraphiteResonanceSurface: UIView {
    private let artwork = CALayer()
    private let leftDrift = CALayer()
    private let rightDrift = CALayer()
    private let bottomDrift = CALayer()
    private let centerDrift = CALayer()
    private let cloudLeft = CALayer()
    private let cloudRight = CALayer()
    private let cloudBottom = CALayer()
    private let cloudCenter = CALayer()
    private let bloom = CALayer()

    private let halo = CAShapeLayer()
    private let ribbon = CALayer()
    private let aura = CAShapeLayer()
    private let underside = CAShapeLayer()
    private let mainStroke = CAShapeLayer()
    private let metal = CAGradientLayer()
    private let glint = CAShapeLayer()
    private let lightTail = CAShapeLayer()

    // The SVG path is reproduced from CONCEPT 03's exact geometry:
    // M186 132 C162 99 145 82 113 82 ... C226 183 208 155 186 132
    // Its painted region is ~149 x 62 points at full size, vs 244 x 101 SVG units.
    private let ribbonWidth: CGFloat = 188
    private let ribbonHeight: CGFloat = 112
    private var contourLength: CGFloat = 1
    private var previousSize = CGSize.zero
    private var currentPhase: LabResonancePhase = .idle
    private var configuredPhase: LabResonancePhase?
    private var motionEnabled = false
    private var reducedMotion = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        artwork.masksToBounds = false
        layer.addSublayer(artwork)
        let cloudConfigurations: [(holder: CALayer, light: CALayer, color: UIColor)] = [
            (leftDrift, cloudLeft, UIColor(red: 0.4118, green: 0.4431, blue: 0.5059, alpha: 1)), // #697181
            (rightDrift, cloudRight, UIColor(red: 0.8275, green: 0.8471, blue: 0.8902, alpha: 1)), // #D3D8E3
            (bottomDrift, cloudBottom, UIColor(red: 0.5020, green: 0.5373, blue: 0.6196, alpha: 1)), // #80899E
            (centerDrift, cloudCenter, UIColor(red: 0.7843, green: 0.7961, blue: 0.8431, alpha: 1)) // #C8CBD7
        ]
        for (holder, light, color) in cloudConfigurations {
            holder.masksToBounds = false
            artwork.addSublayer(holder)
            light.contents = Self.softRadialImage(color: color)
            light.contentsGravity = .resize
            light.contentsScale = 1
            light.minificationFilter = .linear
            light.magnificationFilter = .linear
            light.masksToBounds = false
            holder.addSublayer(light)
        }
        bloom.contents = Self.softRadialImage(
            color: UIColor(red: 0.7843, green: 0.7961, blue: 0.8431, alpha: 1))
        bloom.contentsGravity = .resize
        bloom.contentsScale = 1
        bloom.opacity = 0.07
        artwork.addSublayer(bloom)

        setupStroke(halo, color: UIColor(red: 0.7843, green: 0.7961, blue: 0.8431, alpha: 1),
                    width: 0.75)
        halo.opacity = 0
        artwork.addSublayer(halo)

        ribbon.masksToBounds = false
        artwork.addSublayer(ribbon)
        setupStroke(aura, color: UIColor(red: 0.7843, green: 0.7961, blue: 0.8431, alpha: 1),
                    width: 19)
        aura.shadowColor = UIColor(white: 0.92, alpha: 1).cgColor
        aura.shadowOpacity = 0.20
        aura.shadowRadius = 11
        aura.shadowOffset = .zero
        aura.opacity = 0.13
        setupStroke(underside, color: UIColor(white: 0.18, alpha: 1), width: 9)
        setupStroke(mainStroke, color: .white, width: 6.7)
        setupStroke(lightTail, color: UIColor(white: 1, alpha: 1), width: 4.0)
        setupStroke(glint, color: .white, width: 1.7)
        glint.opacity = 0.42
        [aura, underside].forEach(ribbon.addSublayer)

        // Silver/graphite metal from the approved CSS gradient, not flat white.
        metal.colors = [
            UIColor(red: 0.682, green: 0.722, blue: 0.827, alpha: 1).cgColor,
            UIColor.white.cgColor,
            UIColor(red: 0.827, green: 0.859, blue: 0.922, alpha: 1).cgColor,
            UIColor.white.cgColor,
            UIColor(red: 0.694, green: 0.722, blue: 0.820, alpha: 1).cgColor
        ]
        metal.locations = [0, 0.22, 0.56, 0.79, 1]
        metal.startPoint = CGPoint(x: 0, y: 0)
        metal.endPoint = CGPoint(x: 1, y: 1)
        metal.mask = mainStroke
        ribbon.addSublayer(metal)
        [lightTail, glint].forEach(ribbon.addSublayer)
        lightTail.opacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("GraphiteResonanceSurface is code-only")
    }

    private static func softRadialImage(color: UIColor) -> CGImage? {
        // The accepted CSS used radial-gradient(..., transparent 69%) and
        // filter:blur(38px). Pre-baking feathered falloff eliminates GPU blur.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
        return renderer.image { image in
            let context = image.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let colors: [CGColor] = [
                color.withAlphaComponent(0.75).cgColor,
                color.withAlphaComponent(0.48).cgColor,
                color.withAlphaComponent(0.15).cgColor,
                color.withAlphaComponent(0).cgColor
            ]
            guard let gradient = CGGradient(colorsSpace: space,
                                            colors: colors as CFArray,
                                            locations: [0.0, 0.25, 0.55, 0.94]) else { return }
            context.drawRadialGradient(
                gradient, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                endCenter: CGPoint(x: 128, y: 128), endRadius: 128,
                options: [.drawsAfterEndLocation]
            )
        }.cgImage
    }

    private func setupStroke(_ shape: CAShapeLayer, color: UIColor, width: CGFloat) {
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.lineWidth = width
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
        // Percentages are DIRECTLY from CONCEPT 03's Graphite stage:
        // clouds: a[-14%,4%,62%,73%], b[49%,2%,69%,77%],
        // c[18%,52%,67%,61%], d[27%,23%,45%,48%].
        for holder in [leftDrift, rightDrift, bottomDrift, centerDrift] {
            holder.frame = bounds
        }
        cloudLeft.frame = CGRect(x: -0.14 * size.width, y: 0.04 * size.height,
                                 width: 0.62 * size.width, height: 0.73 * size.height)
        cloudRight.frame = CGRect(x: 0.49 * size.width, y: 0.02 * size.height,
                                  width: 0.69 * size.width, height: 0.77 * size.height)
        cloudBottom.frame = CGRect(x: 0.18 * size.width, y: 0.52 * size.height,
                                   width: 0.67 * size.width, height: 0.61 * size.height)
        cloudCenter.frame = CGRect(x: 0.27 * size.width, y: 0.23 * size.height,
                                   width: 0.45 * size.width, height: 0.48 * size.height)

        bloom.frame = CGRect(x: size.width * 0.16, y: size.height * 0.16,
                             width: size.width * 0.68, height: size.height * 0.65)
        halo.frame = bounds
        halo.path = UIBezierPath(ovalIn: CGRect(
            x: size.width * 0.175, y: size.height * 0.21,
            width: size.width * 0.65, height: size.height * 0.48)).cgPath

        let width = min(ribbonWidth, size.width * 0.60)
        let height = width * ribbonHeight / ribbonWidth
        ribbon.frame = CGRect(x: (size.width - width) * 0.5,
                              y: (size.height - height) * 0.5 - 1,
                              width: width, height: height)
        metal.frame = ribbon.bounds
        let path = makeConcept03InfinityPath(in: ribbon.bounds)
        for shape in [aura, underside, mainStroke, lightTail, glint] {
            shape.frame = ribbon.bounds
            shape.path = path
        }
        aura.shadowPath = path.copy(strokingWithWidth: 19, lineCap: .round,
                                    lineJoin: .round, miterLimit: 10)
        contourLength = length(of: path)
        CATransaction.commit()
        configureMotion(force: true)
    }

    /// Exact canonical control points from the approved interactive SVG:
    /// M186 132 C162 99 145 82 113 82 C83 82 64 104 64 132
    /// C64 161 85 183 113 183 C148 183 166 153 186 132
    /// C210 110 226 82 258 82 C288 82 308 104 308 132
    /// C308 161 287 183 258 183 C226 183 208 155 186 132
    /// Uniform scaling prevents any horizontal stretch.
    private func makeConcept03InfinityPath(in rect: CGRect) -> CGPath {
        let path = UIBezierPath()
        let scale = min(0.61, rect.width * 0.86 / 244, rect.height * 0.72 / 101)
        let cx = rect.width / 2
        let cy = rect.height / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cx + (x - 186) * scale, y: cy + (y - 132) * scale)
        }
        path.move(to: p(186, 132))
        path.addCurve(to: p(113, 82),
                      controlPoint1: p(162, 99), controlPoint2: p(145, 82))
        path.addCurve(to: p(64, 132),
                      controlPoint1: p(83, 82), controlPoint2: p(64, 104))
        path.addCurve(to: p(113, 183),
                      controlPoint1: p(64, 161), controlPoint2: p(85, 183))
        path.addCurve(to: p(186, 132),
                      controlPoint1: p(148, 183), controlPoint2: p(166, 153))
        path.addCurve(to: p(258, 82),
                      controlPoint1: p(210, 110), controlPoint2: p(226, 82))
        path.addCurve(to: p(308, 132),
                      controlPoint1: p(288, 82), controlPoint2: p(308, 104))
        path.addCurve(to: p(258, 183),
                      controlPoint1: p(308, 161), controlPoint2: p(287, 183))
        path.addCurve(to: p(186, 132),
                      controlPoint1: p(226, 183), controlPoint2: p(208, 155))
        path.close()
        return path.cgPath
    }

    private func length(of path: CGPath) -> CGFloat {
        var total: CGFloat = 0
        var last = CGPoint.zero
        var first = CGPoint.zero
        func advance(_ next: CGPoint) {
            total += hypot(next.x - last.x, next.y - last.y)
            last = next
        }
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                last = element.points[0]; first = last
            case .addLineToPoint: advance(element.points[0])
            case .addCurveToPoint:
                let a = element.points[0], b = element.points[1], end = element.points[2]
                let start = last
                for step in 1...48 {
                    let t = CGFloat(step) / 48, u = 1 - t
                    advance(CGPoint(
                        x: u*u*u*start.x + 3*u*u*t*a.x + 3*u*t*t*b.x + t*t*t*end.x,
                        y: u*u*u*start.y + 3*u*u*t*a.y + 3*u*t*t*b.y + t*t*t*end.y))
                }
            case .closeSubpath: advance(first)
            default: break
            }
        }
        return max(1, total)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureMotion(force: true)
    }

    private func configureMotion(force: Bool = false) {
        let enabled = window != nil && !reducedMotion
        guard force || enabled != motionEnabled || configuredPhase != currentPhase else { return }
        motionEnabled = enabled
        configuredPhase = currentPhase

        [leftDrift, rightDrift, bottomDrift, centerDrift].forEach { $0.removeAllAnimations() }
        [glint, lightTail].forEach { $0.removeAllAnimations() }

        guard enabled else { return }
        // Slow drifts directly follow the CSS 12/14/17/9-second ambient field.
        animateDrift(leftDrift, dx: 19, dy: 7, seconds: 12)
        animateDrift(rightDrift, dx: -16, dy: 12, seconds: 14)
        animateDrift(bottomDrift, dx: 11, dy: -13, seconds: 17)
        animateDrift(centerDrift, dx: -8, dy: 9, seconds: 9)

        // Concept 03: a 40-unit bright segment follows a 900-unit gap.
        // Arc-length normalized => no visible jump at the loop seam.
        let segment = min(CGFloat(40) * 0.61, contourLength * 0.08)
        glint.lineDashPattern = [NSNumber(value: Double(segment)),
                                 NSNumber(value: Double(contourLength - segment))]
        lightTail.lineDashPattern = [NSNumber(value: Double(segment * 2)),
                                     NSNumber(value: Double(contourLength - segment * 2))]
        if currentPhase == .input || currentPhase == .output {
            animateLight(glint, lap: 4.0)
            animateLight(lightTail, lap: 4.0)
        }
    }

    private func animateLight(_ shape: CAShapeLayer, lap: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = 0
        animation.toValue = -contourLength
        animation.duration = lap
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        shape.add(animation, forKey: "contourLight")
    }

    private func animateDrift(_ cloud: CALayer, dx: CGFloat, dy: CGFloat, seconds: CFTimeInterval) {
        for (axis, distance) in [("x", dx), ("y", dy)] {
            let anim = CABasicAnimation(keyPath: "transform.translation." + axis)
            anim.fromValue = -distance
            anim.toValue = distance
            anim.duration = seconds
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cloud.add(anim, forKey: "ambient." + axis)
        }
    }

    func update(phase: LabResonancePhase, bands: LabAudioBands,
                orbitActive: Bool, reduceMotion: Bool) {
        reducedMotion = reduceMotion
        currentPhase = phase
        configureMotion()
        let active = phase == .input || phase == .output
        // Exact approved "Expressive" multiplier: 1.7.
        let bass = active ? min(1, bands.low * 1.7) : 0
        let mids = active ? min(1, bands.mid * 1.7) : 0
        let highs = active ? min(1, bands.high * 1.7) : 0
        let energy = max(bass, max(mids, highs))

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.10)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        // Cloud opacity + scale follow real timbre, not a random animation.
        // Match JS: idle .395/.362; active .23 + .5*voice, center .23 + .4*voice.
        cloudLeft.opacity = Float(0.23 + 0.50 * (active ? bass : 0.33))
        cloudRight.opacity = Float(0.23 + 0.50 * (active ? mids : 0.33))
        cloudBottom.opacity = Float(0.23 + 0.50 * (active ? highs : 0.33))
        cloudCenter.opacity = Float(0.23 + 0.40 * (active ? energy : 0.33))
        cloudLeft.transform = CATransform3DMakeScale(CGFloat(1 + 0.58 * bass), CGFloat(1 + 0.58 * bass), 1)
        cloudRight.transform = CATransform3DMakeScale(CGFloat(1 + 0.47 * mids), CGFloat(1 + 0.47 * mids), 1)
        cloudBottom.transform = CATransform3DMakeScale(CGFloat(1 + 0.50 * highs), CGFloat(1 + 0.50 * highs), 1)
        cloudCenter.transform = CATransform3DMakeScale(CGFloat(1 + 0.72 * energy), CGFloat(1 + 0.72 * energy), 1)
        bloom.opacity = Float(active ? (0.08 + 0.55 * energy) : 0.07)
        bloom.transform = CATransform3DMakeScale(CGFloat(0.85 + 0.46 * energy),
                                                CGFloat(0.85 + 0.46 * energy), 1)

        // Original CSS: ring is invisible while idle / processing.
        halo.opacity = active ? Float(0.10 + 0.38 * mids) : 0
        // Original CSS: audio bass expands X, mid range expands Y.
        ribbon.transform = CATransform3DMakeScale(CGFloat(1 + bass * 0.085),
                                                  CGFloat(1 + mids * 0.060), 1)
        aura.opacity = Float(0.13 + 0.63 * energy)
        aura.lineWidth = 19 + CGFloat(bass * 16)
        glint.opacity = active ? Float(0.35 + 0.65 * highs) : 0
        lightTail.opacity = active ? Float(0.22 + 0.35 * mids) : 0
        let fade: Float = orbitActive ? 0.08 : 1
        artwork.opacity = fade
        CATransaction.commit()
    }
}
