import SwiftUI
import UIKit
import QuartzCore

/// Graphite observatory: the canonical infinity in a quiet, layered orbital field.
/// Core Animation owns continuous motion; voice updates only change its intensity.
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
/// - Feathered dust-lane textures are baked once and transformed by the compositor.
/// - Core Animation drifts slender dust lanes independently from voice scales.
/// - A CAShapeLayer animates dashPhase for the continuously traveling ∞ highlight.
/// - Audio-driven changes touch only opacity/transform/stroke width at <=20 Hz.
final class GraphiteResonanceSurface: UIView {
    private let artwork = CALayer()
    // Graphite depth fades smoothly from center to black at the edges.
    private let graphiteDepth = CALayer()
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
    private let haloTracer = CAShapeLayer()
    private var haloLength: CGFloat = 1
    private let starfield = CALayer()
    private var satellites: [CAShapeLayer] = []
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
    private var contourOffset: CGFloat = 0
    private var ovalOffset: CGFloat = 0
    private var previousSize = CGSize.zero
    private var currentPhase: LabResonancePhase = .idle
    private var configuredPhase: LabResonancePhase?
    private var motionEnabled = false
    private var reducedMotion = false
    private var applicationActive = UIApplication.shared.applicationState != .background

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        layer.masksToBounds = false

        NotificationCenter.default.addObserver(self, selector: #selector(suspendMotion),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeMotion),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        artwork.masksToBounds = false
        layer.addSublayer(artwork)
        graphiteDepth.contents = Self.softRadialImage(
            color: UIColor(red: 0.42, green: 0.45, blue: 0.51, alpha: 1))
        graphiteDepth.contentsGravity = .resize
        graphiteDepth.contentsScale = 1
        graphiteDepth.opacity = 0.14
        artwork.addSublayer(graphiteDepth)
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
        // The orbital horizon remains visible while waiting.
        halo.opacity = 0.19
        artwork.addSublayer(halo)
        setupStroke(haloTracer, color: UIColor(white: 0.96, alpha: 1), width: 1.35)
        haloTracer.opacity = 0.42
        haloTracer.lineCap = .round
        artwork.addSublayer(haloTracer)

        artwork.addSublayer(starfield)
        for index in 0..<18 {
            let star = CAShapeLayer()
            star.fillColor = UIColor(white: index % 3 == 0 ? 0.92 : 0.65, alpha: 1).cgColor
            star.opacity = index % 3 == 0 ? 0.42 : 0.20
            starfield.addSublayer(star)
            satellites.append(star)
        }
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
        // Moving contour light: a luminous leading bar and broad diffused tail.
        // At a compact glyph size 1.7pt was barely visible on its metal surface.
        setupStroke(lightTail, color: UIColor(white: 0.98, alpha: 1), width: 8.8)
        setupStroke(glint, color: .white, width: 4.2)
        glint.opacity = 0.98
        glint.shadowColor = UIColor.white.cgColor
        glint.shadowOpacity = 0.58
        glint.shadowRadius = 5
        glint.shadowOffset = .zero
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

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func suspendMotion() {
        applicationActive = false
        configureMotion(force: true)
    }

    @objc private func resumeMotion() {
        applicationActive = true
        // iOS can discard compositor animations while the view remains attached.
        // Rebuild explicitly; a SwiftUI update or layout is not guaranteed on return.
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        configureMotion(force: true)
    }

    required init?(coder: NSCoder) {
        fatalError("GraphiteResonanceSurface is code-only")
    }

    private static func softRadialImage(color: UIColor) -> CGImage? {
        // Pre-baking feathered falloff avoids live blur and offscreen render passes.
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
        graphiteDepth.frame = CGRect(x: size.width * 0.035, y: size.height * 0.025,
                                     width: size.width * 0.93, height: size.height * 0.93)
        // Thin dust lanes create depth without large opaque spots behind the glyph.
        for holder in [leftDrift, rightDrift, bottomDrift, centerDrift] { holder.frame = bounds }
        cloudLeft.frame = CGRect(x: size.width * 0.08, y: size.height * 0.44,
                                 width: size.width * 0.48, height: size.height * 0.065)
        cloudRight.frame = CGRect(x: size.width * 0.49, y: size.height * 0.49,
                                  width: size.width * 0.43, height: size.height * 0.045)
        cloudBottom.frame = CGRect(x: size.width * 0.23, y: size.height * 0.66,
                                   width: size.width * 0.54, height: size.height * 0.035)
        cloudCenter.frame = CGRect(x: size.width * 0.33, y: size.height * 0.29,
                                   width: size.width * 0.38, height: size.height * 0.025)
        bloom.frame = CGRect(x: size.width * 0.29, y: size.height * 0.30,
                             width: size.width * 0.42, height: size.height * 0.35)
        starfield.frame = bounds
        for (index, star) in satellites.enumerated() {
            let angle = CGFloat(index) * 2.399963
            let radius = CGFloat(0.68 + Double(index % 5) * 0.07)
            let point = CGPoint(x: size.width * 0.5 + cos(angle) * size.width * 0.39 * radius,
                                y: size.height * 0.48 + sin(angle) * size.height * 0.38 * radius)
            let diameter: CGFloat = index % 4 == 0 ? 1.6 : 0.85
            star.path = UIBezierPath(ovalIn: CGRect(x: point.x, y: point.y,
                                                  width: diameter, height: diameter)).cgPath
        }
        let oval = UIBezierPath(ovalIn: CGRect(
            x: size.width * 0.175, y: size.height * 0.21,
            width: size.width * 0.65, height: size.height * 0.48)).cgPath
        halo.frame = bounds
        halo.path = oval
        haloTracer.frame = bounds
        haloTracer.path = oval
        haloLength = length(of: oval)

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
        let enabled = window != nil && applicationActive && !reducedMotion
        guard force || enabled != motionEnabled || configuredPhase != currentPhase else { return }
        motionEnabled = enabled
        configuredPhase = currentPhase

        contourOffset = glint.presentation()?.lineDashPhase ?? contourOffset
        ovalOffset = haloTracer.presentation()?.lineDashPhase ?? ovalOffset
        [leftDrift, rightDrift, bottomDrift, centerDrift].forEach { $0.removeAllAnimations() }
        [halo, haloTracer, glint, lightTail, starfield].forEach { $0.removeAllAnimations() }

        guard enabled else { return }
        let style = currentPhase.style
        let orbit = CABasicAnimation(keyPath: "transform.rotation.z")
        orbit.fromValue = 0
        orbit.toValue = currentPhase == .output ? -Double.pi * 2 : Double.pi * 2
        orbit.duration = abs(style.lap) * 8
        orbit.repeatCount = .infinity
        orbit.timingFunction = CAMediaTimingFunction(name: .linear)
        starfield.add(orbit, forKey: "siderealOrbit")
        // Independent slow drift keeps the narrow dust lanes from moving as one sheet.
        animateDrift(leftDrift, dx: 19, dy: 7, seconds: 12)
        animateDrift(rightDrift, dx: -16, dy: 12, seconds: 14)
        animateDrift(bottomDrift, dx: 11, dy: -13, seconds: 17)
        animateDrift(centerDrift, dx: -8, dy: 9, seconds: 9)

        // The large, fine oval is alive even when waiting: very slow
        // scaling in sync with a quiet orbiting silver shimmer. No center
        // bar expanding independently of the ellipse.
        let ovalBreath = CABasicAnimation(keyPath: "transform.scale")
        ovalBreath.fromValue = 0.985
        ovalBreath.toValue = 1.035
        ovalBreath.duration = style.breath
        ovalBreath.autoreverses = true
        ovalBreath.repeatCount = .infinity
        ovalBreath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for ovalLayer in [halo, haloTracer] {
            ovalLayer.add(ovalBreath.copy() as! CAAnimation, forKey: "breathingOval")
        }

        haloTracer.lineDashPattern = [
            NSNumber(value: Double(haloLength * 0.075)),
            NSNumber(value: Double(haloLength * 0.925))
        ]
        let ovalOrbit = CABasicAnimation(keyPath: "lineDashPhase")
        ovalOrbit.fromValue = ovalOffset
        ovalOrbit.toValue = ovalOffset + (style.lap < 0 ? haloLength : -haloLength)
        ovalOrbit.duration = abs(style.lap)
        ovalOrbit.repeatCount = .infinity
        ovalOrbit.timingFunction = CAMediaTimingFunction(name: .linear)
        haloTracer.add(ovalOrbit, forKey: "ovalLightOrbit")

        // Concept 03: a 40-unit bright segment follows a 900-unit gap.
        // Arc-length normalized => no visible jump at the loop seam.
        let segment = min(CGFloat(40) * 0.61, contourLength * 0.08)
        glint.lineDashPattern = [NSNumber(value: Double(segment)),
                                 NSNumber(value: Double(contourLength - segment))]
        lightTail.lineDashPattern = [NSNumber(value: Double(segment * 2.1)),
                                     NSNumber(value: Double(contourLength - segment * 2.1))]
        animateLight(glint, lap: style.lap)
        animateLight(lightTail, lap: style.lap)
    }

    private func animateLight(_ shape: CAShapeLayer, lap: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "lineDashPhase")
        animation.fromValue = contourOffset
        animation.toValue = contourOffset + (lap < 0 ? contourLength : -contourLength)
        animation.duration = abs(lap)
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
        let phaseChanged = currentPhase != phase
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
        CATransaction.setAnimationDuration(phaseChanged ? 0.65 : 0.16)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        let style = phase.style
        // Dust lane opacity + scale follow real timbre, not a random animation.

        cloudLeft.opacity = Float(0.035 + 0.14 * (active ? bass : 0.33))
        cloudRight.opacity = Float(0.035 + 0.14 * (active ? mids : 0.33))
        cloudBottom.opacity = Float(0.035 + 0.14 * (active ? highs : 0.33))
        cloudCenter.opacity = Float(0.025 + 0.12 * (active ? energy : 0.33))
        cloudLeft.transform = CATransform3DMakeScale(CGFloat(1 + 0.58 * bass), CGFloat(1 + 0.58 * bass), 1)
        cloudRight.transform = CATransform3DMakeScale(CGFloat(1 + 0.47 * mids), CGFloat(1 + 0.47 * mids), 1)
        cloudBottom.transform = CATransform3DMakeScale(CGFloat(1 + 0.50 * highs), CGFloat(1 + 0.50 * highs), 1)
        cloudCenter.transform = CATransform3DMakeScale(CGFloat(1 + 0.72 * energy), CGFloat(1 + 0.72 * energy), 1)
        // Prevent the broad center blob that obscured the graphite fog.
        // Keep the Expressive response in the actual clouds and ∞ ribbon.
        bloom.opacity = Float(0.018 + 0.045 * energy)
        bloom.transform = CATransform3DMakeScale(CGFloat(0.82 + 0.14 * energy),
                                                CGFloat(0.82 + 0.14 * energy), 1)

        // Thin animated ellipse is always visible; voice increases its contrast.
        halo.opacity = style.halo + Float(0.12 * mids)
        haloTracer.opacity = style.light * 0.65 + Float(0.15 * highs)
        // Original CSS: audio bass expands X, mid range expands Y.
        ribbon.transform = CATransform3DMakeScale(CGFloat(1 + bass * 0.085),
                                                  CGFloat(1 + mids * 0.060), 1)
        aura.opacity = Float(0.06 + 0.20 * energy)
        aura.lineWidth = 17 + CGFloat(bass * 10)
        // A clearly visible moving white bar must not disappear on quiet syllables.
        glint.opacity = style.light + Float(0.06 * highs)
        lightTail.opacity = Float(style.tail) + Float(0.10 * mids)
        let fade: Float = orbitActive ? 0.08 : 1
        artwork.opacity = fade
        CATransaction.commit()
    }
}
