import Foundation

enum EpisodeSequence {
    static func ordered(_ videos: [Episode]) -> [Episode] {
        var identifiers = Set<String>()
        return WatchedCodec.ordered(videos).filter { identifiers.insert($0.id).inserted }
    }

    static func startingEpisode(_ videos: [Episode], record: LibraryRecord?, watched: Set<String>, now: Date = Date()) -> Episode? {
        let available = ordered(videos).filter { $0.releaseDate.map { $0 <= now } ?? true }
        let coordinates = record?.playbackCoordinates
        let resumed = available.first {
            if let videoID = record?.raw["state"]["video_id"].string, $0.id == videoID { return true }
            guard let season = coordinates?.season, let episode = coordinates?.episode else { return false }
            return $0.season == season && $0.episode == episode
        }
        guard let resumed else {
            return available.first { ($0.season ?? 1) > 0 && !watched.contains($0.watchedKey) } ?? available.first
        }
        let offset = record?.raw["state"]["timeOffset"].numericValue ?? 0
        let duration = record?.raw["state"]["duration"].numericValue ?? 0
        let flagged = (record?.raw["state"]["flaggedWatched"].numericValue ?? 0) > 0
        // A watched bit can belong to an earlier viewing. Keep a fresh partial
        // rewatch on the current episode, as with Desktop's resume position.
        if offset.isFinite, offset > 0, (record?.progress ?? 0) < 0.9, duration > 0 || !flagged { return resumed }
        let finished = watched.contains(resumed.watchedKey) || (record?.progress ?? 0) >= 0.9
            || flagged
        guard finished, let season = resumed.season, season > 0,
              let index = available.firstIndex(where: { $0.watchedKey == resumed.watchedKey }) else { return resumed }
        // Desktop advances past finished ordinary episodes and retains the
        // original point when no following unwatched episode is available.
        return available.dropFirst(index + 1).first {
            ($0.season ?? 0) > 0 && ($0.episode ?? 0) > 0 && !watched.contains($0.watchedKey)
        } ?? resumed
    }

    static func adjacent(_ videos: [Episode], current: ResumeTarget, now: Date = Date()) -> (previous: Episode?, next: Episode?) {
        let ordered = ordered(videos)
        guard let playing = ordered.first(where: { $0.id == current.videoId }) ?? ordered.first(where: { $0.season == current.season && $0.episode == current.episode }),
              let season = playing.season, let episode = playing.episode, season >= 0, episode > 0 else { return (nil, nil) }
        var coordinates = Set<String>()
        // Specials have their own sequence. Ordinary episodes cross season
        // boundaries without entering specials or unaired episodes.
        let available = ordered.filter {
            guard let candidateSeason = $0.season, let number = $0.episode, number > 0,
                  (season == 0 ? candidateSeason == 0 : candidateSeason > 0),
                  ($0.releaseDate.map({ $0 <= now }) ?? true) else { return false }
            return coordinates.insert($0.watchedKey).inserted
        }
        guard let index = available.firstIndex(where: { $0.watchedKey == playing.watchedKey }) else { return (nil, nil) }
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
