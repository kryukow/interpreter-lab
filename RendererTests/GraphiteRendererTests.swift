import XCTest
import UIKit
@testable import InterpreterLab

final class GraphiteRendererTests: XCTestCase {
    @MainActor func testSphereStagesAtPhoneSizesAndLifecycle() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 932))
        let controller = UIViewController()
        controller.view.backgroundColor = .black
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let surface = GraphiteResonanceSurface()
        controller.view.addSubview(surface)
        for width in [CGFloat(284), 354, 394] {
            surface.frame = CGRect(x: 0, y: 40, width: width, height: 235)
            surface.layoutIfNeeded()
            XCTAssertEqual(surface.sphereRadius, 61 * width / 395, accuracy: 0.01)
            for phase in LabResonancePhase.allCases {
                surface.update(phase: phase, bands: .init(low: 0.4, mid: 0.7, high: 0.5),
                               orbitActive: false, reduceMotion: false)
                XCTAssertTrue(surface.isAnimating, "Every sphere stage stays alive")
                try await Task.sleep(nanoseconds: 700_000_000)
                // Hosted test windows need not receive compositor display passes.
                // Exercise the production drawing code explicitly in a real context.
                surface.setNeedsDisplay()
                surface.layoutIfNeeded()
                surface.layer.displayIfNeeded()
                let framesBeforeSnapshot = surface.renderedFrames
                let image = UIGraphicsImageRenderer(bounds: surface.bounds).image { context in
                    UIColor.black.setFill()
                    context.fill(surface.bounds)
                    surface.draw(surface.bounds)
                }
                XCTAssertGreaterThan(surface.renderedFrames, framesBeforeSnapshot,
                                     "Snapshot must execute the real sphere renderer")
                let bitmap = try XCTUnwrap(image.cgImage)
                var pixel = [UInt8](repeating: 0, count: 4)
                pixel.withUnsafeMutableBytes { storage in
                    let sample = CGContext(data: storage.baseAddress, width: 1, height: 1,
                                           bitsPerComponent: 8, bytesPerRow: 4,
                                           space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    sample.interpolationQuality = .high
                    sample.draw(bitmap, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                }
                XCTAssertGreaterThan(Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]), 0,
                                     "The rendered sphere must contain visible graphite light")
                let attachment = XCTAttachment(image: image)
                attachment.name = "Graphite-Sphere-\(phase)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertFalse(surface.isAnimating)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(surface.isAnimating, "Return restarts without a phase or layout change")
        surface.update(phase: .input, bands: .silence, orbitActive: false, reduceMotion: true)
        XCTAssertFalse(surface.isAnimating, "Reduce Motion keeps a static sphere without a display link")
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(surface.isAnimating, "Resume respects Reduce Motion")
        surface.update(phase: .output, bands: .silence, orbitActive: false, reduceMotion: false)
        XCTAssertTrue(surface.isAnimating)
        surface.update(phase: .output, bands: .silence, orbitActive: true, reduceMotion: false)
        XCTAssertFalse(surface.isAnimating, "Opening a sheet must pause hidden sphere work")
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(surface.isAnimating, "Foreground resume must preserve sheet occlusion")
        surface.update(phase: .output, bands: .silence, orbitActive: false, reduceMotion: false)
        XCTAssertTrue(surface.isAnimating, "Closing the sheet resumes without changing stage")
        surface.removeFromSuperview()
        XCTAssertFalse(surface.isAnimating, "Detached surfaces consume no frames")
    }

    @MainActor func testDisplayLinkDoesNotRetainDetachedSphere() {
        weak var released: GraphiteResonanceSurface?
        autoreleasepool {
            let surface = GraphiteResonanceSurface()
            released = surface
            surface.update(phase: .idle, bands: .silence, orbitActive: false, reduceMotion: false)
        }
        XCTAssertNil(released)
    }

    func testAdaptiveFrameRatePolicy() {
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 120, lowPower: false, thermalState: .nominal), 120)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 120, lowPower: false, thermalState: .fair), 120)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 60, lowPower: false, thermalState: .nominal), 60)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 0, lowPower: false, thermalState: .nominal), 60)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 240, lowPower: false, thermalState: .nominal), 120)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 120, lowPower: true, thermalState: .nominal), 30)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 120, lowPower: false, thermalState: .serious), 30)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 60, lowPower: false, thermalState: .critical), 30)
        XCTAssertEqual(LabSphereFramePolicy.requestedRate(screenMaximum: 24, lowPower: true, thermalState: .serious), 24)
    }
}
