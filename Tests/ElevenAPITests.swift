import Foundation

@main
struct ElevenAPITests {
    static func main() throws {
        precondition(LabElevenModels.supported == [
            "eleven_flash_v2_5", "eleven_multilingual_v2"
        ])
        let encoded = Data(#"{"voice_id":"abcd_123","name":"Russian voice"}"#.utf8)
        let decoded = try JSONDecoder().decode(LabElevenVoice.self, from: encoded)
        precondition(decoded.voiceID == "abcd_123")
        precondition(decoded.name == "Russian voice")
        precondition(decoded.id == "abcd_123")
        precondition(String(describing: LabElevenAPI.Error.noVoice.errorDescription!).contains("голос"))
        let fixture = Data(#"{"voice_id":"voice","public_owner_id":"owner","name":"Demo","language":"pl","preview_url":"https://example.com/general.mp3","verified_languages":[{"language":"en-US","preview_url":"https://example.com/en.mp3"},{"language":"polish","preview_url":"https://example.com/pl.mp3"}]}"#.utf8)
        let shared = try JSONDecoder().decode(LabSharedVoice.self, from: fixture)
        precondition(shared.preview(for: "pl")?.lastPathComponent == "pl.mp3")
        precondition(shared.preview(for: "en")?.lastPathComponent == "en.mp3")
        precondition(shared.preview(for: "es")?.lastPathComponent == "general.mp3")
        precondition(shared.sampleIsInLanguage("pl"))
        precondition(!shared.sampleIsInLanguage("es"))
        precondition(LabVoiceLanguage.secureURL("http://example.com/a.mp3") == nil)
        precondition(LabVoiceLanguage.secureURL("https://key:secret@example.com/a.mp3") == nil)
        precondition(LabElevenCatalogAPI.languages.map(\.code).contains("pl"))
        precondition(LabElevenCatalogAPI.languages.map(\.code).contains("en"))
        precondition(LabElevenCatalogAPI.languages.map(\.code).contains("es"))
        let owned = try JSONDecoder().decode(LabElevenVoice.self, from: fixture)
        precondition(owned.preview(for: "pl")?.lastPathComponent == "pl.mp3")
        precondition(decoded.preview(for: "en") == nil)
        let nativeOnly = Data(#"{"voice_id":"russian","public_owner_id":"owner","name":"Russian","language":"ru","labels":{"language":"ru"},"preview_url":"https://example.com/unknown.mp3"}"#.utf8)
        let nativeShared = try JSONDecoder().decode(LabSharedVoice.self, from: nativeOnly)
        let nativeOwned = try JSONDecoder().decode(LabElevenVoice.self, from: nativeOnly)
        precondition(!nativeShared.sampleIsInLanguage("ru"))
        precondition(!nativeOwned.sampleIsInLanguage("ru"))
        precondition(LabElevenCatalogAPI.CatalogError.http(401, "denied").errorDescription == "ElevenLabs HTTP 401: denied")
        let permissionError = LabElevenCatalogAPI.CatalogError.http(401, "The API key you used is missing the permission voices_write to execute this operation.").errorDescription!
        precondition(permissionError.contains("Voices → Write"))
        precondition(permissionError.contains("Предыдущий выбор сохранён"))
        precondition(!LabElevenCatalogAPI.CatalogError.http(500, "voices_write").errorDescription!.contains("отключено"))
        print("ElevenLabs language catalog, secure recorded previews, legacy decoding and errors passed")
    }
}
