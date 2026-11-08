import Foundation

/// One saved title the library calendar may resolve: the fields Desktop's `gatherCandidates` reads.
struct LibraryCalendarEntry: Sendable {
    let media: Media
    /// "series" or "movie", as Desktop's `gatherCandidates` maps them.
    let type: String
    let mtime: Double
    let temp: Bool
    let removed: Bool
}

/// Desktop's library release calendar rules (`calendar-library.ts`): which saved titles are resolved, in which order and how many.
enum LibraryCalendarCandidates {
    static let seriesLimit = 80
    static let movieLimit = 80

    /// Library records as Desktop's Stremio library items: every record not removed counts, temp ones included.
    static func entries(from records: [LibraryRecord]) -> [LibraryCalendarEntry] {
        records.compactMap { record in
            guard let media = record.media else { return nil }
            return LibraryCalendarEntry(media: media, type: record.raw["type"].string == "series" ? "series" : "movie",
                                        mtime: record.modifiedTimestamp ?? 0, temp: record.raw["temp"] == .bool(true),
                                        removed: record.raw["removed"] == .bool(true))
        }
    }

    /// The Trakt watchlist as Desktop's `fetchTraktWatchlist` candidates. The id is IMDb first, then TMDB.
    static func entries(traktWatchlist items: [TraktLibraryItem]) -> [LibraryCalendarEntry] {
        items.compactMap { item in
            guard let media = item.importMedia else { return nil }
            return LibraryCalendarEntry(media: media, type: item.type == .movie ? "movie" : "series",
                                        mtime: LibraryRecord.timestamp(item.contextDate) ?? 0, temp: false, removed: false)
        }
    }

    /// Desktop's `gatherCandidates` merge, `curatedFirst` order and per-kind limits, as the titles to resolve.
    static func select(_ entries: [LibraryCalendarEntry]) -> [Media] {
        var order: [String] = []
        var merged: [String: (media: Media, type: String, temp: Bool, mtime: Double)] = [:]
        for entry in entries where !entry.removed {
            let id = entry.media.id
            if let previous = merged[id] {
                var media = previous.media
                if media.name.isEmpty { media.name = entry.media.name }
                merged[id] = (media, previous.type, previous.temp && entry.temp, max(previous.mtime, entry.mtime))
            } else {
                order.append(id)
                merged[id] = (entry.media, entry.type, entry.temp, entry.mtime)
            }
        }
        let candidates = order.compactMap { merged[$0] }
        let series = candidates.filter { $0.type == "series" }.sorted(by: curatedFirst)
        let movies = candidates.filter { $0.type == "movie" }.sorted(by: curatedFirst)
        return Array(series.prefix(seriesLimit)).map(\.media) + Array(movies.prefix(movieLimit)).map(\.media)
    }

    /// Curated (not temp) titles first, then the most recently changed.
    private static func curatedFirst(_ a: (media: Media, type: String, temp: Bool, mtime: Double), _ b: (media: Media, type: String, temp: Bool, mtime: Double)) -> Bool {
        if a.temp != b.temp { return !a.temp }
        return a.mtime > b.mtime
    }

    /// Desktop skips the season zero, episode zero entry of a series.
    static func skipsEpisode(season: Int?, number: Int?) -> Bool {
        season == 0 && number == 0
    }

    /// Desktop's duplicate key: the show name with letters and digits only, the season and episode, and the day.
    static func dedupeKey(showName: String, season: Int?, episode: Int?, day: String) -> String {
        let norm = showName.lowercased().filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
        if let season, let episode { return "tv|\(norm)|s\(season)e\(episode)|\(day)" }
        return "movie|\(norm)|\(day)"
    }

    /// Keeps the first item for each key, in order.
    static func dedupe<T>(_ items: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert(key($0)).inserted }
    }
}
