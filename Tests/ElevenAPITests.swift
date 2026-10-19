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
        precondition(LabElevenCatalogAPI.CatalogError.http(401, "denied").errorDescription == "ElevenLabs HTTP 401: denied")
        print("ElevenLabs language catalog, secure recorded previews, legacy decoding and errors passed")
    }
}
