import Foundation

/// Desktop's `animeCwEnd`: what a finished series shows while its next episode has not aired.
/// `hide` drops it from Continue Watching; `timer` keeps the card with a countdown to the air date.
enum ContinueWatchingEnd: String, Sendable {
    case hide, timer
}

struct ContinueWatchingPresentation {
    let episode: Episode?
    let upNext: Bool
    let progress: Double
    /// Desktop's `cwHideCaughtUp` outcome: the card renders nothing and leaves the row.
    let hidden: Bool
    /// Desktop's `animeCwEnd` "timer": the air date of the next episode while the card waits for it.
    let airsAt: Date?

    func coordinates(record: LibraryRecord, media: Media) -> EpisodePresentation.Coordinates? {
        let raw = record.playbackCoordinates
        let target = ResumeTarget(id: record.id, season: raw.season, episode: raw.episode, videoId: record.raw["state"]["video_id"].string)
        return EpisodePresentation.coordinates(episode: episode ?? EpisodePresentation.episode(in: media, target: target), fallback: target)
    }

    /// `advanceNext` is Desktop's `cwAdvanceNext`. On (the default) a finished episode moves the card to the next one.
    /// Off, the card keeps the episode it was on, with its remaining time, and shows it as in-progress or finished.
    /// `hideCaughtUp` and `endMode` are Desktop's `cwHideCaughtUp` and `animeCwEnd`. They only act on a finished episode
    /// whose next episode has not aired. Desktop's `useCwAdvance` receives `cwAdvanceNext` as its `enabled` flag and returns
    /// the plain list when it is off, so with `advanceNext` off these rules do nothing either.
    init(record: LibraryRecord, media: Media, watched: Set<String>, now: Date = Date(), advanceNext: Bool = true, hideCaughtUp: Bool = true, endMode: ContinueWatchingEnd = .hide) {
        let videos = media.videos ?? []
        let selected = media.episodic ? EpisodeSequence.startingEpisode(videos, record: record, watched: watched, now: now) : nil
        let coordinates = record.playbackCoordinates
        let target = ResumeTarget(id: record.id, season: coordinates.season, episode: coordinates.episode, videoId: record.raw["state"]["video_id"].string)
        let current = media.episodic ? EpisodePresentation.episode(in: media, target: target) : nil
        let released = ContinueWatchingAdvance.advances(
            enabled: true,
            selectedSeason: selected?.season,
            selectedEpisode: selected?.episode,
            currentSeason: coordinates.season,
            currentEpisode: coordinates.episode
        )
        var outcome = ContinueWatchingOutcome.show
        if advanceNext, let current, !released, !videos.isEmpty {
            let next = ContinueWatchingAdvance.nextUnwatched(after: current, in: videos, watched: watched)
            outcome = ContinueWatchingAdvance.outcome(
                finished: ContinueWatchingAdvance.finished(record),
                advancing: released,
                hasNext: next != nil,
                nextAirDate: next?.releaseDate,
                now: now,
                hideCaughtUp: hideCaughtUp,
                endMode: endMode
            )
        }
        let advancing = advanceNext && released
        episode = advanceNext ? selected : current
        upNext = advancing
        progress = advancing ? 0 : record.progress
        hidden = outcome == .hide
        if case .waiting(let date) = outcome { airsAt = date } else { airsAt = nil }
    }
}

/// Pure rules behind Desktop's `cwAdvanceNext`, `cwHideCaughtUp`, `animeCwEnd` and `cwPreferEpisodeStill`,
/// kept free of records and media where possible so they can be tested directly.
enum ContinueWatchingAdvance {
    /// True when the card should show the next episode instead of the current one.
    static func advances(enabled: Bool, selectedSeason: Int?, selectedEpisode: Int?, currentSeason: Int?, currentEpisode: Int?) -> Bool {
        guard enabled, let selectedSeason, let selectedEpisode, let currentSeason, let currentEpisode else { return false }
        return selectedSeason != currentSeason || selectedEpisode != currentEpisode
    }

    /// Desktop's `isFinishedSeries`: finished at 90% watched, or flagged watched when the length is unknown.
    static func finished(_ record: LibraryRecord) -> Bool {
        let state = record.raw["state"]
        let duration = state["duration"].numericValue ?? 0
        let flagged = (state["flaggedWatched"].numericValue ?? 0) > 0
        return duration > 0 ? record.progress >= 0.9 : flagged
    }

    /// The first unwatched regular episode after `current`, aired or not. Specials are skipped, as Up Next skips them.
    static func nextUnwatched(after current: Episode, in videos: [Episode], watched: Set<String>) -> Episode? {
        let ordered = EpisodeSequence.ordered(videos)
        guard let index = ordered.firstIndex(where: { (episode: Episode) -> Bool in episode.navigationKey == current.navigationKey }) else { return nil }
        return ordered.dropFirst(index + 1).first { (episode: Episode) -> Bool in
            (episode.season ?? 0) > 0 && (episode.episode ?? 0) > 0 && !watched.contains(episode.watchedKey)
        }
    }

    /// Desktop's `shouldDropFinished` with `animeCwEnd`. A finished series that has a released next episode is `show`
    /// (the card advances). Otherwise `timer` waits for the next air date, and `hide` drops the series when
    /// `cwHideCaughtUp` is on or when no later episode exists at all.
    static func outcome(finished: Bool, advancing: Bool, hasNext: Bool, nextAirDate: Date?, now: Date, hideCaughtUp: Bool, endMode: ContinueWatchingEnd) -> ContinueWatchingOutcome {
        guard finished, !advancing else { return .show }
        if endMode == .timer, let nextAirDate, nextAirDate > now { return .waiting(nextAirDate) }
        return hideCaughtUp || !hasNext ? .hide : .show
    }

    /// Desktop's `cwPreferEpisodeStill`: the episode still leads the card while it shows the episode the user is on.
    /// Up Next cards keep the series artwork, as Desktop does.
    static func stillURL(episode: Episode?, upNext: Bool, prefer: Bool) -> String? {
        guard prefer, !upNext, let still = episode?.thumbnail, !still.isEmpty else { return nil }
        return still
    }

    /// Desktop's countdown in `continue-card.tsx`: days and hours, then hours and minutes, then minutes (at least one).
    static func countdown(until airs: Date, now: Date) -> ContinueWatchingCountdown {
        let seconds = airs.timeIntervalSince(now)
        guard seconds.isFinite, seconds > 0 else { return .airingNow }
        let minutes = Int(min(seconds, 1e12) / 60)
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        let rest = minutes % 60
        if days > 0 { return .days(days, hours) }
        if hours > 0 { return .hours(hours, rest) }
        return .minutes(max(1, rest))
    }
}

enum ContinueWatchingOutcome: Equatable {
    case show, hide, waiting(Date)
}

enum ContinueWatchingCountdown: Equatable {
    case airingNow, days(Int, Int), hours(Int, Int), minutes(Int)
}
