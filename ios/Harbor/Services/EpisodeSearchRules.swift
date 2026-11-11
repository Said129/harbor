import Foundation

/// Desktop's episode search (`episode-search-controls.tsx`, `cross-season-results.tsx`) for the episodes the list
/// already holds: a title match, or a season and episode written as "2x5" or "S2E5". Pure.
enum EpisodeSearchRules {
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
    }

    /// True when the episode matches the query. An empty query matches every episode.
    static func matches(_ episode: Episode, query: String) -> Bool {
        let text = normalized(query)
        guard !text.isEmpty else { return true }
        if let code = coordinates(text) {
            return episode.listedSeason == code.season && episode.listedEpisode == code.episode
        }
        let title = normalized(episode.name ?? episode.title ?? "")
        return title.contains(text)
    }

    /// The season and episode numbers in "2x5", "s2e5" or "2e5" form, or nil for any other text.
    static func coordinates(_ text: String) -> (season: Int, episode: Int)? {
        guard let regex = try? NSRegularExpression(pattern: "^s?([0-9]{1,3})(?:x|e)([0-9]{1,4})$"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let seasonRange = Range(match.range(at: 1), in: text),
              let episodeRange = Range(match.range(at: 2), in: text),
              let season = Int(text[seasonRange]),
              let episode = Int(text[episodeRange]) else { return nil }
        return (season, episode)
    }
}
