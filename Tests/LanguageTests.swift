import Foundation

@main
struct LabLanguageTests {
    static func main() {
        let languages = PartnerLanguage.allCases
        assert(languages.count == 5)
        let expected: [(String, String, String)] = [
            ("de", "de-DE", "German"),
            ("en", "en-GB", "English"),
            ("es", "es-ES", "Spanish"),
            ("ro", "ro-RO", "Romanian"),
            ("pl", "pl-PL", "Polish")
        ]
        for (code, locale, name) in expected {
            let partner = PartnerLanguage.current(code)
            assert(partner.rawValue == code)
            assert(partner.speechLocale == locale)
            assert(partner.englishLanguageName == name)
            assert(PartnerLanguage.sourceName(code) == name)
            assert(PartnerLanguage.voiceLocale(for: code) == locale)
            assert(partner.outputCode(whenSourceIsRussian: true) == code)
            assert(partner.outputCode(whenSourceIsRussian: false) == "ru")
        }
        assert(PartnerLanguage.sourceName("ru") == "Russian")
        assert(PartnerLanguage.voiceLocale(for: "ru") == "ru-RU")
        assert(PartnerLanguage.current("invalid") == .de)
        // Same circular geometry as the Live orbit: five positions -2...2.
        for center in 0..<languages.count {
            let distances = languages.indices.map { index -> Int in
                let d = (index - center + languages.count) % languages.count
                return d <= languages.count / 2 ? d : d - languages.count
            }
            assert(Set(distances) == Set([-2, -1, 0, 1, 2]))
        }
        print("Live partner-language bindings: five bidirectional directions, five locales, orbit passed")
    }
}
