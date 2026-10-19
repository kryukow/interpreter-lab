import XCTest
import SwiftUI
import UIKit
@testable import InterpreterLab

@MainActor private final class TranscriptFixture: ObservableObject {
    @Published var text = ""
    @Published var follow = true
}

private struct TranscriptHarness: View {
    @ObservedObject var fixture: TranscriptFixture
    var body: some View {
        LabLiveTextView(text: $fixture.text, followTail: $fixture.follow, editable: false)
            .frame(height: 132)
    }
}

final class TranscriptConsoleTests: XCTestCase {
    @MainActor private func settle() async throws {
        try await Task.sleep(nanoseconds: 450_000_000)
    }

    @MainActor private func findTextView(in view: UIView) -> UITextView? {
        if let text = view as? UITextView { return text }
        return view.subviews.lazy.compactMap { findTextView(in: $0) }.first
    }

    @MainActor func testLiveUnicodeTailManualScrollAndResume() async throws {
        let fixture = TranscriptFixture()
        let host = UIHostingController(rootView: TranscriptHarness(fixture: fixture))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await settle()
        let text = try XCTUnwrap(findTextView(in: host.view))
        fixture.text = (1...45).map { "\($0) Распознаётся речь 👩🏽‍🚀 — español, język polski." }.joined(separator: "\n")
        try await settle()
        XCTAssertEqual(text.text, fixture.text)
        XCTAssertGreaterThan(text.contentSize.height, text.bounds.height * 3)
        XCTAssertGreaterThanOrEqual(text.contentOffset.y + text.bounds.height,
                                    text.contentSize.height - 32, "Newest words stay visible")
        text.delegate?.scrollViewWillBeginDragging?(text)
        text.setContentOffset(.zero, animated: false)
        try await settle()
        XCTAssertFalse(fixture.follow)
        fixture.text += "\nНовые слова остаются внизу 🌌"
        try await settle()
        XCTAssertLessThan(text.contentOffset.y, 2, "Reading older words must not jump down")
        fixture.follow = true
        try await settle()
        XCTAssertGreaterThanOrEqual(text.contentOffset.y + text.bounds.height,
                                    text.contentSize.height - 32, "Resume follows without a text revision")
        XCTAssertFalse(text.isEditable)
        XCTAssertEqual(text.accessibilityLabel, "Распознанный текст")
        attach(host.view, name: "Transcript-Unicode-Tail-320")
    }

    @MainActor func testSettingsAndTranscriptPhoneSnapshots() async throws {
        let model = LabSession()
        model.source = "Распознавание сохраняет живой текст. English · Español · Polski 👩🏽‍🚀"
        for width in [CGFloat(320), 390, 430] {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 844))
            let console = UIHostingController(rootView: LabTranscriptConsole(model: model).padding().preferredColorScheme(.dark))
            window.rootViewController = console
            window.makeKeyAndVisible()
            console.view.layoutIfNeeded()
            try await settle()
            attach(console.view, name: "Transcript-\(Int(width))")
            let settings = UIHostingController(rootView: LabSettings(model: model).preferredColorScheme(.dark))
            window.rootViewController = settings
            settings.view.layoutIfNeeded()
            try await settle()
            attach(settings.view, name: "Settings-\(Int(width))")
            window.isHidden = true
        }
    }

    @MainActor func testCompleteInterpreterPhoneSnapshots() async throws {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844)] {
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            let host = UIHostingController(rootView: LabView().preferredColorScheme(.dark))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await settle()
            // Capture the entire real screen, including its fixed recording dock.
            XCTAssertEqual(host.view.bounds.size, size)
            attach(host.view, name: "Interpreter-FullScreen-\(Int(size.width))x\(Int(size.height))")
            window.isHidden = true
        }
    }

    @MainActor private func attach(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
