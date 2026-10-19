import Foundation

struct LabElevenVoice: Decodable, Identifiable, Hashable {
    let voiceID: String
    let name: String
    var id: String { voiceID }
    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id", name
    }
}

enum LabElevenModels {
    static let fast = "eleven_flash_v2_5"
    static let natural = "eleven_multilingual_v2"
    static let supported = [fast, natural]
}

enum LabElevenAPI {
    enum Error: LocalizedError {
        case noKey, noVoice, tooLong, badResponse, emptyAudio, invalidAudio, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "Сохрани API-ключ ElevenLabs в настройках."
            case .noVoice: return "Выбери голос ElevenLabs для языка перевода."
            case .tooLong: return "Фраза слишком длинная для выбранной TTS-модели."
            case .badResponse: return "ElevenLabs вернул неожиданный ответ."
            case .emptyAudio: return "ElevenLabs не вернул звуковой файл."
            case .invalidAudio: return "ElevenLabs вернул неподдерживаемый аудиоформат."
            case .http(let status, let reason): return "ElevenLabs HTTP \(status): \(reason)"
            }
        }
    }

    static func voices(apiKey: String) async throws -> [LabElevenVoice] {
        var all: [LabElevenVoice] = []
        var next: String?
        // Read at most three pages, enough for up to 300 user voices.
        for _ in 0..<3 {
            var components = URLComponents(string: "https://api.elevenlabs.io/v2/voices")!
            var query: [URLQueryItem] = [URLQueryItem(name: "page_size", value: "100")]
            if let next { query.append(URLQueryItem(name: "next_page_token", value: next)) }
            components.queryItems = query
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 20
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            try check(data, response)
            let page = try JSONDecoder().decode(VoicesPage.self, from: data)
            all.append(contentsOf: page.voices)
            if !page.hasMore || page.nextPageToken == nil { break }
            next = page.nextPageToken
        }
        return Array(Dictionary(grouping: all, by: \.voiceID).compactMap { $0.value.first })
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Chargeable operation. Must ONLY be triggered after choosing ElevenLabs
    /// and configuring an actual voice; replay reuses the cached file in Lab.
    static func synthesize(text: String, voiceID: String, modelID: String,
                           apiKey: String) async throws -> URL {
        guard !apiKey.isEmpty else { throw Error.noKey }
        guard !voiceID.isEmpty else { throw Error.noVoice }
        guard LabElevenModels.supported.contains(modelID) else { throw Error.badResponse }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw Error.emptyAudio }
        guard message.count <= 9_000 else { throw Error.tooLong }
        // Percent-encode the voice ID via URLComponents instead of interpolation
        // into arbitrary untrusted URLs.
        guard voiceID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
            throw Error.noVoice
        }
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        // Voice settings remain account-configured; do not impose arbitrary
        // personality or stability that could alter the approved voice.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": message, "model_id": modelID
        ])
        let (bytes, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        try check(bytes, response)
        guard bytes.count >= 500, bytes.count < 30_000_000 else { throw Error.emptyAudio }
        // MP3 begins with ID3 metadata or MPEG frame sync.
        let mp3 = (bytes.starts(with: [0x49, 0x44, 0x33]) ||
                  (bytes.count > 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0))
        guard mp3 else { throw Error.invalidAudio }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lab-eleven-\(UUID().uuidString)").appendingPathExtension("mp3")
        try bytes.write(to: url, options: [.atomic])
        return url
    }

    private struct VoicesPage: Decodable {
        let voices: [LabElevenVoice]
        let hasMore: Bool
        let nextPageToken: String?
        enum CodingKeys: String, CodingKey {
            case voices, hasMore = "has_more", nextPageToken = "next_page_token"
        }
    }

    private static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var reason = "Проверь ключ, доступ к модели и остаток кредитов."
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = object["detail"] {
                if let message = detail as? [String: Any],
                   let value = message["message"] as? String { reason = value }
                else if let value = detail as? String { reason = value }
            }
            throw Error.http(http.statusCode, String(reason.prefix(180)))
        }
    }
}
