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
    private static let arabic: [ClosedRange<UInt32>] = [0x0600...0x06ff, 0x0750...0x077f]
    private static let cyrillic: [ClosedRange<UInt32>] = [0x0400...0x04ff]
    private static let devanagari: [ClosedRange<UInt32>] = [0x0900...0x097f]
    private static let hebrew: [ClosedRange<UInt32>] = [0x0590...0x05ff]
    private static let korean: [ClosedRange<UInt32>] = [0xac00...0xd7af, 0x1100...0x11ff]
    private static let chinese: [ClosedRange<UInt32>] = [0x3400...0x4dbf, 0x4e00...0x9fff]
    private static let japanese: [ClosedRange<UInt32>] = [0x3040...0x30ff] + chinese
    private static let greek: [ClosedRange<UInt32>] = [0x0370...0x03ff]
    private static let thai: [ClosedRange<UInt32>] = [0x0e00...0x0e7f]
    private static let ranges: [String: [ClosedRange<UInt32>]] = ["ar": arabic, "fa": arabic, "ur": arabic, "ru": cyrillic, "uk": cyrillic, "bg": cyrillic,
        "sr": cyrillic, "mk": cyrillic, "be": cyrillic, "el": greek, "hi": devanagari, "mr": devanagari, "ne": devanagari, "th": thai,
        "he": hebrew, "yi": hebrew, "ko": korean, "zh": chinese, "ja": japanese]
    private static let foreign: [ClosedRange<UInt32>] = [arabic, cyrillic, greek, devanagari, thai, hebrew, korean, japanese].flatMap { $0 }

    static func accepts(_ text: String?, language: String) -> Bool {
        guard let text, !text.isEmpty else { return false }
        let base = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: "-").first.map(String.init) ?? ""
        if base.isEmpty || base == "en" { return true }
        // Swift's regex conversion traps on the concatenated JavaScript \u ranges.
        // Scalar membership preserves Desktop's exact blocks without compiling a regex.
        let contains: ([ClosedRange<UInt32>]) -> Bool = { blocks in text.unicodeScalars.contains { scalar in blocks.contains { $0.contains(scalar.value) } } }
        if let blocks = ranges[base] { return contains(blocks) }
        return !contains(foreign)
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
