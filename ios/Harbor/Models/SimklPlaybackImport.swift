import Foundation

/// Desktop 0.9.132 simkl/playback.ts: entry anime ids use entry coordinates;
/// franchise ids require the explicit TVDB season/episode mapping.
enum SimklPlaybackImport {
    static func items(_ value: JSONValue) -> [LibraryRecord] {
        var seen = Set<String>()
        return value.array.compactMap(item).filter { record in
            let coordinates = record.playbackCoordinates
            return seen.insert(record.id + "|" + (coordinates.season.map(String.init) ?? "") + "|" + (coordinates.episode.map(String.init) ?? "")).inserted
        }
    }
    private static func movieID(_ ids: JSONValue) -> String? {
        if let id = ids["imdb"].string, id.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { return id }
        return ids["tmdb"].textValue.flatMap { $0.isEmpty || $0 == "0" ? nil : "tmdb:movie:" + $0 }
    }
    private static func seriesID(_ ids: JSONValue) -> String? {
        if let id = movieID(ids) { return id.replacingOccurrences(of: "tmdb:movie:", with: "tmdb:tv:") }
        for key in ["mal", "kitsu"] { if let id = ids[key].integer, id > 0 { return "\(key):\(id)" } }
        return nil
    }
    static func item(_ raw: JSONValue) -> LibraryRecord? {
        let progress = min(100, max(0, raw["progress"].numericValue ?? 0))
        guard progress.isFinite, progress >= 1, progress <= 98 else { return nil }
        let when: String
        if let paused = raw["paused_at"].string { when = paused }
        else if let watched = raw["watched_at"].string { when = watched }
        else { when = "1970-01-01T00:00:00.000Z" }
        if raw["movie"] != .null {
            guard let id = movieID(raw["movie"]["ids"]) else { return nil }
            return build(id, type: "movie", node: raw["movie"], progress: progress, when: when)
        }
        let anime = raw["anime"] != .null && raw["show"] == .null
        if anime, raw["episode"] == .null, let id = movieID(raw["anime"]["ids"]) {
            return build(id, type: "movie", node: raw["anime"], progress: progress, when: when, anime: true)
        }
        let node = raw["show"] != .null ? raw["show"] : raw["anime"], ids = node["ids"]
        var nativeID: String?
        if anime { for key in ["kitsu", "mal", "anilist"] { if let id = ids[key].integer, id > 0 { nativeID = "\(key):\(id)"; break } } }
        guard let id = nativeID ?? seriesID(ids) else { return nil }
        let mapped = anime && nativeID == nil, episode = raw["episode"]
        let season: Int?, number: Int?
        if mapped { season = episode["tvdb_season"].integer; number = episode["tvdb_number"].integer }
        else { season = episode["season"].integer ?? (anime ? 1 : nil); number = episode["number"].integer ?? episode["episode"].integer }
        guard !mapped || (season != nil && number != nil) else { return nil }
        return build(id, type: "series", node: node, progress: progress, when: when, season: season, episode: number, anime: anime)
    }
    private static func build(_ id: String, type: String, node: JSONValue, progress: Double, when: String, season: Int? = nil, episode: Int? = nil, anime: Bool = false) -> LibraryRecord {
        let duration = type == "movie" ? 6_300_000.0 : 2_640_000.0
        var state: [String: JSONValue] = ["timeOffset": .number((progress / 100 * duration).rounded()), "duration": .number(duration), "lastWatched": .string(when)]
        if type == "series", let season, let episode, season > 0, episode > 0 {
            state["season"] = .integer(Int64(season)); state["episode"] = .integer(Int64(episode)); state["video_id"] = .string("\(id):\(season):\(episode)")
        }
        var fields: [String: JSONValue] = ["_id": .string(id), "type": .string(type), "name": .string(node["title"].string ?? "Untitled"),
            "state": .object(state), "removed": .bool(false), "temp": .bool(false), "_ctime": .string(when), "_mtime": .string(when),
            "external": .string("simkl"), "remotePct": .number(progress / 100)]
        if type == "series" || anime { fields["isAnime"] = .bool(anime) }
        return LibraryRecord(raw: .object(fields))
    }
    static func checkpoint(_ record: LibraryRecord) -> (ResumeTarget, ResumeEntry)? {
        guard record.raw["external"] == .string("simkl"), let progress = record.raw["remotePct"].numericValue else { return nil }
        let coordinates = record.playbackCoordinates
        let target = ResumeTarget(id: record.id, season: coordinates.season, episode: coordinates.episode, videoId: record.raw["state"]["video_id"].string)
        let timestamp = LibraryRecord.timestamp(record.raw["state"]["lastWatched"]) ?? 0
        return (target, .init(ms: record.raw["state"]["timeOffset"].numericValue ?? 0, t: timestamp > 0 && timestamp < Double(UInt64.max) ? UInt64(timestamp) : 0, pct: progress, source: "simkl"))
    }
}
