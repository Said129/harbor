import Foundation

enum LibraryHistoryView: String, Codable, CaseIterable, Identifiable, Sendable {
    case posters, episodes
    var id: String { rawValue }
    var title: String { self == .posters ? "Posters" : "Episodes" }
}
struct LibraryHistoryEntry: Identifiable, Sendable {
    let record: LibraryRecord
    let localID: String?
    let date: Double?
    let watchedAt: Double?
    let season: Int?
    let episode: Int?
    let progress: Double
    let watched: Bool
    let durationMs: Double
    let timeOffsetMs: Double
    var id: String { record.id }
    var media: Media? { record.media }
    var episodeHint: Episode? {
        guard media?.episodic == true, let season, let episode else { return nil }
        return .init(id: record.raw["state"]["video_id"].string ?? "\(id):\(season):\(episode)", season: season, episode: episode)
    }
    var listingRecord: LibraryRecord {
        var fields = record.raw.objectValue, state = record.raw["state"].objectValue
        // Desktop groups by _mtime and displays lastWatched independently.
        state["lastWatched"] = .null; fields["state"] = .object(state)
        fields["_mtime"] = date.map(JSONValue.number) ?? .integer(0); return .init(raw: .object(fields))
    }
    static func eligible(_ record: LibraryRecord) -> Bool {
        (record.raw["removed"] != .bool(true) || record.raw["temp"] == .bool(true))
            && (record.watched || (record.raw["state"]["timeOffset"].numericValue ?? 0) > 0)
    }
    static func merge(local: [LibraryRecord], remote: [TraktLibraryItem]) -> [Self] {
        var result: [Self] = [], index: [String: Int] = [:]
        let local = local.enumerated().filter { eligible($0.element) }.sorted {
            let first = LibraryRecord.timestamp($0.element.raw["state"]["lastWatched"]) ?? LibraryRecord.timestamp($0.element.raw["_mtime"]) ?? 0
            let second = LibraryRecord.timestamp($1.element.raw["state"]["lastWatched"]) ?? LibraryRecord.timestamp($1.element.raw["_mtime"]) ?? 0
            return first == second ? $0.offset < $1.offset : first > second
        }.map(\.element)
        for record in local {
            let state = record.raw["state"], duration = state["duration"].numericValue ?? 0, offset = state["timeOffset"].numericValue ?? 0
            let ratio = duration.isFinite && offset.isFinite && duration > 0 ? min(1, max(0, offset / duration)) : 0
            let coordinates = record.playbackCoordinates
            let entry = Self(record: record, localID: record.id, date: LibraryRecord.timestamp(record.raw["_mtime"]),
                watchedAt: LibraryRecord.timestamp(state["lastWatched"]) ?? LibraryRecord.timestamp(record.raw["_mtime"]),
                season: record.media?.type == "movie" ? nil : coordinates.season, episode: record.media?.type == "movie" ? nil : coordinates.episode,
                progress: ratio, watched: record.watched || ratio >= 0.9, durationMs: duration, timeOffsetMs: offset)
            if let existing = index[record.id] { result[existing] = entry } else { index[record.id] = result.count; result.append(entry) }
        }
        for item in remote {
            guard let record = item.record(history: true), index[record.id] == nil else { continue }
            index[record.id] = result.count
            result.append(.init(record: record, localID: nil, date: LibraryRecord.timestamp(item.contextDate), watchedAt: LibraryRecord.timestamp(item.contextDate),
                season: nil, episode: nil, progress: 0, watched: false, durationMs: 0, timeOffsetMs: 0))
        }
        return result
    }
}
