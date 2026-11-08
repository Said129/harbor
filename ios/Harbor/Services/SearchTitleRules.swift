import Foundation

/// Desktop's title rules for search (`src/lib/search.ts`, `searchAll`): only titles with a poster are listed,
/// and at most twelve movies and twelve series are shown.
enum SearchTitleRules {
    /// Desktop's `movies.slice(0, 12)` and `series.slice(0, 12)`.
    static let titleLimit = 12

    /// Plans whose rows list titles (Desktop's movie and series results). Other rows, such as Live TV or anime, keep all their titles.
    static func isTitleRow(_ kind: String) -> Bool {
        ["movie", "series", "tv"].contains(kind)
    }

    /// Desktop keeps a movie or series only when TMDB has a `poster_path`. Harbor also counts its IMDb poster fallback.
    static func hasPoster(_ media: Media) -> Bool {
        !(media.poster ?? "").isEmpty || !(media.fallbackPoster ?? "").isEmpty
    }

    /// The poster filter, then the cap, in Desktop's order.
    static func limited(_ metas: [Media]) -> [Media] {
        Array(metas.filter(hasPoster).prefix(titleLimit))
    }
}
