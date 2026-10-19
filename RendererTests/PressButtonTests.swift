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
