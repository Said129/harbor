import Foundation

/// Desktop's genre discovery rules (`src/lib/feed/tags.ts`, `src/lib/feed/daily-rows-catalog.ts`, `src/components/genre-tiles.tsx`).
enum DiscoveryGenreRules {
    /// Desktop's `TILES` in `GenreTiles`, in Desktop's order. Each name is a key of Desktop's `MOVIE_GENRES`.
    static let tileNames = [
        "Action", "Adventure", "Thriller", "Crime", "Drama", "Romance", "Mystery", "Sci-Fi", "Fantasy", "Horror",
        "Comedy", "Family", "Animation", "Western", "War", "History", "Documentary", "Music",
    ]

    /// Approximate the Desktop OKLCH collage colors in sRGB for native SwiftUI cards.
    /// Values are (gradient start, gradient end, text ink).
    static let tilePalette: [String: (UInt32, UInt32, UInt32)] = [
        "Action": (0x8A352C, 0x301A1A, 0xF5E7E4), "Adventure": (0x397651, 0x1A332A, 0xE8F3EC),
        "Animation": (0x247B83, 0x18363A, 0xE8F4F4), "Comedy": (0x987327, 0x40331F, 0xF7F1DC),
        "Crime": (0x60432E, 0x241E19, 0xF2E9DE), "Documentary": (0x376D4B, 0x1A3228, 0xE7F1EA),
        "Drama": (0x405676, 0x1D293B, 0xE9EEF5), "Family": (0x77752D, 0x34341E, 0xF1F0E1),
        "Fantasy": (0x783C75, 0x332239, 0xF3EAF2), "History": (0x826D2F, 0x373020, 0xF2ECDD),
        "Horror": (0x61251F, 0x251617, 0xF2E5E3), "Music": (0x754094, 0x33203F, 0xF0E9F4),
        "Mystery": (0x5C5826, 0x302F1D, 0xF1F0E0), "Romance": (0x874653, 0x3B232A, 0xF4E8EB),
        "Sci-Fi": (0x4D467F, 0x25223D, 0xEBE9F5), "Thriller": (0x1F5A6A, 0x192D36, 0xE6F0F2),
        "War": (0x6B5B2C, 0x322D1D, 0xF0EDDF), "Western": (0x8A5A32, 0x39271E, 0xF5EDE3),
    ]

    static func tileID(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    static func tmdbGenreRail(_ name: String) -> DiscoveryRail? {
        guard let id = CustomCalendar.movieGenres.first(where: { $0.0 == name })?.1 else { return nil }
        return DiscoveryRail(id: "discover-genre-\(tileID(name))", title: tileLabel(name), kind: "movie", path: "discover/movie",
            parameters: ["with_genres": String(id), "sort_by": "popularity.desc"])
    }

    /// Desktop's `LAMBDA`: how strongly a liked genre raises its chance of being picked.
    static let lambda = 0.85

    /// Desktop's label in the active interface language.
    static func tileLabel(_ name: String) -> String {
        DesktopInterfaceText.value(name)
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
