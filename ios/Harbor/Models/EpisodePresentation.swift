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

    static func coordinates(in media: Media?, target: ResumeTarget) -> Coordinates? {
        coordinates(episode: episode(in: media, target: target), fallback: target)
    }
}

enum ContinueWatchingSelection {
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
