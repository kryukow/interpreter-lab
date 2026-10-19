import Foundation

/// Entries shown in the public ElevenLabs Voice Library. Searching and
/// listening to a stored preview do NOT invoke paid Text-to-Speech.
struct LabSharedVoice: Decodable, Identifiable, Hashable {
    struct Sample: Decodable, Hashable {
        let language: String?
        let previewURL: String?
        enum CodingKeys: String, CodingKey {
            case language, previewURL = "preview_url"
        }
    }

    let voiceID: String
    let publicOwnerID: String
    let name: String
    let description: String?
    let gender: String?
    let accent: String?
    let language: String?
    let previewURL: String?
    let verifiedLanguages: [Sample]?
    let freeUsersAllowed: Bool?

    var id: String { publicOwnerID + ":" + voiceID }

    enum CodingKeys: String, CodingKey {
        case voiceID = "voice_id", publicOwnerID = "public_owner_id"
        case name, description, gender, accent, language
        case previewURL = "preview_url"
        case verifiedLanguages = "verified_languages"
        case freeUsersAllowed = "free_users_allowed"
    }

    /// An exact-language recorded preview takes precedence over a general
    /// demo, which could be spoken in English even for a multilingual voice.
    func preview(for languageCode: String) -> URL? {
        let matching = verifiedLanguages?.first {
            LabVoiceLanguage.matches($0.language, languageCode) && LabVoiceLanguage.secureURL($0.previewURL) != nil
        }?.previewURL
        return LabVoiceLanguage.secureURL(matching) ?? LabVoiceLanguage.secureURL(previewURL)
    }

    func sampleIsInLanguage(_ code: String) -> Bool {
        if verifiedLanguages?.contains(where: {
            LabVoiceLanguage.matches($0.language, code) && LabVoiceLanguage.secureURL($0.previewURL) != nil
        }) == true { return true }
        // A general recording cannot be labelled as the requested language
        // merely because the voice itself supports that language.
        return verifiedLanguages?.isEmpty != false && LabVoiceLanguage.matches(language, code)
    }
}

struct LabSharedVoicePage: Decodable {
    let voices: [LabSharedVoice]
    let hasMore: Bool
    let totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case voices, hasMore = "has_more", totalCount = "total_count"
    }
}

enum LabElevenCatalogAPI {
    enum CatalogError: LocalizedError {
        case missingKey, invalidSelection, badResponse, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .missingKey: return "Сначала сохрани ключ ElevenLabs в настройках."
            case .invalidSelection: return "Недопустимый идентификатор голоса."
            case .badResponse: return "ElevenLabs вернул неожиданный ответ каталога."
            case .http(let code, let text): return "ElevenLabs HTTP \(code): \(text)"
            }
        }
    }

    static let languages: [(code: String, name: String)] = [
        ("ru", "Русский"), ("de", "Deutsch"),
        ("en", "English"), ("es", "Español"),
        ("pl", "Polski"), ("ro", "Română")
    ]

    static func browse(apiKey: String, language: String, search: String = "",
                       page: Int = 0) async throws -> LabSharedVoicePage {
        guard !apiKey.isEmpty else { throw CatalogError.missingKey }
        guard languages.contains(where: { $0.code == language }), page >= 0 else {
            throw CatalogError.invalidSelection
        }

        var components = URLComponents(string: "https://api.elevenlabs.io/v1/shared-voices")!
        var items = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "page_size", value: "30"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort", value: "trending")
        ]
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "search", value: String(trimmed.prefix(80))))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 25
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        try validate(response, data)
        return try JSONDecoder().decode(LabSharedVoicePage.self, from: data)
    }

    /// Importing a public voice requires the ElevenLabs permission Voices: Write.
    /// It is an explicit user action, never done while browsing or previewing.
    /// Some library voices are restricted by account tier/licensing.
    static func addToAccount(apiKey: String, voice: LabSharedVoice) async throws -> String {
        guard !apiKey.isEmpty else { throw CatalogError.missingKey }
        guard validPathID(voice.publicOwnerID), validPathID(voice.voiceID) else {
            throw CatalogError.invalidSelection
        }
        let url = URL(string: "https://api.elevenlabs.io/v1/voices/add/\(voice.publicOwnerID)/\(voice.voiceID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["new_name": voice.name])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        try validate(response, data)
        struct AddedVoice: Decodable {
            let voiceID: String
            enum CodingKeys: String, CodingKey { case voiceID = "voice_id" }
        }
        return try JSONDecoder().decode(AddedVoice.self, from: data).voiceID
    }

    private static func validPathID(_ value: String) -> Bool {
        !value.isEmpty && value.count < 150
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static func validate(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw CatalogError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var detail = "Проверь права API-ключа и доступность голоса для своего тарифа."
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["detail"] {
                if let dict = error as? [String: Any], let msg = dict["message"] as? String {
                    detail = msg
                } else if let msg = error as? String { detail = msg }
            }
            throw CatalogError.http(http.statusCode, String(detail.prefix(200)))
        }
    }
}


/// Provider payloads can use ISO codes, locale codes, or full language names.
enum LabVoiceLanguage {
    static func matches(_ value: String?, _ code: String) -> Bool {
        guard let value else { return false }
        let normalized = value.lowercased().replacingOccurrences(of: "_", with: "-")
        let names = ["english": "en", "spanish": "es", "polish": "pl", "russian": "ru", "german": "de", "romanian": "ro"]
        return (names[normalized] ?? String(normalized.split(separator: "-").first ?? "")) == code.lowercased()
    }
    static func secureURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}
