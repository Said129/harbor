import Foundation

enum EpisodeSequence {
    static func ordered(_ videos: [Episode]) -> [Episode] {
        var identifiers = Set<String>()
        return WatchedCodec.ordered(videos).filter { identifiers.insert($0.id).inserted }
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
