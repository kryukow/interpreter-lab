import XCTest
import UIKit
@testable import InterpreterLab

final class GraphiteRendererTests: XCTestCase {
    @MainActor func testAllPhasesAtPhoneSizes() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let surface = GraphiteResonanceSurface()
        controller.view.addSubview(surface)
        for width in [CGFloat(284), 354, 394] {
            surface.frame = CGRect(x: 18, y: 40, width: width, height: 168)
            surface.layoutIfNeeded()
            for phase in LabResonancePhase.allCases {
                surface.update(phase: phase, bands: .init(low: 0.4, mid: 0.7, high: 0.5),
                               orbitActive: false, reduceMotion: false)
                let artwork = try XCTUnwrap(surface.layer.sublayers?.first)
                let halo = try XCTUnwrap(artwork.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.lineWidth < 1 })
                XCTAssertNotNil(halo.path)
                XCTAssertLessThan(halo.lineWidth, 1)
                XCTAssertGreaterThan(halo.opacity, 0.10, "Orbital horizon stays visible at idle")
                XCTAssertNotNil(halo.animation(forKey: "breathingOval"),
                                "The oval must actually breathe, not stay static")
                let ovalTracers = try XCTUnwrap(artwork.sublayers?.compactMap { $0 as? CAShapeLayer })
                XCTAssertGreaterThanOrEqual(ovalTracers.count, 2)
                let haloTracer = try XCTUnwrap(ovalTracers.first { $0.lineWidth > 1 })
                XCTAssertNotNil(haloTracer.animation(forKey: "ovalLightOrbit"),
                                "Light must travel around the elliptical halo")
                let ribbon = try XCTUnwrap(artwork.sublayers?.first { layer in
                    layer.sublayers?.contains(where: { $0 is CAGradientLayer }) == true
                })
                XCTAssertLessThanOrEqual(ribbon.bounds.width, 188)
                let strokes = try XCTUnwrap(ribbon.sublayers?.compactMap { ($0 as? CAShapeLayer) ?? ($0.mask as? CAShapeLayer) })
                XCTAssertEqual(strokes.count, 5)
                for stroke in strokes { XCTAssertNotNil(stroke.path) }
                XCTAssertNotNil(strokes.first(where: { abs($0.lineWidth - 4.2) < 0.01 })?.animation(forKey: "contourLight"),
                                "Every stage retains a continuous, phase-paced contour")
                let image = UIGraphicsImageRenderer(bounds: surface.bounds).image { context in
                    UIColor.black.setFill()
                    context.fill(surface.bounds)
                    surface.layer.render(in: context.cgContext)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "Graphite-\(phase)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        surface.update(phase: .input, bands: .silence, orbitActive: true, reduceMotion: true)
        let artwork = try XCTUnwrap(surface.layer.sublayers?.first)
        XCTAssertEqual(artwork.opacity, 0.08, accuracy: 0.001)
        for cloud in artwork.sublayers ?? [] { XCTAssertTrue(cloud.animationKeys()?.isEmpty ?? true) }
        surface.update(phase: .processing, bands: .silence, orbitActive: false, reduceMotion: false)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let ribbon = try XCTUnwrap(artwork.sublayers?.first { layer in
                    layer.sublayers?.contains(where: { $0 is CAGradientLayer }) == true
                })
        let glint = try XCTUnwrap(ribbon.sublayers?.compactMap { $0 as? CAShapeLayer }.first { abs($0.lineWidth - 4.2) < 0.01 })
        XCTAssertNil(glint.animation(forKey: "contourLight"))
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertNotNil(glint.animation(forKey: "contourLight"),
                        "Resuming must restart motion without relying on layout or a phase change")
        surface.update(phase: .processing, bands: .silence, orbitActive: false, reduceMotion: true)
        XCTAssertNil(glint.animation(forKey: "contourLight"))
        surface.removeFromSuperview()
    }
}
