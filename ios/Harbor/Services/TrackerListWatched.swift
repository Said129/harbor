import Foundation
import Observation

/// Desktop's `useAnilistWatched` and `useMalWatched` (`lib/anilist/use-anilist-watched.ts`, `lib/mal/use-mal-watched.ts`):
/// a list entry's progress marks the first N aired episodes of the title as watched, and a completed entry marks all of them.
/// Pure value logic: the caller passes the aired episode keys already in season and number order.
enum TrackerListWatched {
    /// One list entry as the watched rule reads it: whether it is completed, its progress and the episode total.
    struct Progress: Equatable, Sendable {
        let completed: Bool
        let progress: Int
        let total: Int?
    }

    /// Desktop's cap: the aired episodes, limited to the known episode total when there is one.
    static func watchedKeys(completed: Bool, progress: Int, total: Int?, airedKeys: [String]) -> Set<String> {
        let cap: Int
        if let total, total > 0 { cap = min(airedKeys.count, total) } else { cap = airedKeys.count }
        let count = completed ? cap : max(0, min(progress, cap))
        return Set(airedKeys.prefix(count))
    }

    /// The AniList list entries by Harbor id: `anilist:N`, and `mal:N` too when AniList knows the MyAnimeList id.
    static func aniListProgress(_ list: [AniListListEntry]) -> [String: Progress] {
        var out: [String: Progress] = [:]
        for entry in list {
            let progress = Progress(completed: entry.status == .completed, progress: entry.progress, total: entry.media.episodes)
            out["anilist:\(entry.media.id)"] = progress
            if let malID = entry.media.idMal { out["mal:\(malID)"] = progress }
        }
        return out
    }

    /// The MyAnimeList list entries by Harbor id, `mal:N`.
    static func malProgress(_ list: [MALListEntry]) -> [String: Progress] {
        var out: [String: Progress] = [:]
        for entry in list {
            out["mal:\(entry.media.id)"] = Progress(completed: entry.status == .completed, progress: entry.watched, total: entry.media.numEpisodes)
        }
        return out
    }

    /// The watched keys one title gets from the list entry the store holds for its Harbor id.
    @MainActor static func keys(in store: TrackerListProgressStore, for media: Media) -> Set<String> {
        guard let progress = store.entries[media.id] else { return [] }
        let airedKeys = ManualWatchedSelection.releasedEpisodes(media).map(\.watchedKey)
        return watchedKeys(completed: progress.completed, progress: progress.progress, total: progress.total, airedKeys: airedKeys)
    }
}

/// The AniList and MyAnimeList list entries the last list load read, by Harbor id, for one profile. The lists screens
/// fill it and `LibraryModel.watchedEpisodes` reads it, so nothing here touches the network.
@MainActor @Observable final class TrackerListProgressStore {
    private static var stores: [String: TrackerListProgressStore] = [:]
    static func forOwner(_ owner: String) -> TrackerListProgressStore {
        if let saved = stores[owner] { return saved }
        let store = TrackerListProgressStore(); stores[owner] = store; return store
    }

    private(set) var entries: [String: TrackerListWatched.Progress] = [:]

    /// AniList and MyAnimeList each fill their own ids, so a load adds to what the other list left instead of replacing it.
    func replace(_ entries: [String: TrackerListWatched.Progress]) { self.entries.merge(entries) { _, new in new } }
}
