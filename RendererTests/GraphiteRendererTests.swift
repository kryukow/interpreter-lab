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
                let halo = try XCTUnwrap(artwork.sublayers?.compactMap { $0 as? CAShapeLayer }.first)
                XCTAssertNotNil(halo.path)
                XCTAssertLessThan(halo.lineWidth, 1)
                let ribbon = try XCTUnwrap(artwork.sublayers?.last)
                XCTAssertLessThanOrEqual(ribbon.bounds.width, 188)
                let strokes = try XCTUnwrap(ribbon.sublayers?.compactMap { $0 as? CAShapeLayer })
                XCTAssertEqual(strokes.count, 5)
                for stroke in strokes { XCTAssertNotNil(stroke.path) }
                XCTAssertNotNil(strokes.last?.animation(forKey: "contourLight"))
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
        surface.removeFromSuperview()
    }
}
