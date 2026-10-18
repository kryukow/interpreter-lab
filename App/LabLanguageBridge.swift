import Foundation

// Adapter only. The PartnerLanguage model is copied unchanged from Live 1.4.23.
// Keep recognition, translation and playback specific to Interpreter Lab.
extension PartnerLanguage {
    var speechLocale: String {
        switch self {
        case .de: return "de-DE"
        case .en: return "en-GB"
        case .es: return "es-ES"
        case .ro: return "ro-RO"
        case .pl: return "pl-PL"
        }
    }

    var englishLanguageName: String {
        switch self {
        case .de: return "German"
        case .en: return "English"
        case .es: return "Spanish"
        case .ro: return "Romanian"
        case .pl: return "Polish"
        }
    }

    static func sourceName(_ code: String) -> String {
        if code == "ru" { return "Russian" }
        return PartnerLanguage.current(code).englishLanguageName
    }

    static func voiceLocale(for code: String) -> String {
        code == "ru" ? "ru-RU" : PartnerLanguage.current(code).speechLocale
    }
}
