import XCTest
import UIKit
@testable import InterpreterLab

final class PressButtonTests: XCTestCase {
    @MainActor func testNativeHoldFinishesOnceIncludingReleaseOutside() {
        var begins = 0
        var ends = 0
        var cancels = 0
        let parent = PressButton(title: "Polski", subtitle: "Перевод на русский", pressed: false,
                                 enabled: true, begin: { begins += 1 }, end: { ends += 1 },
                                 cancel: { cancels += 1 })
        let coordinator = parent.makeCoordinator()
        let button = GraphitePressControl(frame: CGRect(x: 0, y: 0, width: 160, height: 76))
        coordinator.connect(button)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchDown)
        XCTAssertTrue(button.illuminated, "Finger feedback must precede speech arming")
        XCTAssertEqual(begins, 1)
        button.sendActions(for: .touchUpOutside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(ends, 1)
        XCTAssertEqual(cancels, 0)
        XCTAssertFalse(button.illuminated)
    }

    @MainActor func testBackgroundCancelsHoldWithoutSendingTranslation() {
        var ends = 0
        var cancels = 0
        let parent = PressButton(title: "Русский", subtitle: "Polski", pressed: false,
                                 enabled: true, begin: {}, end: { ends += 1 },
                                 cancel: { cancels += 1 })
        let coordinator = parent.makeCoordinator()
        let button = GraphitePressControl(frame: .zero)
        coordinator.connect(button)
        button.sendActions(for: .touchDown)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(ends, 0)
        XCTAssertFalse(button.touchHeld)
    }

    @MainActor func testMaterialAndAccessibleDescriptionUseSingleHorizontalLabel() {
        let button = GraphitePressControl(frame: CGRect(x: 0, y: 0, width: 160, height: 76))
        button.configure(title: "Español", subtitle: "Перевод на русский", pressed: false)
        button.layoutIfNeeded()
        XCTAssertTrue(button.isExclusiveTouch)
        XCTAssertEqual(button.layer.cornerRadius, 22)
        XCTAssertEqual(button.configuration?.imagePlacement, .leading)
        XCTAssertNil(button.configuration?.subtitle)
        XCTAssertEqual(button.configuration?.title, "Español")
        XCTAssertTrue(button.accessibilityLabel?.contains("Перевод на русский") == true)
        button.configure(title: "Español", subtitle: "Русский", pressed: true)
        XCTAssertTrue(button.illuminated, "Recognition can sustain the held material")
    }

    @MainActor func testConfiguredButtonRendersMicAndTitleAboveMaterial() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let button = GraphitePressControl(frame: CGRect(x: 20, y: 20, width: 160, height: 76))
        host.view.addSubview(button)
        button.configure(title: "Polski", subtitle: "Русский", pressed: false)
        host.view.layoutIfNeeded()
        button.layoutIfNeeded()
        let decorations = try XCTUnwrap(button.layer.sublayers?.filter { $0 is CAGradientLayer })
        XCTAssertEqual(decorations.count, 2)
        for decoration in decorations {
            XCTAssertLessThan(decoration.zPosition, 0)
            for content in button.subviews {
                XCTAssertLessThan(decoration.zPosition, content.layer.zPosition,
                                  "Material must stay beneath lazily inserted UIKit content")
            }
        }
        XCTAssertEqual(button.layer.cornerRadius, 22)
        XCTAssertNotNil(button.titleLabel?.text)
        XCTAssertNotNil(button.imageView?.image)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let snapshot = UIGraphicsImageRenderer(size: button.bounds.size, format: format).image { context in
            button.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: snapshot)
        attachment.name = "Graphite recording button — visible mic and label"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The centre of an empty graphite button has no silver pixels. This
        // catches opaque decoration layers covering otherwise configured text.
        let image = try XCTUnwrap(snapshot.cgImage)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let silverCount: Int = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let data = bytes.bindMemory(to: UInt8.self)
            var count = 0
            for y in 20..<(height - 20) {
                for x in 20..<(width - 20) {
                    let offset = (y * width + x) * 4
                    if data[offset] > 160 && data[offset + 1] > 160 && data[offset + 2] > 160 {
                        count += 1
                    }
                }
            }
            return count
        }
        XCTAssertGreaterThan(silverCount, 50, "Mic and title must be visible in the rendered button")
    }

    @MainActor func testDismantlingCancelsExactlyOnce() {
        var cancels = 0
        let parent = PressButton(title: "English", subtitle: "Русский", pressed: false,
                                 enabled: true, begin: {}, end: {}, cancel: { cancels += 1 })
        let coordinator = parent.makeCoordinator()
        let button = GraphitePressControl(frame: .zero)
        coordinator.connect(button)
        button.sendActions(for: .touchDown)
        PressButton.dismantleUIView(button, coordinator: coordinator)
        coordinator.abort()
        XCTAssertEqual(cancels, 1)
        XCTAssertFalse(button.touchHeld)
    }
}

