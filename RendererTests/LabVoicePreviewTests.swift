import XCTest
@testable import InterpreterLab

final class LabVoicePreviewTests: XCTestCase {
    @MainActor func testSuccessfulGenerationIsNotRepeatedAfterPlaybackFailure() async throws {
        let preview = LabVoicePreview()
        let voice = "test-" + UUID().uuidString
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(voice)
        let target = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceAuditions")
            .appendingPathComponent(LabVoicePreview.generatedCacheName(voiceID: voice, language: "ru", modelID: LabElevenModels.fast))
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        // Deliberately undecodable audio models playback failure after the paid
        // response has arrived. Replaying must reuse it, never bill a second time.
        try Data([1, 2, 3]).write(to: source)
        var requests = 0
        preview.generateSample = { text, _, _ in
            requests += 1
            XCTAssertEqual(text, LabVoicePreview.sampleText(for: "ru"))
            return source
        }
        for _ in 0..<2 {
            preview.playGenerated(voiceID: voice, language: "ru", modelID: LabElevenModels.fast)
            for _ in 0..<50 {
                if !preview.isLoading { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertFalse(preview.isLoading)
            XCTAssertNotNil(preview.errorMessage)
        }
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(preview.hasGenerated(voiceID: voice, language: "ru", modelID: LabElevenModels.fast))
    }

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

    @MainActor func testGeneratedCacheSeparatesVoiceLanguageAndModel() {
        let base = LabVoicePreview.generatedCacheName(voiceID: "one", language: "ru", modelID: "fast")
        XCTAssertEqual(base, LabVoicePreview.generatedCacheName(voiceID: "one", language: "ru", modelID: "fast"))
        XCTAssertNotEqual(base, LabVoicePreview.generatedCacheName(voiceID: "one", language: "de", modelID: "fast"))
        XCTAssertNotEqual(base, LabVoicePreview.generatedCacheName(voiceID: "two", language: "ru", modelID: "fast"))
        XCTAssertNotEqual(base, LabVoicePreview.generatedCacheName(voiceID: "one", language: "ru", modelID: "natural"))
        XCTAssertEqual(base.count, 68)
    }
}
