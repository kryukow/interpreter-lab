import XCTest
import SwiftUI
import UIKit
@testable import InterpreterLab

final class AuditionControlsTests: XCTestCase {
    @MainActor func testExactFreeAndExplicitPaidLanguageControlsAtPhoneWidths() async throws {
        for width in [CGFloat(320), 390] {
            for exact in [true, false] {
                let preview = LabVoicePreview()
                let voiceID = exact ? "snapshot.exact.russian.voice" : "snapshot.missing.russian.voice"
                let controls = LabVoiceAuditionControls(
                    preview: preview, voiceID: voiceID, language: "ru",
                    modelID: LabElevenModels.natural,
                    recordedURL: URL(string: "https://example.invalid/never-requested-demo.mp3"),
                    exactLanguageRecording: exact, recordedIdentity: "snapshot:" + voiceID)
                let host = UIHostingController(rootView:
                    VStack(alignment: .leading, spacing: 18) {
                        Text("ПРОБА ГОЛОСА · RU")
                            .font(.system(size: 10, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                        Text(exact ? "Есть русская запись" : "Нужна русская проба")
                            .font(.system(size: 22, weight: .medium))
                        controls.padding(18)
                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                        Spacer(minLength: 0)
                    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Color(red: 0.035, green: 0.039, blue: 0.047))
                        .foregroundStyle(.white).preferredColorScheme(.dark))
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 700))
                window.rootViewController = host
                window.makeKeyAndVisible()
                defer { window.isHidden = true; preview.stop() }
                host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 200_000_000)
                host.view.layoutIfNeeded()

                XCTAssertEqual(host.view.bounds.width, width, accuracy: 0.5)
                XCTAssertNil(preview.activeID, "Rendering controls must not play or generate audio")
                XCTAssertFalse(preview.isLoading)
                XCTAssertNil(preview.errorMessage)
                XCTAssertFalse(preview.hasGenerated(voiceID: voiceID, language: "ru", modelID: LabElevenModels.natural),
                               "The fixture must remain an ungenerated language sample")
                var drawn = false
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    drawn = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                XCTAssertTrue(drawn, "Capture the actual hosted graphite controls")
                XCTAssertNotNil(image.cgImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "Audition-\(exact ? "Exact-Free-RU" : "Missing-RU-Explicit-Paid")-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }
}
