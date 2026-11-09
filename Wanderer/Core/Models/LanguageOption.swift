import SwiftUI

struct LanguageOption: Identifiable, Hashable {
    let id: String
    let nativeName: String
    let englishName: String

    static let all: [LanguageOption] = [
        .init(id: "en", nativeName: "English", englishName: "English"),
        .init(id: "id", nativeName: "Bahasa Indonesia", englishName: "Indonesian"),
        .init(id: "ms", nativeName: "Bahasa Melayu", englishName: "Malay"),
        .init(id: "da", nativeName: "Dansk", englishName: "Danish"),
        .init(id: "de", nativeName: "Deutsch", englishName: "German"),
        .init(id: "es", nativeName: "Español", englishName: "Spanish"),
        .init(id: "fr", nativeName: "Français", englishName: "French"),
        .init(id: "it", nativeName: "Italiano", englishName: "Italian"),
        .init(id: "nl", nativeName: "Nederlands", englishName: "Dutch"),
        .init(id: "no", nativeName: "Norsk", englishName: "Norwegian"),
        .init(id: "pl", nativeName: "Polski", englishName: "Polish"),
        .init(id: "pt", nativeName: "Português", englishName: "Portuguese"),
        .init(id: "ro", nativeName: "Română", englishName: "Romanian"),
        .init(id: "fi", nativeName: "Suomi", englishName: "Finnish"),
        .init(id: "sv", nativeName: "Svenska", englishName: "Swedish"),
        .init(id: "tl", nativeName: "Tagalog", englishName: "Tagalog"),
        .init(id: "vi", nativeName: "Tiếng Việt", englishName: "Vietnamese"),
        .init(id: "tr", nativeName: "Türkçe", englishName: "Turkish"),
        .init(id: "el", nativeName: "Ελληνικά", englishName: "Greek"),
        .init(id: "ru", nativeName: "Русский", englishName: "Russian"),
        .init(id: "he", nativeName: "עברית", englishName: "Hebrew"),
        .init(id: "ar", nativeName: "العربية", englishName: "Arabic"),
        .init(id: "ja", nativeName: "日本語", englishName: "Japanese"),
        .init(id: "ko", nativeName: "한국어", englishName: "Korean"),
        .init(id: "zh-Hans", nativeName: "中文 (简体)", englishName: "Chinese (Simplified)"),
        .init(id: "zh-Hant", nativeName: "中文 (繁體)", englishName: "Chinese (Traditional)"),
        .init(id: "th", nativeName: "ไทย", englishName: "Thai"),
        .init(id: "hi", nativeName: "हिन्दी", englishName: "Hindi")
    ]

    static var deviceDefault: LanguageOption {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return all.first(where: { $0.id == code || $0.id.hasPrefix(code) }) ?? all[0]
    }

    static func named(_ id: String) -> LanguageOption {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}
