import XCTest
@testable import InterpreterLab

final class LabVoicePreviewTests: XCTestCase {
    @MainActor func testMissingRecordingDoesNotSelectOrPlay() {
        let preview = LabVoicePreview()
        preview.playRecorded(url: nil, id: "unavailable")
        XCTAssertNil(preview.activeID)
        XCTAssertFalse(preview.isLoading)
        XCTAssertNotNil(preview.errorMessage)
        preview.stop()
        XCTAssertNil(preview.activeID)
    }

    @MainActor func testUnavailableAppleVoiceIsReported() {
        let preview = LabVoicePreview()
        preview.playApple(voiceID: "missing.voice.identifier", language: "pl")
        XCTAssertNil(preview.activeID)
        XCTAssertNotNil(preview.errorMessage)
    }

    @MainActor func testAuditionPhrasesCoverRequestedLanguages() {
        XCTAssertTrue(LabVoicePreview.sampleText(for: "pl-PL").contains("Cześć"))
        XCTAssertTrue(LabVoicePreview.sampleText(for: "es").contains("Hola"))
        XCTAssertTrue(LabVoicePreview.sampleText(for: "en-GB").contains("Hello"))
    }
}
