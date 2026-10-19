import Foundation

/// The display pool never becomes a source media's watched-bitset array.
struct AnimeEpisodePool: Sendable {
    let currentID: String
    let sources: [String: Media]
    let episodes: [Episode]
    let missingEntryIDs: [String]
    private let episodeKeys: Set<String>

    init(current: Media, others: [Media], missingEntryIDs: [String] = []) {
        currentID = current.id
        self.missingEntryIDs = missingEntryIDs
        var sources: [String: Media] = [:], combined: [Episode] = [], seen = Set<String>()
        for media in [current] + others where sources[media.id] == nil {
            sources[media.id] = media
            for raw in media.videos ?? [] {
                guard (raw.episode ?? 0) > 0 else { continue }
                var episode = raw; episode.sourceMetaID = media.id
                let coordinates = episode.imdbSeason.flatMap { season in episode.imdbEpisode.map { "s\(season)e\($0)" } }
                let key = media.id + "|" + (coordinates ?? episode.id)
                if seen.insert(key).inserted { combined.append(episode) }
            }
        }
        self.sources = sources
        episodeKeys = Set(combined.map { $0.routingKey + "|" + $0.watchedKey })
        // Current entry wins ties, following Desktop's pool insertion order.
        episodes = combined.enumerated().sorted { first, second in
            let a = first.element, b = second.element
            let seasonA = a.imdbSeason ?? 99, seasonB = b.imdbSeason ?? 99
            if seasonA != seasonB { return seasonA < seasonB }
            let numberA = a.imdbEpisode ?? a.episode ?? 0, numberB = b.imdbEpisode ?? b.episode ?? 0
            if numberA != numberB { return numberA < numberB }
            let absoluteA = a.absoluteNumber ?? a.episode ?? 0, absoluteB = b.absoluteNumber ?? b.episode ?? 0
            return absoluteA == absoluteB ? first.offset < second.offset : absoluteA < absoluteB
        }.map(\.element)
    }

    func source(for episode: Episode, presentation: EpisodeOrderProjection? = nil) -> Media? {
        guard let id = episode.sourceMetaID, var media = sources[id],
              episodeKeys.contains(episode.routingKey + "|" + episode.watchedKey) else { return nil }
        guard let presentation else { return media }
        let projected = Dictionary(presentation.videos.map { ($0.routingKey, $0) }, uniquingKeysWith: { first, _ in first })
        media.videos = media.videos?.map { raw in
            var value = raw; value.sourceMetaID = id
            return projected[value.routingKey] ?? value
        }
        return media
    }

    @MainActor func watched(in library: LibraryModel) -> [String: Set<String>] {
        sources.mapValues { library.watchedEpisodes($0) }
    }

    @MainActor func startingEpisode(in library: LibraryModel, presentation: EpisodeOrderProjection) -> Episode? {
        EpisodeSequence.startingEpisode(presentation.videos, record: library.items.first { $0.id == currentID },
            watched: [], presentation: presentation, watchedBySource: watched(in: library))
    }
}
