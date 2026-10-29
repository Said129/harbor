import Foundation
import Observation

struct MusicPlaylist: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    let createdAt: String
    var updatedAt: String
    var trackIds: [String]
    var trackAddedAt: [String: String]
}

@MainActor @Observable
final class MusicPlaylistStore {
    let owner: String
    private(set) var playlists: [MusicPlaylist] = []
    private(set) var ready = false
    private(set) var tracks: [String: MusicTrack] = [:]
    var error: String?
    @ObservationIgnored private let persistence: any MusicPlaylistPersistence
    init(owner: String, persistence: (any MusicPlaylistPersistence)? = nil) {
        self.owner = owner
        self.persistence = persistence ?? KeychainMusicPlaylistPersistence()
        do {
            let saved = try (self.persistence.read(owner: owner) ?? MusicPlaylistDocument()).validated()
            playlists = saved.playlists; tracks = saved.tracks; ready = true
        } catch { self.error = "No se pudieron recuperar tus listas. Los datos se conservan." }
    }
    @discardableResult func create(_ name: String) -> MusicPlaylist? {
        var createdID: String?
        let saved = change { values in
            let base = try Self.name(name)
            let names = Set(values.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: .current) })
            var title = base
            var suffix = 1
            while names.contains(title.lowercased(with: .current)) { title = base + " (\(suffix))"; suffix += 1 }
            title = try Self.name(title)
            let now = Self.timestamp
            let id = UUID().uuidString; createdID = id
            values.insert(MusicPlaylist(id: id, name: title, createdAt: now, updatedAt: now, trackIds: [], trackAddedAt: [:]), at: 0)
        }
        return saved ? playlists.first { $0.id == createdID } : nil
    }
    func rename(_ id: String, name: String) {
        change { values in
            guard let index = values.firstIndex(where: { $0.id == id }) else { throw HarborError(code: "music-store") }
            let title = try Self.name(name)
            guard !values.contains(where: { $0.id != id && $0.name.compare(title, options: .caseInsensitive, locale: .current) == .orderedSame }) else { throw HarborError(code: "music-playlist-duplicate-name") }
            values[index].name = title; values[index].updatedAt = Self.timestamp
        }
    }
    func delete(_ id: String) { change { $0.removeAll { $0.id == id } } }
    func add(_ record: MusicRecord, to id: String) {
        add([record.local.track], to: id)
    }
    @discardableResult func remember(_ recordings: [MusicTrack]) -> Bool {
        guard ready else { return false }
        if error == nil, recordings.allSatisfy({ track in
            guard let previous = tracks[track.id] else { return false }
            return track.playlistRecording(replacing: previous) == previous
        }) { return true }
        return change(upserting: recordings) { _ in }
    }
    @discardableResult func add(_ recordings: [MusicTrack], to id: String) -> MusicPlaylist? {
        let saved = change(upserting: recordings) { values in
            guard let index = values.firstIndex(where: { $0.id == id }) else { throw HarborError(code: "music-store") }
            let now = Self.timestamp
            var known = Set(values[index].trackIds)
            for track in recordings where known.insert(track.id).inserted {
                values[index].trackIds.append(track.id); values[index].trackAddedAt[track.id] = now
            }
            values[index].updatedAt = now
        }
        return saved ? playlists.first { $0.id == id } : nil
    }
    func recordings(in id: String, local: [MusicRecord] = []) -> [MusicTrack] {
        let imported = Dictionary(local.map { ($0.id, $0.local.track) }, uniquingKeysWith: { first, _ in first })
        return (playlists.first { $0.id == id }?.trackIds ?? []).compactMap { tracks[$0] ?? imported[$0] }
    }
    func remove(_ track: String, from id: String) {
        change { values in
            guard let index = values.firstIndex(where: { $0.id == id }) else { throw HarborError(code: "music-store") }
            values[index].trackIds.removeAll { $0 == track }; values[index].trackAddedAt[track] = nil
            values[index].updatedAt = Self.timestamp
        }
    }
    func move(_ track: String, in id: String, to: Int) {
        change { values in
            guard let index = values.firstIndex(where: { $0.id == id }) else { throw HarborError(code: "music-store") }
            values[index].trackIds = try MusicOrdering.move(values[index].trackIds, track: track, to: to)
            values[index].updatedAt = Self.timestamp
        }
    }
    @discardableResult private func change(upserting recordings: [MusicTrack] = [], _ mutation: (inout [MusicPlaylist]) throws -> Void) -> Bool {
        guard ready else { return false }
        do {
            var next = MusicPlaylistDocument(playlists: playlists, tracks: tracks)
            try mutation(&next.playlists)
            for track in recordings { next.tracks[track.id] = track.playlistRecording(replacing: next.tracks[track.id]) }
            next = try next.validated()
            next.playlists.sort { $0.updatedAt == $1.updatedAt ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : (Int64($0.updatedAt) ?? 0) > (Int64($1.updatedAt) ?? 0) }
            try persistence.write(next, owner: owner)
            playlists = next.playlists; tracks = next.tracks; error = nil; return true
        } catch { self.error = safeMessage(error); return false }
    }
    private static var timestamp: String { String(Int64(Date().timeIntervalSince1970 * 1000)) }
    private static func name(_ input: String) throws -> String {
        try CoreBridge.invoke(JSONEncoder().encode(JSONValue.object(["operation": .string("musicPlaylistName"), "name": .string(input)])), as: String.self)
    }
}

enum MusicOrdering {
    static func move(_ ids: [String], track: String, to: Int) throws -> [String] {
        let fields: [String: JSONValue] = ["operation": .string("musicPlaylistOrder"), "ids": .array(ids.map(JSONValue.string)), "trackId": .string(track), "toIndex": .integer(Int64(max(0, to)))]
        return try CoreBridge.invoke(JSONEncoder().encode(JSONValue.object(fields)), as: [String].self)
    }
}
