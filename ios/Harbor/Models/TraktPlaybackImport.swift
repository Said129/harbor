import Foundation

enum TraktPlaybackImport {
    static func items(_ value: JSONValue) -> [LibraryRecord] {
        var seen = Set<String>()
        return value.array.compactMap(item).filter { record in
            let coordinates = record.playbackCoordinates
            return seen.insert(record.id + "|" + (coordinates.season.map(String.init) ?? "") + "|" + (coordinates.episode.map(String.init) ?? "")).inserted
        }
    }
    private static func identifier(_ ids: JSONValue, kind: String) -> String? {
        if let id = ids["imdb"].string, id.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { return id }
        guard let id = ids["tmdb"].textValue, !id.isEmpty, id != "0" else { return nil }; return "tmdb:\(kind):" + id
    }
    static func item(_ raw: JSONValue) -> LibraryRecord? {
        let progress = min(100, max(0, raw["progress"].numericValue ?? 0))
        guard progress.isFinite, (1...98).contains(progress) else { return nil }
        let node: JSONValue, type: String, id: String
        if raw["movie"] != .null && raw["episode"] == .null {
            node = raw["movie"]; type = "movie"; guard let found = identifier(node["ids"], kind: "movie") else { return nil }; id = found
        } else if raw["show"] != .null {
            node = raw["show"]; type = "series"; guard let found = identifier(node["ids"], kind: "tv") else { return nil }; id = found
        } else { return nil }
        let when = raw["paused_at"].string ?? "1970-01-01T00:00:00.000Z", duration = type == "movie" ? 6_300_000.0 : 2_640_000.0
        var state: [String: JSONValue] = ["timeOffset": .number((progress / 100 * duration).rounded()), "duration": .number(duration), "lastWatched": .string(when)]
        if type == "series", let season = raw["episode"]["season"].integer, let episode = raw["episode"]["number"].integer, season > 0, episode > 0 {
            state["season"] = .integer(Int64(season)); state["episode"] = .integer(Int64(episode)); state["video_id"] = .string("\(id):\(season):\(episode)")
        }
        return LibraryRecord(raw: .object(["_id": .string(id), "type": .string(type), "name": .string(node["title"].string ?? "Untitled"),
            "state": .object(state), "removed": .bool(false), "temp": .bool(false), "_ctime": .string(when), "_mtime": .string(when),
            "external": .string("trakt"), "remotePct": .number(progress / 100)]))
    }
    static func checkpoint(_ record: LibraryRecord) -> (ResumeTarget, ResumeEntry)? {
        guard record.raw["external"] == .string("trakt"), let progress = record.raw["remotePct"].numericValue else { return nil }
        let coordinates = record.playbackCoordinates
        let target = ResumeTarget(id: record.id, season: coordinates.season, episode: coordinates.episode, videoId: record.raw["state"]["video_id"].string)
        let timestamp = LibraryRecord.timestamp(record.raw["state"]["lastWatched"]) ?? 0
        return (target, .init(ms: record.raw["state"]["timeOffset"].numericValue ?? 0, t: timestamp > 0 && timestamp < Double(UInt64.max) ? UInt64(timestamp) : 0, pct: progress, source: "trakt"))
    }
}
