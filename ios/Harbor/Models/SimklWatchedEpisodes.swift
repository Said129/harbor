import Foundation

/// Desktop's Simkl watched keys for one title (`useWatchedSets` and `simklWatchedForId`): the `season:episode` keys that the
/// synced Simkl list marks as watched for this title. Reads the list already in memory, so no network or disk work happens here.
enum SimklWatchedEpisodes {
    static func keys(in snapshot: SimklLibrarySnapshot, for media: Media) -> Set<String> {
        guard let target = SimklTarget.direct(media), let item = snapshot.item(for: target) else { return [] }
        return item.watchedEpisodes
    }
}
