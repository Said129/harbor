import Foundation

/// One released episode for Home's "New Episodes" row. Desktop's `NewEpisode` in `src/lib/new-episodes.ts`.
struct NewEpisode: Identifiable, Equatable, Sendable {
    let key: String
    let seriesID: String
    let seriesName: String
    let season: Int
    let episode: Int
    let title: String
    let still: String?
    let poster: String?
    let released: Date
    var id: String { key }
}

/// Desktop's `useNewEpisodes` and `newEpisodesFor` rules. Pure, so the row only loads metadata and renders.
enum NewEpisodeRule {
    /// Desktop's `MAX_SERIES` and `MAX_CARDS` in `use-new-episodes.ts`.
    static let maxSeries = 40
    static let maxCards = 60
    /// Desktop's `RECENT_MS`: only episodes released within the last 45 days count as new.
    static let recentSeconds: TimeInterval = 45 * 24 * 60 * 60

    /// Series with an IMDb id from the Continue Watching list, first 40 of them.
    static func candidates(_ records: [LibraryRecord]) -> [LibraryRecord] {
        Array(records.filter { (record: LibraryRecord) -> Bool in record.id.hasPrefix("tt") && record.media?.type == "series" }.prefix(maxSeries))
    }

    /// Desktop's `Date.parse(state.lastWatched ?? _mtime)`, the time an episode must come after to count as new.
    static func lastWatched(_ record: LibraryRecord) -> Date? {
        let stamp = LibraryRecord.timestamp(record.raw["state"]["lastWatched"]) ?? LibraryRecord.timestamp(record.raw["_mtime"])
        return stamp.map { Date(timeIntervalSince1970: $0 / 1_000) }
    }

    /// Desktop's `computeList`: released after the last watch, released within 45 days, not in the future, and not the 0x0 entry.
    static func episodes(in media: Media, seriesID: String, seriesName: String, poster: String?, lastWatched: Date, now: Date) -> [NewEpisode] {
        let oldest = now.addingTimeInterval(-recentSeconds)
        var result: [NewEpisode] = []
        for video in media.videos ?? [] {
            guard let released = video.releaseDate, released <= now, released > lastWatched, released > oldest else { continue }
            let season = video.season ?? 0
            let number = video.episode ?? 0
            guard season != 0 || number != 0 else { continue }
            result.append(NewEpisode(key: "\(seriesID):\(season):\(number)", seriesID: seriesID, seriesName: seriesName, season: season, episode: number,
                title: video.name ?? video.title ?? "", still: video.thumbnail, poster: media.poster ?? poster, released: released))
        }
        return result
    }

    /// Desktop's merge: one entry per key, newest first, capped at 60 cards. Dismissals apply afterwards, as in `visible`.
    static func merged(_ lists: [[NewEpisode]]) -> [NewEpisode] {
        var seen = Set<String>()
        var unique: [NewEpisode] = []
        for episode in lists.flatMap({ $0 }) where seen.insert(episode.key).inserted { unique.append(episode) }
        return Array(unique.sorted { $0.released > $1.released }.prefix(maxCards))
    }

    static func visible(_ found: [NewEpisode], dismissed: Set<String>) -> [NewEpisode] {
        found.filter { (episode: NewEpisode) -> Bool in !dismissed.contains(episode.key) }
    }
}

/// Desktop's `dismissEpisodes`: dismissals are kept on this device only, and the newest 600 keys are kept.
enum NewEpisodeDismissals {
    static let storageKey = "harbor.newEpisodes.dismissed.v1"
    static let limit = 600

    /// Appends keys in the order given, skipping those already stored, then keeps the newest `limit`.
    static func adding(_ keys: [String], to stored: [String]) -> [String] {
        var seen = Set(stored)
        var fresh: [String] = []
        for key in keys where seen.insert(key).inserted { fresh.append(key) }
        return Array((stored + fresh).suffix(limit))
    }

    static func load(_ defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: storageKey) ?? []
    }

    static func save(_ keys: [String], defaults: UserDefaults = .standard) {
        defaults.set(Array(keys.suffix(limit)), forKey: storageKey)
    }
}
