import Foundation

/// Desktop's "Translate overviews" (`translateDescriptions`, `tmdb-details.ts`): with it off, the plot text and the tagline stay
/// English even when the metadata language is another one. The localized text is the fallback when TMDB has no English text.
enum OverviewTranslationPolicy {
    /// An empty language is Desktop's "English (default)".
    static func isEnglish(_ language: String) -> Bool {
        let base = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: "-").first.map(String.init) ?? ""
        return base.isEmpty || base == "en"
    }

    /// Whether the page has to ask TMDB for the English record on top of the localized one.
    static func needsEnglish(translate: Bool, language: String) -> Bool {
        !translate && !isEnglish(language)
    }

    /// English when the setting is off and TMDB has some, the localized text otherwise.
    static func text(localized: String?, english: String?, translate: Bool) -> String? {
        if translate { return localized }
        guard let english, !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return localized }
        return english
    }
}
