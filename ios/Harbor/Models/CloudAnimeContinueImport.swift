import Foundation

enum CloudAnimeContinueImport {
    static func owns(_ id: String) -> Bool { ["kitsu", "mal", "anilist", "anidb"].contains(String(id.split(separator: ":").first ?? "")) && id.contains(":") }
    static func entry(_ record: LibraryRecord, existing: LocalContinueEntry?, now: Double) -> LocalContinueEntry? {
        let raw = record.raw, state = raw["state"]
        guard owns(record.id), !(raw["removed"] == .bool(true) && raw["temp"] != .bool(true)),
              (state["timeOffset"].numericValue ?? 0) > 0 || state["video_id"].string?.isEmpty == false,
              let t = modifiedTime(raw["_mtime"]), t.isFinite, t > 0, t < Double(UInt64.max), now - t <= 45 * 86_400_000,
              existing == nil || Double(existing!.t) < t else { return nil }
        let coordinates = record.playbackCoordinates
        let value = LocalContinueEntry(id: record.id, type: raw["type"].string == "movie" ? "movie" : "series", name: raw["name"].string ?? "",
            poster: raw["poster"].string, background: raw["background"].string,
            season: coordinates.season, episode: coordinates.episode, videoId: state["video_id"].string,
            positionMs: state["timeOffset"].numericValue ?? 0, durationMs: state["duration"].numericValue ?? 0, t: UInt64(t))
        return value.valid ? value : nil
    }
    private static func modifiedTime(_ value: JSONValue) -> Double? {
        if let number = value.numericValue { return number }
        return value.string.flatMap { ISO8601DateParser.shared.date($0) }.map { $0.timeIntervalSince1970 * 1_000 }
    }
}
