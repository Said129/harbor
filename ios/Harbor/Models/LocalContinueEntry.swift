import Foundation

enum LocalContinueSource: String, Codable, Sendable { case library, local }

/// Only a real playback checkpoint may create a personal entry. Imported cloud
/// progress is a shared source and cannot identify the person who watched it.
struct LocalContinueEntry: Codable, Equatable, Sendable {
    let id: String
    let type: String
    let name: String
    var poster: String?
    var background: String?
    var isAnime: Bool?
    var source: LocalContinueSource?
    var season: Int?
    var episode: Int?
    var videoId: String?
    let positionMs: Double
    let durationMs: Double
    let t: UInt64
    var valid: Bool {
        !id.isEmpty && id.utf8.count <= 2_048 && id.rangeOfCharacter(from: .controlCharacters) == nil
            && ["movie", "series"].contains(type) && name.utf8.count <= 4_096
            && positionMs.isFinite && positionMs >= 0 && durationMs.isFinite && durationMs >= 0
            && (season ?? 0) >= 0 && (episode ?? 1) > 0 && (videoId?.utf8.count ?? 0) <= 4_096
            && (poster?.utf8.count ?? 0) <= 16_384 && (background?.utf8.count ?? 0) <= 16_384
    }
    static func playback(_ media: Media, target: ResumeTarget, snapshot: ResumeSnapshot, source: LocalContinueSource) -> Self? {
        guard media.id == target.id, ["movie", "series", "anime"].contains(media.type), !media.id.hasPrefix("iptv:") else { return nil }
        let value = Self(id: media.id, type: media.type == "anime" ? "series" : media.type, name: media.name, poster: media.poster, background: media.background,
            isAnime: AnimeLibraryDetection.hasDirectEvidence(media), source: source, season: target.season, episode: target.episode, videoId: target.videoId,
            positionMs: snapshot.positionMs, durationMs: snapshot.durationMs, t: snapshot.timestampMs)
        return value.valid ? value : nil
    }
    var record: LibraryRecord {
        let date = Date(timeIntervalSince1970: Double(t) / 1_000).ISO8601Format(.init(includingFractionalSeconds: true))
        var state: [String: JSONValue] = ["timeOffset": .number(positionMs), "duration": .number(durationMs),
            "flaggedWatched": .integer(durationMs > 0 && positionMs / durationMs >= 0.9 ? 1 : 0), "lastWatched": .string(date)]
        if let season { state["season"] = .integer(Int64(season)) }
        if let episode { state["episode"] = .integer(Int64(episode)) }
        if let videoId { state["video_id"] = .string(videoId) }
        else if let season, let episode { state["video_id"] = .string("\(id):\(season):\(episode)") }
        var fields: [String: JSONValue] = ["_id": .string(id), "type": .string(type), "name": .string(name), "state": .object(state),
            "removed": .bool(false), "temp": .bool(false), "_ctime": .string(date), "_mtime": .string(date), "local": .bool(true)]
        if let poster { fields["poster"] = .string(poster) }; if let background { fields["background"] = .string(background) }
        if let isAnime { fields["isAnime"] = .bool(isAnime) }; if let source { fields["nativeSource"] = .string(source.rawValue) }
        return LibraryRecord(raw: .object(fields))
    }
}

struct LocalContinueDocument: Codable, Equatable, Sendable {
    var version = 1
    var entries: [String: LocalContinueEntry] = [:]
    private var order: [String] = []
    init() { }
    var valid: Bool {
        version == 1 && entries.count <= 60 && entries.allSatisfy { $0.key == $0.value.id && $0.value.valid }
            && order.count == entries.count && Set(order) == Set(entries.keys)
    }
    // Desktop uses Object.values: canonical array-index keys enumerate before
    // other ids, even when they were inserted later. Equal timestamps retain it.
    private var insertionOrder: [LocalContinueEntry] {
        func index(_ key: String) -> UInt64? {
            guard let value = UInt64(key), value < UInt64(UInt32.max), String(value) == key else { return nil }; return value
        }
        let numeric = order.compactMap { key -> (String, UInt64)? in index(key).map { (key, $0) } }.sorted { $0.1 < $1.1 }.map(\.0)
        return (numeric + order.filter { index($0) == nil }).compactMap { entries[$0] }
    }
    mutating func remove(_ id: String) -> Bool {
        guard entries.removeValue(forKey: id) != nil else { return false }
        order.removeAll { $0 == id }; return true
    }
    mutating func save(_ entry: LocalContinueEntry) throws {
        guard entry.valid else { throw HarborError(code: "local-continue-entry") }
        if entry.type == "movie", entry.durationMs > 0, entry.positionMs / entry.durationMs >= 0.92 { _ = remove(entry.id) }
        else {
            if entries[entry.id] == nil { order.append(entry.id) }
            entries[entry.id] = entry
            let oldest = insertionOrder.enumerated().sorted { $0.element.t == $1.element.t ? $0.offset < $1.offset : $0.element.t < $1.element.t }
            for value in oldest.prefix(max(0, entries.count - 60)) { _ = remove(value.element.id) }
        }
    }
    var sorted: [LocalContinueEntry] {
        insertionOrder.enumerated().sorted { $0.element.t == $1.element.t ? $0.offset < $1.offset : $0.element.t > $1.element.t }.map(\.element)
    }
}

struct LocalContinueSnapshot: Sendable {
    let personal: LocalContinueDocument
    let shared: LocalContinueDocument
    let personalRecords: [LibraryRecord]
    let sharedRecords: [LibraryRecord]
    init(personal: LocalContinueDocument = .init(), shared: LocalContinueDocument = .init()) {
        self.personal = personal; self.shared = shared
        personalRecords = personal.sorted.map(\.record); sharedRecords = shared.sorted.map(\.record)
    }
}
