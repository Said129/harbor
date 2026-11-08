import Foundation

/// Desktop's next-up pick: `nextUpEp` in `src/views/detail/series-episodes/use-episode-progress-map.ts` and
/// `nextUpKey` in `ordered-episodes.tsx`. The next episode to watch is the first one, in the order the list shows
/// them, that is not watched. Desktop does not special-case season 0 here: the list on screen is the list scanned.
enum NextUpEpisode {
    /// The routing key of the next episode to watch, or nil when every listed episode is watched.
    static func routingKey(in episodes: [Episode], isWatched: (Episode) -> Bool) -> String? {
        episodes.first(where: { !isWatched($0) })?.routingKey
    }
}
