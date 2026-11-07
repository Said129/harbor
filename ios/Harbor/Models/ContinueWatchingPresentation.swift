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

    /// `advanceNext` is Desktop's `cwAdvanceNext`. On (the default) a finished episode moves the card to the next one.
    /// Off, the card keeps the episode it was on, with its remaining time, and shows it as in-progress or finished.
    init(record: LibraryRecord, media: Media, watched: Set<String>, now: Date = Date(), advanceNext: Bool = true) {
        let selected = media.episodic ? EpisodeSequence.startingEpisode(media.videos ?? [], record: record, watched: watched, now: now) : nil
        let coordinates = record.playbackCoordinates
        let advancing = ContinueWatchingAdvance.advances(
            enabled: advanceNext,
            selectedSeason: selected?.season,
            selectedEpisode: selected?.episode,
            currentSeason: coordinates.season,
            currentEpisode: coordinates.episode
        )
        var shown: Episode? = selected
        if !advanceNext {
            let target = ResumeTarget(id: record.id, season: coordinates.season, episode: coordinates.episode, videoId: record.raw["state"]["video_id"].string)
            shown = media.episodic ? EpisodePresentation.episode(in: media, target: target) : nil
        }
        episode = shown; upNext = advancing; progress = advancing ? 0 : record.progress
    }
}

/// Pure rule behind Desktop's `cwAdvanceNext`, kept free of records and media so it can be tested directly.
enum ContinueWatchingAdvance {
    /// True when the card should show the next episode instead of the current one.
    static func advances(enabled: Bool, selectedSeason: Int?, selectedEpisode: Int?, currentSeason: Int?, currentEpisode: Int?) -> Bool {
        guard enabled, let selectedSeason, let selectedEpisode, let currentSeason, let currentEpisode else { return false }
        return selectedSeason != currentSeason || selectedEpisode != currentEpisode
    }
}
