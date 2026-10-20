import Foundation

/// A season changes the hero presentation, never the media used for playback or progress.
struct AnimeSeasonArtwork: Hashable, Sendable {
    let entryID: String
    let background: String
    let logo: String?
    let description: String?

    static func entry(from start: String?, year: String? = nil, franchise: [AnimeFranchiseEntry], anchorID: String) -> AnimeFranchiseEntry? {
        guard franchise.count > 1, let seasonStart = time(start) ?? time(year) else { return nil }
        let sideFormats: Set<String> = ["ova", "ona", "special", "music", "movie"]
        var nearest: AnimeFranchiseEntry?, distance = TimeInterval.infinity
        for entry in franchise {
            guard !entry.current, !sideFormats.contains(entry.subtype?.lowercased() ?? ""),
                  entry.media.background?.isEmpty == false,
                  let date = time(entry.startDate) ?? (entry.year > 0 ? time(String(entry.year)) : nil) else { continue }
            let delta = abs(date.timeIntervalSince(seasonStart))
            if delta < distance { nearest = entry; distance = delta }
        }
        guard distance <= 150 * 86_400, nearest?.id != anchorID else { return nil }
        return nearest
    }

    static func presentation(_ entry: AnimeFranchiseEntry, root: Media, episodes: [Episode], language: String) -> Self? {
        guard let background = entry.media.background, !background.isEmpty else { return nil }
        let details = root.details
        let base = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: "-").first.map(String.init) ?? ""
        let supplied = details?.overviewLanguage?.lowercased().split(separator: "-").first.map(String.init)
        let localized = !base.isEmpty && base != "en" && supplied == base
        var counts: [Int: Int] = [:], order: [Int] = []
        for episode in episodes where episode.sourceMetaID == entry.id {
            guard let season = episode.imdbSeason else { continue }
            if counts[season] == nil { order.append(season) }
            counts[season, default: 0] += 1
        }
        var best: Int?, bestCount = 0
        for season in order where (counts[season] ?? 0) > bestCount { best = season; bestCount = counts[season] ?? 0 }
        let seasonOverview = localized ? best.flatMap { details?.seasonOverviews?[$0] } : nil
        let overview = localized ? details?.localizedOverview : nil
        return Self(entryID: entry.id, background: background, logo: entry.media.logo,
            description: seasonOverview ?? overview ?? entry.media.description)
    }

    private static func time(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = value.count == 4 ? value + "-06-30" : value.count == 7 ? value + "-01" : value
        return ISO8601DateParser.shared.date(iso) ?? ISO8601DateParser.shared.date(iso + "T00:00:00Z")
    }
}

/// The same script guard as Desktop's anime-episode-build.ts; it rejects untranslated fallbacks.
enum LocalizedMetadataText {
    static func accepts(_ text: String?, language: String) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let base = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: "-").first.map(String.init) ?? ""
        if base.isEmpty || base == "en" { return true }
        let arabic = #"[\u0600-\u06FF\u0750-\u077F]"#, cyrillic = #"[\u0400-\u04FF]"#
        let devanagari = #"[\u0900-\u097F]"#, hebrew = #"[\u0590-\u05FF]"#, korean = #"[\uAC00-\uD7AF\u1100-\u11FF]"#
        let ranges = ["ar": arabic, "fa": arabic, "ur": arabic, "ru": cyrillic, "uk": cyrillic, "bg": cyrillic, "sr": cyrillic, "mk": cyrillic, "be": cyrillic,
            "el": #"[\u0370-\u03FF]"#, "hi": devanagari, "mr": devanagari, "ne": devanagari, "th": #"[\u0E00-\u0E7F]"#,
            "he": hebrew, "yi": hebrew, "ko": korean, "zh": #"[\u3400-\u4DBF\u4E00-\u9FFF]"#, "ja": #"[\u3040-\u30FF\u3400-\u4DBF\u4E00-\u9FFF]"#]
        if let range = ranges[base] { return text.range(of: range, options: .regularExpression) != nil }
        let foreign = #"[\u0600-\u06FF\u0750-\u077F\u0400-\u04FF\u0370-\u03FF\u0900-\u097F\u0E00-\u0E7F\u0590-\u05FF\uAC00-\uD7AF\u1100-\u11FF\u3400-\u4DBF\u4E00-\u9FFF\u3040-\u30FF]"#
        return text.range(of: foreign, options: .regularExpression) == nil
    }
    static func apply(_ response: JSONValue, language: String, to details: inout MediaDetails) {
        details.overviewLanguage = language
        details.localizedOverview = accepts(response["overview"].string, language: language) ? response["overview"].string : nil
        var seasons: [Int: String] = [:]
        for season in response["seasons"].array {
            guard let number = season["season_number"].integer, let text = season["overview"].string, accepts(text, language: language) else { continue }
            seasons[number] = text
        }
        details.seasonOverviews = seasons
    }
}
