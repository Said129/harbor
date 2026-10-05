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
    var watched: Bool { (raw["state"]["flaggedWatched"].numericValue ?? 0) > 0 }
    var progress: Double {
        let duration = raw["state"]["duration"].numericValue ?? 0
        return duration > 0 ? min(1, max(0, (raw["state"]["timeOffset"].numericValue ?? 0) / duration)) : 0
    }
    var continuing: Bool { !watched && (raw["state"]["timeOffset"].numericValue ?? 0) > 0 && (bookmarked || raw["temp"] == .bool(true)) }
    var modified: String { raw["_mtime"].string ?? "" }
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
