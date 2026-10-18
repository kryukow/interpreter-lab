import Foundation

// Text-only SSE event parser. Accepts completed translation but never announces
// success before the terminal response.completed event.
struct LabResponseStream {
    enum StreamError: LocalizedError {
        case api(String)
        case incomplete(String)
        case interrupted
        case missingText
        case tooLong

        var errorDescription: String? {
            switch self {
            case .api(let message): return "OpenAI: " + message
            case .incomplete(let reason): return "Ответ не завершён: " + reason
            case .interrupted: return "Соединение оборвалось до завершения перевода. Повтори запрос."
            case .missingText: return "Модель завершила запрос, но не прислала текст перевода."
            case .tooLong: return "Ответ превышает разрешённый размер."
            }
        }
    }

    private(set) var text = ""
    private(set) var completed = false

    mutating func ingest(_ event: [String: Any]) throws {
        guard !completed else { return }
        switch event["type"] as? String {
        case "response.output_text.delta":
            if let delta = event["delta"] as? String { text += delta }
        case "response.output_text.done":
            if let final = event["text"] as? String { text = final }
        case "response.completed":
            if text.isEmpty, let response = event["response"] as? [String: Any] {
                text = Self.extractText(response)
            }
            completed = true
        case "response.failed":
            let response = event["response"] as? [String: Any] ?? [:]
            let error = response["error"] as? [String: Any] ?? [:]
            throw StreamError.api(Self.errorText(error, fallback: "Обработка запроса завершилась ошибкой."))
        case "response.incomplete":
            let response = event["response"] as? [String: Any] ?? [:]
            let details = response["incomplete_details"] as? [String: Any] ?? [:]
            throw StreamError.incomplete(details["reason"] as? String ?? "Неизвестная причина.")
        case "error":
            let error = event["error"] as? [String: Any] ?? event
            throw StreamError.api(Self.errorText(error, fallback: "Ошибка потока перевода."))
        case "response.refusal.delta", "response.refusal.done":
            throw StreamError.api("Запрос отклонён моделью.")
        default:
            break
        }
        if text.utf8.count > 200_000 { throw StreamError.tooLong }
    }

    func finish() throws -> String {
        guard completed else { throw StreamError.interrupted }
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw StreamError.missingText }
        return result
    }

    static func errorText(_ json: [String: Any], fallback: String) -> String {
        let code = json["code"] as? String ?? ""
        let param = json["param"] as? String ?? ""
        let message = json["message"] as? String ?? (json["detail"] as? String ?? fallback)
        let extras = [code.isEmpty ? nil : "код: " + code,
                      param.isEmpty ? nil : "поле: " + param].compactMap { $0 }
        return (String(message.prefix(350)) + (extras.isEmpty ? "" : " (" + extras.joined(separator: ", ") + ")"))
    }

    private static func extractText(_ json: [String: Any]) -> String {
        let output = json["output"] as? [[String: Any]] ?? []
        var parts: [String] = []
        for item in output where item["type"] as? String == "message" {
            for segment in item["content"] as? [[String: Any]] ?? []
            where segment["type"] as? String == "output_text" {
                if let part = segment["text"] as? String { parts.append(part) }
            }
        }
        return parts.joined(separator: "\n")
    }
}
