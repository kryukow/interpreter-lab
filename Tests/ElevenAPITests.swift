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
        print("ElevenLabs TTS models, voice decoder and error messages passed")
    }
}
