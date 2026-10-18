import Foundation
import Security

enum LabKeychain {
    enum KeyError: LocalizedError {
        case invalid, storage
        var errorDescription: String? {
            switch self {
            case .invalid: return "Вставь действительный API-ключ OpenAI без пробелов."
            case .storage: return "Не удалось обратиться к Keychain iPhone."
            }
        }
    }

    // Separate from Interpreter and Interpreter Live.
    private static let service = "org.interpreter.lab.api-key"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "openai"]
    }

    static func load() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = value as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeyError.storage }
        return key
    }

    static func save(_ input: String) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20,
              !key.contains(where: { $0.isWhitespace }) else { throw KeyError.invalid }
        let bytes = Data(key.utf8)
        let updated = SecItemUpdate(query as CFDictionary,
                                    [kSecValueData as String: bytes] as CFDictionary)
        if updated == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = bytes
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw KeyError.storage }
        } else if updated != errSecSuccess {
            throw KeyError.storage
        }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeyError.storage }
    }
}
