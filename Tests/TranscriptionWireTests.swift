import Foundation

@main struct TranscriptionWireTests {
    static func main() throws {
        let audio = Data([0, 1, 2, 255])
        for mode in TranscriptionMode.allCases {
            for hint in TranscriptionLanguageHint.allCases {
                let request = try TranscriptionWire.request(file: audio, filename: "clip.m4a", key: "fixture", mode: mode, boundary: "fixture-boundary", hint: hint)
                precondition(request.httpMethod == "POST")
                precondition(request.url?.path == "/v1/audio/transcriptions")
                precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
                let body = String(decoding: request.httpBody!, as: UTF8.self)
                precondition(body.contains(mode.model))
                precondition(body.hasSuffix("\r\n--fixture-boundary--\r\n"))
                if mode == .single {
                    precondition(!body.contains("diarized_json"))
                    for language in hint.languages {
                        precondition(body.contains("name=\"languages[]\"\r\n\r\n" + language))
                    }
                } else {
                    precondition(body.contains("diarized_json") && body.contains("chunking_strategy"))
                    precondition(!body.contains("languages[]"))
                    precondition(body.contains("name=\"language\"") == (hint.languages.count == 1))
                }
            }
        }
        let sanitized = try TranscriptionWire.request(file: audio, filename: "bad\"\r\n.m4a", key: "fixture", mode: .single, boundary: "test")
        precondition(String(decoding: sanitized.httpBody!, as: UTF8.self).contains("filename=\"bad___.m4a\""))
        do { _ = try TranscriptionWire.request(file: Data(), filename: "x", key: "x", mode: .single, boundary: "x"); preconditionFailure() }
        catch TranscriptWireError.emptyFile { }
        do { _ = try TranscriptionWire.request(file: Data(count: TranscriptionWire.maxBytes + 1), filename: "x", key: "x", mode: .single, boundary: "x"); preconditionFailure() }
        catch TranscriptWireError.fileTooLarge { }
        precondition(TranscriptionWire.expectedChunks(durationSeconds: 180) == 1)
        precondition(TranscriptionWire.expectedChunks(durationSeconds: 181) == 2)
        precondition(TranscriptionWire.expectedChunks(durationSeconds: .nan) == 0)
        precondition(abs(TranscriptionMode.single.price(for: 120) - 0.009) < 0.000001)
        precondition(abs(TranscriptionMode.group.price(for: 120) - 0.012) < 0.000001)
        let single = try TranscriptionWire.parse(Data(#"{"text":"Hallo","languages":[{"code":"de"}]}"#.utf8), mode: .single)
        precondition(single.text == "Hallo" && single.languages == ["de"])
        let group = try TranscriptionWire.parse(Data(#"{"text":"Hallo","segments":[{"speaker":"A","start":2.5,"end":3.2,"text":"Hallo"}]}"#.utf8), mode: .group)
        precondition(group.formatted(mode: .group, partNumber: 2, showPart: true, offsetSeconds: 180) == "Часть 2\n[03:02] A: Hallo")
        for payload in [#"{"text":""}"#, #"{"text":"x","segments":[{"text":"x"}]}"#] {
            do { _ = try TranscriptionWire.parse(Data(payload.utf8), mode: .group); preconditionFailure() }
            catch { }
        }
        if case .invalidKey = TranscriptionWire.serverError(Data(#"{"error":{"code":"invalid_api_key"}}"#.utf8), status: 401) {} else { preconditionFailure() }
        if case .quota = TranscriptionWire.serverError(Data(#"{"error":{"code":"insufficient_quota"}}"#.utf8), status: 429) {} else { preconditionFailure() }
        print("Transcription: both modes, all language hints, multipart, limits, cost, parser and absolute timestamps passed")
    }
}
