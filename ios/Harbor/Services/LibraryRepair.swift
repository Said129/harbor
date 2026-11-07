import Foundation

/// What the repair would rewrite, counted as Desktop's `RepairResult` counts it.
struct LibraryRepairPlan: Equatable, Sendable {
    let total: Int
    let alreadyClean: Int
    let unrepairable: Int
    /// The normalized records to write, in library order.
    let repairs: [JSONValue]

    var needsRepair: Int { repairs.count }
}

/// Desktop's Stremio library repair (`src/lib/stremio-library-repair.ts`): every library record is rewritten to the
/// shape Stremio's app reads. Pure: the caller supplies the records and decides whether to write the plan.
///
/// Harbor keeps keys Desktop drops (its `native...` fields, `imdb_id`, `external`): dropping them would erase data
/// that only Harbor reads. Records are compared by value, not by JSON text, so key order does not count as a change.
enum LibraryRepair {
    /// Desktop's `ANIME_CLOUD_ID`: anime saved under a cloud id is left alone unless it is removed.
    static let animeCloudPattern = "^(kitsu|mal|anilist|anidb):"
    /// Desktop writes 25 records per `datastorePut`.
    static let batchSize = 25

    static let topLevelFields: Set<String> = ["_id", "name", "type", "poster", "posterShape", "removed", "temp", "_ctime", "_mtime", "state", "behaviorHints"]
    static let stateFields: Set<String> = ["lastWatched", "timeWatched", "timeOffset", "overallTimeWatched", "timesWatched", "flaggedWatched",
                                           "duration", "video_id", "videoId", "watched", "lastVidReleased", "noNotif"]
    static let hintFields: Set<String> = ["defaultVideoId", "featuredVideoId", "hasScheduledVideos"]
    static let numberFields = ["timeWatched", "timeOffset", "overallTimeWatched", "timesWatched", "flaggedWatched", "duration"]

    /// Desktop's `repairStremioLibrary` decisions, without the network.
    static func plan(_ records: [JSONValue], now: Date = Date()) -> LibraryRepairPlan {
        var repairs: [JSONValue] = []
        var unrepairable = 0
        for raw in records {
            guard let normalized = normalize(raw, now: now) else {
                unrepairable += 1
                continue
            }
            if isCloudAnime(normalized) { continue }
            if normalized != raw { repairs.append(normalized) }
        }
        let clean = records.count - repairs.count - unrepairable
        return LibraryRepairPlan(total: records.count, alreadyClean: clean, unrepairable: unrepairable, repairs: repairs)
    }

    /// The writes in order, 25 to a batch.
    static func batches(_ repairs: [JSONValue]) -> [[JSONValue]] {
        stride(from: 0, to: repairs.count, by: batchSize).map { start in
            Array(repairs[start..<min(start + batchSize, repairs.count)])
        }
    }

    /// Desktop's `normalizeItem`: nil when the record is not an object or has no `_id`.
    static func normalize(_ raw: JSONValue, now: Date = Date()) -> JSONValue? {
        guard case .object(let source) = raw, let id = raw["_id"].string, !id.isEmpty else { return nil }
        var out = unknownFields(source, reserved: topLevelFields)
        out["_id"] = .string(id)
        out["name"] = .string(raw["name"].string ?? "")
        out["type"] = .string(raw["type"].string ?? "movie")
        out["poster"] = optionalString(raw["poster"])
        out["posterShape"] = .string(posterShape(raw["posterShape"]))
        out["removed"] = .bool(raw["removed"] == .bool(true))
        out["temp"] = .bool(raw["temp"] == .bool(true))
        out["_ctime"] = optionalString(raw["_ctime"])
        out["_mtime"] = modifiedTime(raw["_mtime"], now: now)
        out["state"] = .object(normalizedState(raw["state"]))
        out["behaviorHints"] = .object(normalizedHints(raw["behaviorHints"]))
        return .object(out)
    }

    private static func isCloudAnime(_ record: JSONValue) -> Bool {
        guard let id = record["_id"].string, id.range(of: animeCloudPattern, options: .regularExpression) != nil else { return false }
        return record["removed"] != .bool(true)
    }

    private static func normalizedState(_ value: JSONValue) -> [String: JSONValue] {
        var out = unknownFields(value.objectValue, reserved: stateFields)
        out["lastWatched"] = optionalString(value["lastWatched"])
        for field in numberFields { out[field] = number(value[field]) }
        out["video_id"] = value["video_id"].string.map { JSONValue.string($0) } ?? optionalString(value["videoId"])
        out["watched"] = watched(value["watched"])
        out["lastVidReleased"] = optionalString(value["lastVidReleased"])
        out["noNotif"] = .bool(value["noNotif"] == .bool(true))
        return out
    }

    private static func normalizedHints(_ value: JSONValue) -> [String: JSONValue] {
        var out = unknownFields(value.objectValue, reserved: hintFields)
        out["defaultVideoId"] = optionalString(value["defaultVideoId"])
        out["featuredVideoId"] = optionalString(value["featuredVideoId"])
        out["hasScheduledVideos"] = .bool(value["hasScheduledVideos"] == .bool(true))
        return out
    }

    private static func unknownFields(_ source: [String: JSONValue], reserved: Set<String>) -> [String: JSONValue] {
        source.filter { !reserved.contains($0.key) }
    }

    private static func optionalString(_ value: JSONValue) -> JSONValue {
        value.string.map { JSONValue.string($0) } ?? .null
    }

    private static func posterShape(_ value: JSONValue) -> String {
        let shapes = ["square", "landscape", "poster"]
        if let text = value.string, shapes.contains(text) { return text }
        return "poster"
    }

    private static func modifiedTime(_ value: JSONValue, now: Date) -> JSONValue {
        if let text = value.string { return .string(text) }
        return .string(ContinueDismissalAction.iso(now.timeIntervalSince1970 * 1_000))
    }

    /// Desktop's `asNumber`: a finite number is kept as it was sent, anything else becomes 0.
    private static func number(_ value: JSONValue) -> JSONValue {
        switch value {
        case .integer, .unsigned: return value
        case .number(let found): return found.isFinite ? value : .integer(0)
        default: return .integer(0)
        }
    }

    /// Desktop's `normalizeWatched`: `id:...:season:episode`, where the second-to-last part starts with a number like parseInt.
    private static func watched(_ value: JSONValue) -> JSONValue {
        guard let text = value.string, !text.isEmpty else { return .null }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return .null }
        var part = parts[parts.count - 2]
        if let first = part.first, first == "-" || first == "+" { part = part.dropFirst() }
        guard let lead = part.first, lead.isASCII, lead.isNumber else { return .null }
        return .string(text)
    }
}
