import XCTest
import AVFoundation
@testable import InterpreterLab

final class OpenAISpeechTests: XCTestCase {
    func testRealtimeRequestReadsOnlyProvidedTextWithChosenVoice() throws {
        let request = try LabOpenAISpeech.request(apiKey: "test-placeholder", modelID: LabOpenAISpeech.model)
        XCTAssertEqual(request.url?.scheme, "wss")
        XCTAssertEqual(request.url?.host, "api.openai.com")
        XCTAssertEqual(request.url?.path, "/v1/realtime")
        XCTAssertTrue(request.url?.query?.contains("gpt-realtime-2.1") == true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-placeholder")
        let text = "Привет 👩🏽‍🚀 · Guten Tag"
        let event = try XCTUnwrap(JSONSerialization.jsonObject(with: LabOpenAISpeech.responseEvent(text: text, voice: "marin")) as? [String: Any])
        XCTAssertEqual(event["type"] as? String, "response.create")
        let response = try XCTUnwrap(event["response"] as? [String: Any])
        XCTAssertEqual(response["conversation"] as? String, "none")
        XCTAssertEqual(response["output_modalities"] as? [String], ["audio"])
        XCTAssertEqual((response["tools"] as? [Any])?.count, 0)
        let item = try XCTUnwrap((response["input"] as? [[String: Any]])?.first)
        XCTAssertEqual((item["content"] as? [[String: String]])?.first?["text"], text)
        XCTAssertThrowsError(try LabOpenAISpeech.responseEvent(text: "", voice: "marin"))
        XCTAssertThrowsError(try LabOpenAISpeech.responseEvent(text: text, voice: "unsupported"))
        XCTAssertThrowsError(try LabOpenAISpeech.request(apiKey: ""))
        XCTAssertThrowsError(try LabOpenAISpeech.request(apiKey: "placeholder", modelID: "old-model"))
    }

    func testAudioCollectorRejectsIncompleteOrMalformedResponsesAndWritesPlayableWAV() throws {
        var collector = LabOpenAISpeech.AudioCollector()
        let pcm = Data(repeating: 0, count: 4800)
        XCTAssertFalse(try collector.append(["type": "response.output_audio.delta", "delta": pcm.base64EncodedString()]))
        XCTAssertTrue(try collector.append(["type": "response.done", "response": ["status": "completed"]]))
        XCTAssertEqual(collector.pcm, pcm)
        let wav = LabOpenAISpeech.wav(collector.pcm)
        XCTAssertEqual(wav.count, pcm.count + 44)
        XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
        let player = try AVAudioPlayer(data: wav)
        XCTAssertEqual(player.duration, 0.1, accuracy: 0.001)
        XCTAssertThrowsError(try collector.append(["type": "response.done", "response": ["status": "incomplete"]]))
        XCTAssertThrowsError(try collector.append(["type": "response.output_audio.delta", "delta": "not base64!"]))
        XCTAssertThrowsError(try collector.append(["type": "error", "error": ["message": "Access denied"]]))
        var empty = LabOpenAISpeech.AudioCollector()
        XCTAssertThrowsError(try empty.append(["type": "response.done", "response": ["status": "completed"]]))
    }
}
