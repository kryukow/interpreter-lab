import XCTest
@testable import InterpreterLab

final class OwnedVoiceSelectionTests: XCTestCase {
    func testSavedVoiceRemainsVisibleBeforeCatalogLoadsAndWhenCatalogDoesNotContainIt() throws {
        let suite = "OwnedVoiceSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("saved-russian", forKey: "lab.elevenVoice.ru")
        defaults.set(["saved-russian": "My saved Russian voice"], forKey: "lab.elevenVoiceNames")

        // Simulate a new presentation after a relaunch: no in-memory voices.
        let restoredID = try XCTUnwrap(defaults.string(forKey: "lab.elevenVoice.ru"))
        let unloaded = LabOwnedVoiceSelectionSummary(selection: restoredID, voices: [], defaults: defaults)
        XCTAssertEqual(unloaded.name, "My saved Russian voice")
        XCTAssertFalse(unloaded.availableInCatalog)

        // An empty response or unavailable account voice must not erase selection.
        let otherVoice = try JSONDecoder().decode(LabElevenVoice.self, from: Data(#"{"voice_id":"another","name":"Other voice"}"#.utf8))
        let missing = LabOwnedVoiceSelectionSummary(selection: restoredID, voices: [otherVoice], defaults: defaults)
        XCTAssertEqual(missing.name, unloaded.name)
        XCTAssertFalse(missing.availableInCatalog)
        XCTAssertEqual(defaults.string(forKey: "lab.elevenVoice.ru"), restoredID)

        let refreshedVoice = try JSONDecoder().decode(LabElevenVoice.self, from: Data(#"{"voice_id":"saved-russian","name":"Renamed voice"}"#.utf8))
        let loaded = LabOwnedVoiceSelectionSummary(selection: restoredID, voices: [refreshedVoice], defaults: defaults)
        XCTAssertTrue(loaded.availableInCatalog)
        XCTAssertEqual(loaded.name, "Renamed voice")
    }
}
