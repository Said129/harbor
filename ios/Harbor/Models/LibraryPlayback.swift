import Foundation

enum LibraryPlayback {
    static func apply(_ snapshot: ResumeSnapshot, target: ResumeTarget, media: Media, to fields: inout [String: JSONValue]) throws {
        guard target.id == media.id, snapshot.positionMs.isFinite, snapshot.positionMs >= 0,
              snapshot.durationMs.isFinite, snapshot.durationMs >= 0 else { throw HarborError(code: "invalid-resume-position") }
        var state = (fields["state"] ?? .null).objectValue
        let videoID: String
        if let id = target.videoId { videoID = id }
        else if media.episodic, let season = target.season, let episode = target.episode { videoID = "\(target.id):\(season):\(episode)" }
        else { videoID = target.id }
        let previousVideo = state["video_id"]?.string
        let videoChanged = previousVideo != nil && previousVideo != videoID
        let finished = snapshot.durationMs > 0 && snapshot.positionMs / snapshot.durationMs >= 0.9
        let meaningfulResume = snapshot.durationMs > 0 && snapshot.positionMs >= 45_000 && !finished
        let previousFlag = value(state["flaggedWatched"])
        let previousTimeWatched = value(state["timeWatched"])
        let effectiveFlag = videoChanged || meaningfulResume || snapshot.positionMs == 0 ? 0 : previousFlag

        // These are Stremio's current-video and cumulative fields. Preserve
        // unknown provider data while resetting the previous episode's flag.
        state["timeOffset"] = .number(snapshot.positionMs)
        state["timeWatched"] = .number(snapshot.positionMs)
        state["duration"] = .number(snapshot.durationMs)
        state["lastWatched"] = .string(Date(timeIntervalSince1970: Double(snapshot.timestampMs) / 1_000).ISO8601Format())
        state["overallTimeWatched"] = .number(value(state["overallTimeWatched"]) + (videoChanged ? previousTimeWatched : 0))
        state["timesWatched"] = .number(value(state["timesWatched"]) + (finished && effectiveFlag == 0 ? 1 : 0))
        state["flaggedWatched"] = .number(finished ? 1 : effectiveFlag)
        state["video_id"] = .string(videoID)
        if let season = target.season { state["season"] = .integer(Int64(season)) } else { state.removeValue(forKey: "season") }
        if let episode = target.episode { state["episode"] = .integer(Int64(episode)) } else { state.removeValue(forKey: "episode") }
        if media.episodic, finished, let videos = media.videos,
           let episode = videos.first(where: { video in
               if video.id == videoID { return true }
               guard let season = target.season, let episode = target.episode else { return false }
               return video.season == season && video.episode == episode
           }) {
            var watched = try WatchedCodec.decode(state["watched"]?.string, videos: videos)
            watched.insert(episode.watchedKey)
            state["watched"] = .string(try WatchedCodec.encode(watched, videos: videos))
        }
        fields["state"] = .object(state)
        if fields["removed"] == .bool(true) { fields["temp"] = .bool(true) }
    }

    private static func value(_ field: JSONValue?) -> Double {
        guard let value = field?.numericValue, value.isFinite, value >= 0 else { return 0 }
        return value
    }
}
