import XCTest
import SwiftUI
import UIKit
@testable import InterpreterLab

final class SelectionSheetTests: XCTestCase {
    @MainActor func testGraphiteSheetSnapshotsAtPhoneWidths() async throws {
        for width in [CGFloat(320), 390] {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 680))
            let host = UIHostingController(rootView: LabGraphiteSelectionSheet(
                title: "Способ перевода", selection: .constant("chatgpt"),
                choices: [
                    LabGraphiteChoice(id: "chatgpt", title: "Подписка ChatGPT", detail: "Лимиты твоей подписки"),
                    LabGraphiteChoice(id: "api", title: "Платный API", detail: "Отдельный ключ OpenAI")
                ]).preferredColorScheme(.dark))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 450_000_000)
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Graphite-Selection-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }
}
