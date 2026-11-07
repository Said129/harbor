import Foundation

/// Desktop's episode list display settings (`episodeLayout`, `episodeCardScale`, `episodeArcGroups`) as pure rules,
/// so the views and the tests share one definition of card sizes and story arcs.
enum EpisodeLayoutPolicy {
    /// Desktop's `episodeLayout`: the vertical list, the horizontal strip, or the grid of cards.
    enum Layout: String, CaseIterable, Sendable {
        case list, strip, grid
    }

    /// Desktop's `defaults.ts`: `episodeLayout: "list"`.
    static let defaultLayout = Layout.list
    /// Desktop's `defaults.ts`: `episodeCardScale: 1`.
    static let defaultCardScale = 1.0
    /// The card sizes Desktop offers in `library-panel/detail-tab.tsx` (Default, Large, Extra large).
    static let cardScaleChoices: [Double] = [1.0, 1.2, 1.45]
    /// Desktop's `episode-strip.tsx`: a strip card is `Math.round(244 * scale)` pixels wide.
    static let stripBaseWidth = 244.0
    /// Desktop's `episode-grid.tsx`: grid columns are at least `Math.round(232 * scale)` pixels wide.
    static let gridBaseMinimumWidth = 232.0

    /// An unknown or missing stored value shows the default layout.
    static func layout(_ raw: String?) -> Layout {
        raw.flatMap(Layout.init(rawValue:)) ?? defaultLayout
    }

    /// Desktop reads `settings.episodeCardScale || 1`, so a missing, zero, negative or non-finite scale means 1.
    static func cardScale(_ value: Double?) -> Double {
        guard let value, value.isFinite, value > 0 else { return defaultCardScale }
        return value
    }

    /// Width of one card in the horizontal strip.
    static func stripWidth(_ scale: Double?) -> Double {
        (stripBaseWidth * cardScale(scale)).rounded()
    }

    /// Smallest width of one column in the grid; the grid fits as many columns of this width as the screen allows.
    static func gridMinimumWidth(_ scale: Double?) -> Double {
        (gridBaseMinimumWidth * cardScale(scale)).rounded()
    }
}

/// One story arc of a show: a TMDB episode group entry, with its episodes as season and episode numbers.
struct EpisodeArc: Identifiable, Equatable, Sendable {
    struct Ref: Equatable, Sendable {
        let season: Int
        let episode: Int
    }
    let id: String
    let name: String
    let order: Int
    let episodes: [Ref]
}

/// Desktop's story-arc rules (`tmdb-episode-groups.ts`, `use-arc-groups.ts`). The TMDB calls live in `TMDBService`.
enum EpisodeArcPolicy {
    /// TMDB's id for a series, from a media id such as `tmdb:tv:1234`; other ids give nil.
    static func tvID(forMediaID id: String) -> Int? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "tmdb", parts[1] == "tv", let number = Int(parts[2]), number > 0 else { return nil }
        return number
    }

    /// The show's story-arc group: type 5 with the most entries. A tie keeps the group TMDB listed first.
    static func storyGroup(_ groups: JSONValue) -> (id: String, name: String)? {
        let candidates = groups["results"].array.enumerated().filter { $0.element["type"].integer == 5 }
        let best = candidates.max { lhs, rhs in
            let left = lhs.element["group_count"].integer ?? 0
            let right = rhs.element["group_count"].integer ?? 0
            return left != right ? left < right : lhs.offset > rhs.offset
        }
        guard let pick = best?.element, let id = pick["id"].string, !id.isEmpty else { return nil }
        return (id, pick["name"].string ?? "")
    }

    /// The arcs of a story-arc group in TMDB's order. Entries without a valid episode pair are dropped, and so are arcs left empty.
    static func arcs(_ detail: JSONValue) -> [EpisodeArc] {
        let indexed = detail["groups"].array.enumerated().map { (offset: $0.offset, group: $0.element) }
        let ordered = indexed.sorted { lhs, rhs in
            let left = lhs.group["order"].integer ?? 0
            let right = rhs.group["order"].integer ?? 0
            return left != right ? left < right : lhs.offset < rhs.offset
        }
        return ordered.compactMap { entry -> EpisodeArc? in
            let group = entry.group
            guard let id = group["id"].string else { return nil }
            let refs = group["episodes"].array.compactMap { item -> EpisodeArc.Ref? in
                guard let season = item["season_number"].integer, let episode = item["episode_number"].integer else { return nil }
                return EpisodeArc.Ref(season: season, episode: episode)
            }
            guard !refs.isEmpty else { return nil }
            return EpisodeArc(id: id, name: group["name"].string ?? "", order: group["order"].integer ?? 0, episodes: refs)
        }
    }

    /// The arc's episodes in arc order, matched by season and episode number. An episode the show does not list is skipped.
    static func episodes(of arc: EpisodeArc, in videos: [Episode]) -> [Episode] {
        var seen = Set<String>()
        let matched = arc.episodes.compactMap { ref in
            videos.first { $0.season == ref.season && $0.episode == ref.episode }
        }
        return matched.filter { seen.insert($0.routingKey).inserted }
    }
}
