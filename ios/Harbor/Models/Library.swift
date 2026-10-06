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
        return !watched && offset.isFinite && offset > 0 && (bookmarked || raw["temp"] == .bool(true))
    }
    var modified: String { raw["_mtime"].string ?? "" }
    var activityTimestamp: Double { max(Self.timestamp(modified) ?? 0, Self.timestamp(raw["state"]["lastWatched"].string) ?? 0) }
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
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return nil }
        let timestamp = date.timeIntervalSince1970 * 1_000
        return timestamp.isFinite && timestamp >= 0 ? timestamp : nil
    }
    func resume(for target: ResumeTarget) -> CloudResume? {
        guard id == target.id, let media else { return nil }
        let state = raw["state"]
        if media.episodic {
            let sameVideo = target.videoId != nil && state["video_id"].string == target.videoId
            let sameCoordinates = target.season != nil && target.episode != nil && state["season"].integer == target.season && state["episode"].integer == target.episode
            guard sameVideo || sameCoordinates else { return nil }
        }
        guard let offset = state["timeOffset"].numericValue, offset.isFinite, offset >= 0 else { return nil }
        let finished = !media.episodic && watched
        let value = finished || offset == 0 ? modified : state["lastWatched"].string ?? modified
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value), date.timeIntervalSince1970 >= 0, date.timeIntervalSince1970 * 1000 < Double(UInt64.max) else { return nil }
        let duration = state["duration"].numericValue ?? 0
        return CloudResume(entry: ResumeEntry(ms: finished ? 0 : offset, t: UInt64(date.timeIntervalSince1970 * 1000)), durationMs: duration.isFinite && duration >= 0 ? duration : 0)
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
