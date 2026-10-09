import Foundation

struct LibraryRecord: Identifiable, Sendable {
    let raw: JSONValue
    var id: String { raw["_id"].string ?? "" }
    var media: Media? {
        guard case .object(var fields) = raw else { return nil }
        fields["id"] = .string(id)
        return Media.parse(.object(fields), kind: "movie")
    }
    var bookmarked: Bool { raw["removed"] != .bool(true) && raw["temp"] != .bool(true) }
    var watched: Bool { (raw["state"]["flaggedWatched"].numericValue ?? 0) > 0 || (raw["state"]["timesWatched"].numericValue ?? 0) > 0 }
    var progress: Double {
        let duration = raw["state"]["duration"].numericValue ?? 0
        let offset = raw["state"]["timeOffset"].numericValue ?? 0
        return duration.isFinite && duration > 0 && offset.isFinite ? min(1, max(0, offset / duration)) : 0
    }
    var continuing: Bool {
        let offset = raw["state"]["timeOffset"].numericValue ?? 0
        guard let media, ["movie", "series", "anime"].contains(media.type), !id.hasPrefix("iptv:"),
              offset.isFinite, offset > 0, bookmarked || raw["temp"] == .bool(true) else { return false }
        // Desktop keeps series with a current video, including the completed
        // episode from which it offers the next one. timesWatched is cumulative;
        // it must not hide a later episode or a movie being watched again.
        return media.type != "movie" || !currentMovieFinished
    }
    private var currentMovieFinished: Bool { (raw["state"]["flaggedWatched"].numericValue ?? 0) > 0 || progress >= 0.9 }
    var modified: String { raw["_mtime"].textValue ?? "" }
    var activityTimestamp: Double { max(Self.timestamp(raw["_mtime"]) ?? 0, Self.timestamp(raw["state"]["lastWatched"]) ?? 0) }
    var playbackCoordinates: (season: Int?, episode: Int?) {
        let state = raw["state"]
        let parts = (state["video_id"].string ?? "").split(separator: ":")
        let anime = ["kitsu", "mal", "anilist", "anidb"].contains(String(parts.first ?? "")) && parts.count == 3
        let season = state["season"].integer ?? (anime ? 1 : parts.count >= 3 ? Int(parts[parts.count - 2]) : nil)
        let episode = state["episode"].integer ?? (parts.count >= 3 ? Int(parts[parts.count - 1]) : nil)
        return (season, episode)
    }
    var playbackCaption: String? {
        var parts: [String] = []
        let coordinates = playbackCoordinates
        if media?.episodic == true, let season = coordinates.season, let episode = coordinates.episode { parts.append("T\(season) · E\(episode)") }
        let duration = raw["state"]["duration"].numericValue ?? 0
        let offset = raw["state"]["timeOffset"].numericValue ?? 0
        if duration.isFinite, duration > 0, offset.isFinite, offset >= 0, duration > offset {
            let minutes = ceil((duration - offset) / 60_000)
            if minutes < Double(Int.max) { parts.append("\(Int(minutes)) min restantes") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    static func timestamp(_ value: String?) -> Double? {
        guard let value else { return nil }
        if let timestamp = Double(value), timestamp.isFinite, timestamp >= 0 { return timestamp }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return nil }
        let timestamp = date.timeIntervalSince1970 * 1_000
        return timestamp.isFinite && timestamp >= 0 ? timestamp : nil
    }
    static func timestamp(_ value: JSONValue) -> Double? {
        if let timestamp = value.numericValue { return timestamp.isFinite && timestamp >= 0 ? timestamp : nil }
        return timestamp(value.string)
    }
    func resume(for target: ResumeTarget) -> CloudResume? {
        guard id == target.id, let media else { return nil }
        let state = raw["state"]
        if media.episodic {
            let sameVideo = target.videoId != nil && state["video_id"].string == target.videoId
            let coordinates = playbackCoordinates
            let sameCoordinates = target.season != nil && target.episode != nil && coordinates.season == target.season && coordinates.episode == target.episode
            guard sameVideo || sameCoordinates else { return nil }
        }
        guard let offset = state["timeOffset"].numericValue, offset.isFinite, offset >= 0 else { return nil }
        let finished = media.type == "movie" && currentMovieFinished
        let timestamp = finished || offset == 0 ? Self.timestamp(raw["_mtime"]) : Self.timestamp(state["lastWatched"]) ?? Self.timestamp(raw["_mtime"])
        guard let timestamp, timestamp < Double(UInt64.max) else { return nil }
        let duration = state["duration"].numericValue ?? 0
        return CloudResume(entry: ResumeEntry(ms: finished ? 0 : offset, t: UInt64(timestamp)), durationMs: duration.isFinite && duration >= 0 ? duration : 0)
    }
    static func new(_ media: Media) -> [String: JSONValue] {
        let now = Date().ISO8601Format()
        return ["_id": .string(media.id), "type": .string(media.type), "name": .string(media.name), "poster": media.poster.map(JSONValue.string) ?? .null, "background": media.background.map(JSONValue.string) ?? .null, "posterShape": .string("poster"), "removed": .bool(false), "temp": .bool(false), "_ctime": .string(now), "_mtime": .string(now), "state": .object(["timeOffset": .integer(0), "duration": .integer(0), "timeWatched": .integer(0), "flaggedWatched": .integer(0), "video_id": .null, "lastWatched": .null])]
    }
}

extension JSONValue {
    var numericValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .unsigned(let value): Double(value)
        case .number(let value): value
        default: nil
        }
    }
}
