import Foundation

/// Desktop's mark-season rules: `allWatched` in `use-episode-progress-map.ts` and the write in `use-mark-season.ts`.
enum SeasonWatchPolicy {
    /// Desktop's `airedOnly` (`src/lib/aired.ts`): dated episodes that aired by `now`; undated ones only before the last aired dated
    /// episode. When no episode has a date, all of them count.
    static func airedOnly(_ episodes: [Episode], now: Date = Date()) -> [Episode] {
        var anyDated = false
        var boundary = -1
        var aired: [Bool?] = []
        for (index, episode) in episodes.enumerated() {
            guard let date = episode.releaseDate else { aired.append(nil); continue }
            anyDated = true
            let past = date <= now
            if past { boundary = index }
            aired.append(past)
        }
        guard anyDated else { return episodes }
        return episodes.indices.filter { index in aired[index] == true || (aired[index] == nil && index <= boundary) }.map { episodes[$0] }
    }

    /// Desktop's `allWatched`: at least one aired episode, and every aired episode is watched.
    static func allWatched(_ episodes: [Episode], watched: Set<String>, now: Date = Date()) -> Bool {
        let aired = airedOnly(episodes, now: now)
        return !aired.isEmpty && aired.allSatisfy { watched.contains($0.watchedKey) }
    }

    /// The episodes one mark-season write changes: only the aired ones when marking watched (Desktop's `airedOnly`), all of them otherwise.
    static func targets(_ episodes: [Episode], marking watched: Bool, now: Date = Date()) -> [Episode] {
        guard watched else { return episodes }
        return airedOnly(episodes, now: now)
    }
}
