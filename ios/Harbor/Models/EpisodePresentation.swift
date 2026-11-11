import Foundation

enum EpisodePresentation {
    struct Coordinates: Equatable, Sendable {
        let season: Int
        let episode: Int
        var caption: String { "T\(season) · E\(episode)" }
        var compactCaption: String { "S\(season)E\(episode)" }
    }

    static func episode(in media: Media?, target: ResumeTarget) -> Episode? {
        guard let media, media.id == target.id else { return nil }
        let videos = media.videos ?? []
        if let videoID = target.videoId, let exact = videos.first(where: { $0.id == videoID }) { return exact }
        guard let season = target.season, let episode = target.episode else { return nil }
        let matches = videos.filter { $0.season == season && $0.episode == episode }
        return matches.count == 1 ? matches.first : nil
    }

    static func coordinates(episode: Episode?, fallback: ResumeTarget? = nil) -> Coordinates? {
        guard let season = episode?.listedSeason ?? fallback?.season,
              let number = episode?.listedEpisode ?? fallback?.episode,
              season >= 0, number > 0 else { return nil }
        return Coordinates(season: season, episode: number)
    }

    static func coordinates(in media: Media?, target: ResumeTarget, presentation: EpisodeOrderProjection? = nil) -> Coordinates? {
        let original = episode(in: media, target: target)
        guard let media, media.id == target.id, let presentation else { return coordinates(episode: original, fallback: target) }
        // A running session keeps its original metadata snapshot. The order can
        // finish loading later, just as it does for previous/next navigation.
        let source = presentation.videos.filter { $0.sourceMetaID == nil || $0.sourceMetaID == media.id }
        let projected: Episode?
        if let id = original?.id ?? target.videoId {
            let matches = source.filter { $0.id == id }
            projected = matches.count == 1 ? matches.first : nil
        } else { projected = nil }
        return coordinates(episode: projected ?? original, fallback: target)
    }
}

enum ContinueWatchingSelection {
    static func canResolveAnimeRoot(_ record: LibraryRecord, detectedAnime: Set<String>) -> Bool {
        includes(record, kind: "anime", detectedAnime: detectedAnime) && AnimePublicIdentity(record.id) != nil
    }

    static func roomCards(_ records: [LibraryRecord], kind: String?, excludesAnime: Bool, detectedAnime: Set<String>,
                          franchiseRoot: (String) -> String? = { _ in nil }) -> [LibraryRecord] {
        let selected = records.filter { includes($0, kind: kind, detectedAnime: detectedAnime) }
        let visible = HomeCatalogFilter.continueWatching(selected, animeOnlyInAnimeRoom: excludesAnime, detectedAnime: detectedAnime)
        switch kind {
        case nil:
            let cards = HomeContinueWatchingRules.cards(visible)
            return HomeContinueWatchingRules.onePerFranchise(cards, root: { franchiseRoot($0.id) }, watched: HomeContinueWatchingRules.lastWatched)
        case "series": return Array(visible.prefix(16))
        default: return visible
        }
    }

    static func includes(_ record: LibraryRecord, kind: String?, detectedAnime: Set<String>) -> Bool {
        guard let kind else { return true }
        guard let media = record.media else { return false }
        if kind == "anime" {
            return AnimeService.isAnime(media.id) || media.type == "anime" || record.raw["isAnime"] == .bool(true) || detectedAnime.contains(media.id)
        }
        // Desktop Shows includes IMDb series even when also detected as anime.
        // Anime-provider IDs have their own room and are excluded from Shows.
        return media.type == kind && !AnimeService.isAnime(media.id)
    }
}
