import Foundation
import Security

/// ElevenLabs credentials never enter source control, UserDefaults, the
/// ChatGPT OAuth keychain group, diagnostics or HTTP query parameters.
enum LabElevenKeychain {
    enum Error: LocalizedError {
        case invalid, storage
        var errorDescription: String? {
            switch self {
            case .invalid: return "Введи API-ключ ElevenLabs без пробелов."
            case .storage: return "Не удалось сохранить ключ ElevenLabs в Keychain iPhone."
            }
        }
    }

    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "org.interpreter.lab.elevenlabs",
        kSecAttrAccount as String: "elevenlabs"
    ]

    static func load() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = value as? Data,
              let key = String(data: data, encoding: .utf8) else { throw Error.storage }
        return key
    }

    static func save(_ raw: String) throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 12, key.count <= 512,
              !key.contains(where: { $0.isWhitespace }) else { throw Error.invalid }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw Error.storage }
        } else if status != errSecSuccess {
            throw Error.storage
        }
    }

    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.storage }
    }
}
