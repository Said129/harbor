import Foundation

/// Desktop's genre discovery rules (`src/lib/feed/tags.ts`, `src/lib/feed/daily-rows-catalog.ts`, `src/components/genre-tiles.tsx`).
enum DiscoveryGenreRules {
    /// Desktop's `TILES` in `GenreTiles`, in Desktop's order. Each name is a key of Desktop's `MOVIE_GENRES`.
    static let tileNames = [
        "Action", "Adventure", "Thriller", "Crime", "Drama", "Romance", "Mystery", "Sci-Fi", "Fantasy", "Horror",
        "Comedy", "Family", "Animation", "Western", "War", "History", "Documentary", "Music",
    ]

    /// Desktop's `LAMBDA`: how strongly a liked genre raises its chance of being picked.
    static let lambda = 0.85

    /// The tile's text: the Discover translation when it has one, otherwise the Desktop interface translation (English when neither has it).
    static func tileLabel(_ name: String) -> String {
        let discover = DesktopVoyage.copy(name)
        return discover != name ? discover : DesktopInterfaceText.value(name)
    }

    /// Desktop's `movieGenre`: the genre filter with a 70-minute runtime floor. The floor's own keys win.
    static func movieFloor(genreID: Int, floor: [String: String]) -> [String: String] {
        var params: [String: String] = ["with_genres": String(genreID), "with_runtime.gte": "70"]
        for (key, value) in floor { params[key] = value }
        return params
    }

    /// Desktop's `relax`: a looser floor for thin rows. Vote counts drop to 60% (at least 20), the average drops by 0.4.
    static func relax(_ floor: [String: String]) -> [String: String] {
        var out = floor
        if let votes = out["vote_count.gte"] {
            out["vote_count.gte"] = String(max(20, Int(((Double(votes) ?? 0) * 0.6).rounded())))
        }
        if let average = out["vote_average.gte"] {
            out["vote_average.gte"] = String(format: "%.1f", (Double(average) ?? 0) - 0.4)
        }
        return out
    }

    /// Desktop's `genreNames`: `count` movie genres drawn with taste weights (a liked genre is up to 1.85 times as likely).
    static func weightedGenres(affinity: [String: Double], rng: inout DiscoveryFeedRandom.Mulberry32, count: Int) -> [String] {
        let names = CustomCalendar.movieGenres.map { $0.0 }
        return DiscoveryDailyRows.weightedPick(
            names,
            weight: { 1 + lambda * DiscoveryDailyRows.normalizedAffinity(affinity, key: $0) },
            rng: &rng,
            count: count)
    }
}
