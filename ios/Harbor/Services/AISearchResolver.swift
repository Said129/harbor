import Foundation

/// A suggestion matched to a Harbor title (Desktop's `AiResult`). Episode fields are set only for series with both numbers.
struct AISearchResult: Identifiable, Equatable, Sendable {
    let media: Media
    var season: Int? = nil
    var episode: Int? = nil
    var episodeTitle: String? = nil

    var id: String {
        if let season, let episode { return "\(media.id):\(season):\(episode)" }
        return media.id
    }
}

/// Desktop's title matching (`pickBest` and `resolveAiSuggestions` in `src/lib/ai-search.ts`).
/// Desktop searches Cinemeta; here the pool comes from the caller, which searches the installed catalogs.
enum AISearchResolver {
    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") })
    }

    /// An exact title scores 5 and a title that contains the suggestion scores 3 (for 4+ characters). A matching type adds 1, and a matching year adds 1.
    /// The first candidate with the best score wins.
    static func bestMatch(_ pool: [Media], for suggestion: AISearchSuggestion) -> Media? {
        let target = normalized(suggestion.title)
        guard !target.isEmpty else { return nil }
        var best: Media?
        var bestScore = 0
        for media in pool {
            let name = normalized(media.name)
            guard !name.isEmpty else { continue }
            var nameScore = 0
            if name == target {
                nameScore = 5
            } else if target.count >= 4 && name.contains(target) {
                nameScore = 3
            }
            guard nameScore > 0 else { continue }
            var score = nameScore
            if let type = suggestion.type, media.type == type { score += 1 }
            if let year = suggestion.year, (media.releaseInfo ?? "").contains(String(year)) { score += 1 }
            if score > bestScore {
                bestScore = score
                best = media
            }
        }
        return best
    }

    static func result(for suggestion: AISearchSuggestion, in pool: [Media]) -> AISearchResult? {
        guard let media = bestMatch(pool, for: suggestion) else { return nil }
        let isEpisode = media.type == "series" && suggestion.season != nil && suggestion.episode != nil
        return AISearchResult(
            media: media,
            season: isEpisode ? suggestion.season : nil,
            episode: isEpisode ? suggestion.episode : nil,
            episodeTitle: isEpisode ? suggestion.episodeTitle : nil
        )
    }

    /// Searches every suggestion at once (as Desktop does), keeps the order, and drops repeats of the same title or episode.
    static func resolve(_ suggestions: [AISearchSuggestion], search: @escaping @Sendable (String) async throws -> [Media]) async -> [AISearchResult] {
        var resolved = [AISearchResult?](repeating: nil, count: suggestions.count)
        await withTaskGroup(of: (Int, AISearchResult?).self) { group in
            for (index, suggestion) in suggestions.enumerated() {
                group.addTask {
                    let pool = (try? await search(suggestion.title)) ?? []
                    return (index, AISearchResolver.result(for: suggestion, in: pool))
                }
            }
            for await (index, result) in group {
                resolved[index] = result
            }
        }
        var seen = Set<String>()
        var out: [AISearchResult] = []
        for case let result? in resolved where seen.insert(result.id).inserted {
            out.append(result)
        }
        return out
    }
}
