import Foundation

enum EpisodeSequence {
    static func ordered(_ videos: [Episode], presentation: EpisodeOrderProjection? = nil) -> [Episode] {
        if let ordered = presentation?.ordered(videos) { return ordered }
        var identifiers = Set<String>()
        return WatchedCodec.ordered(videos).filter { identifiers.insert($0.routingKey).inserted }
    }

    static func startingEpisode(_ videos: [Episode], record: LibraryRecord?, watched: Set<String>, now: Date = Date(), presentation: EpisodeOrderProjection? = nil, watchedBySource: [String: Set<String>] = [:]) -> Episode? {
        let selected = presentation.flatMap { $0.applies(to: videos) ? $0 : nil }
        let available = ordered(videos, presentation: selected).filter { $0.releaseDate.map { $0 <= now } ?? true }
        let singleSource = Set(videos.compactMap(\.sourceMetaID)).count <= 1
        func regular(_ episode: Episode, defaultSeason: Int = 0) -> Bool { selected?.isRegular(episode.routingKey) ?? ((episode.season ?? defaultSeason) > 0) }
        func wasWatched(_ episode: Episode) -> Bool {
            if let id = episode.sourceMetaID {
                if let source = watchedBySource[id] { return source.contains(episode.watchedKey) }
                if !watchedBySource.isEmpty || !singleSource { return false }
            }
            return watched.contains(episode.watchedKey)
        }
        let coordinates = record?.playbackCoordinates
        let resumed = available.first {
            if let source = $0.sourceMetaID, source != record?.id { return false }
            if let videoID = record?.raw["state"]["video_id"].string, $0.id == videoID { return true }
            guard let season = coordinates?.season, let episode = coordinates?.episode else { return false }
            return $0.season == season && $0.episode == episode
        }
        guard let resumed else {
            return available.first { regular($0, defaultSeason: 1) && !wasWatched($0) } ?? available.first
        }
        let offset = record?.raw["state"]["timeOffset"].numericValue ?? 0
        let duration = record?.raw["state"]["duration"].numericValue ?? 0
        let flagged = (record?.raw["state"]["flaggedWatched"].numericValue ?? 0) > 0
        // A watched bit can belong to an earlier viewing. Keep a fresh partial
        // rewatch on the current episode, as with Desktop's resume position.
        if offset.isFinite, offset > 0, (record?.progress ?? 0) < 0.9, duration > 0 || !flagged { return resumed }
        let finished = wasWatched(resumed) || (record?.progress ?? 0) >= 0.9
            || flagged
        guard finished, regular(resumed),
              let index = available.firstIndex(where: { $0.navigationKey == resumed.navigationKey }) else { return resumed }
        // Desktop advances past finished ordinary episodes and retains the
        // original point when no following unwatched episode is available.
        return available.dropFirst(index + 1).first {
            regular($0) && ($0.episode ?? 0) > 0 && !wasWatched($0)
        } ?? resumed
    }

    static func adjacent(_ videos: [Episode], current: ResumeTarget, now: Date = Date(), presentation: EpisodeOrderProjection? = nil) -> (previous: Episode?, next: Episode?) {
        let selected = presentation.flatMap { $0.applies(to: videos) ? $0 : nil }
        let ordered = ordered(videos, presentation: selected)
        guard let playing = ordered.first(where: { ($0.sourceMetaID == nil || $0.sourceMetaID == current.id) && $0.id == current.videoId }) ?? ordered.first(where: { $0.belongs(to: current) }),
              let season = playing.season, let episode = playing.episode, season >= 0, episode > 0 else { return (nil, nil) }
        var coordinates = Set<String>()
        let sequence = selected?.sequence(containing: playing.routingKey)
        // Specials have their own sequence. Ordinary episodes cross season
        // boundaries without entering specials or unaired episodes.
        let available = ordered.filter {
            guard let candidateSeason = $0.season, let number = $0.episode, number > 0,
                  (sequence?.contains($0.routingKey) ?? (season == 0 ? candidateSeason == 0 : candidateSeason > 0)),
                  ($0.releaseDate.map({ $0 <= now }) ?? true) else { return false }
            return coordinates.insert($0.navigationKey).inserted
        }
        guard let index = available.firstIndex(where: { $0.navigationKey == playing.navigationKey }) else { return (nil, nil) }
        return (index > 0 ? available[index - 1] : nil, index + 1 < available.count ? available[index + 1] : nil)
    }

    static func leadSeconds(setting: Double, duration: Double) -> Double {
        guard setting.isFinite, duration.isFinite, duration > 0 else { return 0 }
        if setting == 0 { return 0 }
        if setting > 0 { return min(300, setting) }
        return min(45, max(15, (duration * 0.04).rounded()))
    }

    static func permitsAutomaticAdvance(duration: Double, startedAtMs: Double, ended: Bool, hasError: Bool) -> Bool {
        // Match Desktop's short-video and near-end resume protection. A
        // native playback error must leave the picker available to the user.
        duration.isFinite && duration >= 150 && startedAtMs.isFinite && startedAtMs / 1000 / duration < 0.8 && ended && !hasError
    }
}
