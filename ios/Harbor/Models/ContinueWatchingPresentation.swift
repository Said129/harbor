import Foundation

struct ContinueWatchingPresentation {
    let episode: Episode?
    let upNext: Bool
    let progress: Double

    func coordinates(record: LibraryRecord, media: Media) -> EpisodePresentation.Coordinates? {
        let raw = record.playbackCoordinates
        let target = ResumeTarget(id: record.id, season: raw.season, episode: raw.episode, videoId: record.raw["state"]["video_id"].string)
        return EpisodePresentation.coordinates(episode: episode ?? EpisodePresentation.episode(in: media, target: target), fallback: target)
    }

    init(record: LibraryRecord, media: Media, watched: Set<String>, now: Date = Date()) {
        let selected = media.episodic ? EpisodeSequence.startingEpisode(media.videos ?? [], record: record, watched: watched, now: now) : nil
        let coordinates = record.playbackCoordinates
        let advancing: Bool
        if let selected, let season = coordinates.season, let number = coordinates.episode {
            advancing = selected.season != season || selected.episode != number
        } else { advancing = false }
        episode = selected; upNext = advancing; progress = advancing ? 0 : record.progress
    }
}
