import Foundation

/// Desktop's anime picks rules: which titles the Anime page's hero and Top Picks may show
/// (`lib/anime-filter.ts`, `views/anime.tsx`) and which genres seed the picks (`lib/anime-top-picks-utils.ts`).
/// Pure value logic. The Anime page applies it; nothing here reads the network or the Keychain.
enum AnimePicksPolicy {
    struct Options: Equatable, Sendable {
        /// Desktop's `animeFavoriteGenres`: Jikan genre ids, used to seed the genre rows.
        var favoriteGenres: [Int]
        /// Desktop's `animeExcludeOrigins`: ISO country codes whose titles are hidden.
        var excludeOrigins: [String]
        /// Desktop's `animeHideWatchedPicks`.
        var hideWatched: Bool

        /// Desktop's `defaults.ts`: no favourite genres, Chinese donghua hidden, watched titles hidden.
        static let desktopDefault = Options(favoriteGenres: [], excludeOrigins: ["CN"], hideWatched: true)
    }

    struct Genre: Equatable, Sendable {
        let id: Int
        let label: String
    }

    struct Origin: Equatable, Sendable {
        let code: String
        let label: String
    }

    /// Desktop's `ANIME_GENRE_OPTIONS` (`components/anime-genre-picker.tsx`) with the Jikan ids of `ANIME_GENRE_TO_JIKAN`.
    static let genres: [Genre] = [
        Genre(id: 1, label: "Action"), Genre(id: 2, label: "Adventure"), Genre(id: 4, label: "Comedy"),
        Genre(id: 8, label: "Drama"), Genre(id: 10, label: "Fantasy"), Genre(id: 24, label: "Sci-Fi"),
        Genre(id: 22, label: "Romance"), Genre(id: 36, label: "Slice of Life"), Genre(id: 37, label: "Supernatural"),
        Genre(id: 7, label: "Mystery"), Genre(id: 40, label: "Psychological"), Genre(id: 14, label: "Horror"),
        Genre(id: 41, label: "Thriller"), Genre(id: 18, label: "Mecha"), Genre(id: 30, label: "Sports"),
        Genre(id: 19, label: "Music")
    ]

    /// Desktop's `ORIGIN_OPTIONS` (`lib/anime-filter.ts`).
    static let origins: [Origin] = [
        Origin(code: "CN", label: "Chinese (Donghua)"),
        Origin(code: "KR", label: "Korean (Aeni)"),
        Origin(code: "TW", label: "Taiwanese")
    ]

    /// Desktop's `animeSeedGenres` takes at most three genres.
    static let seedLimit = 3

    static func genreID(named name: String) -> Int? {
        genres.first { $0.label == name }?.id
    }

    /// Desktop's `animeSeedGenres`: genres from the viewer's own taste first (`tasteGenres`, most watched first),
    /// then the favourites, at most `seedLimit`, with no repeats.
    static func seedGenreIDs(favorites: [Int], tasteGenres: [String]) -> [Int] {
        var out: [Int] = []
        for name in tasteGenres {
            guard let id = genreID(named: name), !out.contains(id) else { continue }
            out.append(id)
            if out.count >= seedLimit { return out }
        }
        for id in favorites {
            if out.count >= seedLimit { break }
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// Desktop's `animeOriginExcluded`: a title with a known country on the excluded list.
    /// A title without a country is never hidden by this rule.
    static func originExcluded(_ media: Media, excludeOrigins: [String]) -> Bool {
        guard !excludeOrigins.isEmpty, let country = media.country else { return false }
        return excludeOrigins.contains(country)
    }

    /// Desktop's `animeFiltered`: hidden by origin, or hidden as watched when that setting is on.
    static func isHidden(_ media: Media, options: Options, isWatched: (String) -> Bool) -> Bool {
        if originExcluded(media, excludeOrigins: options.excludeOrigins) { return true }
        return options.hideWatched && isWatched(media.id)
    }

    /// The titles a picks list may show, in their original order.
    static func filtered(_ items: [Media], options: Options, isWatched: (String) -> Bool) -> [Media] {
        items.filter { !isHidden($0, options: options, isWatched: isWatched) }
    }

    /// Desktop's hero front (`anime.tsx`, `heroSlides`): with hide-watched on, watched titles leave the front only
    /// while at least one unwatched title remains. Otherwise the list is returned unchanged.
    static func heroFront(_ items: [Media], options: Options, isWatched: (String) -> Bool) -> [Media] {
        guard options.hideWatched, items.contains(where: { !isWatched($0.id) }) else { return items }
        return items.filter { !isWatched($0.id) }
    }
}
