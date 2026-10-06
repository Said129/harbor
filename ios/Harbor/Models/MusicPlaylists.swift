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
    var error: String?
    private var key: String { "music-playlists-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do {
            let saved = try KeychainStore().read(key, as: [MusicPlaylist].self) ?? []
            guard Self.valid(saved) else { throw HarborError(code: "music-store") }
            playlists = saved; ready = true
        } catch { self.error = "No se pudieron recuperar tus listas. Los datos se conservan." }
    }
    func create(_ name: String) {
        change { values in
            let title: String = try CoreBridge.invoke(JSONEncoder().encode(JSONValue.object(["operation": .string("musicPlaylistName"), "name": .string(name)])), as: String.self)
            let now = Self.timestamp
            values.insert(MusicPlaylist(id: UUID().uuidString, name: title, createdAt: now, updatedAt: now, trackIds: [], trackAddedAt: [:]), at: 0)
        }
    }
    func rename(_ id: String, name: String) {
        change { values in
            guard let index = values.firstIndex(where: { $0.id == id }) else { throw HarborError(code: "music-store") }
            let title: String = try CoreBridge.invoke(JSONEncoder().encode(JSONValue.object(["operation": .string("musicPlaylistName"), "name": .string(name)])), as: String.self)
            values[index].name = title; values[index].updatedAt = Self.timestamp
        }
    }
    func delete(_ id: String) { change { $0.removeAll { $0.id == id } } }
    func add(_ record: MusicRecord, to id: String) {
        change { values in
            guard let index = values.firstIndex(where: { $0.id == id }) else { throw HarborError(code: "music-store") }
            guard !values[index].trackIds.contains(record.id) else { return }
            let now = Self.timestamp
            values[index].trackIds.append(record.id); values[index].trackAddedAt[record.id] = now
            values[index].updatedAt = now
        }
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
    private func change(_ mutation: (inout [MusicPlaylist]) throws -> Void) {
        guard ready else { return }
        do {
            var next = playlists; try mutation(&next)
            guard Self.valid(next) else { throw HarborError(code: "music-store") }
            next.sort { $0.updatedAt == $1.updatedAt ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : (Int64($0.updatedAt) ?? 0) > (Int64($1.updatedAt) ?? 0) }
            try KeychainStore().write(next, key: key)
            playlists = next; error = nil
        } catch { self.error = safeMessage(error) }
    }
    private static var timestamp: String { String(Int64(Date().timeIntervalSince1970 * 1000)) }
    private static func valid(_ values: [MusicPlaylist]) -> Bool {
        values.count <= 200 && Set(values.map(\.id)).count == values.count && values.allSatisfy { value in
            UUID(uuidString: value.id) != nil && !value.name.isEmpty && value.name.unicodeScalars.count <= 100 && !value.name.contains("\0") &&
            value.trackIds.count <= 500 && Set(value.trackIds).count == value.trackIds.count &&
            value.trackIds.allSatisfy { !$0.isEmpty && $0.utf8.count <= 256 && !$0.contains("\0") } &&
            value.trackAddedAt.count <= 500 && Set(value.trackAddedAt.keys).isSubset(of: Set(value.trackIds)) &&
            Int64(value.createdAt) != nil && Int64(value.updatedAt) != nil
        } && (try? JSONEncoder().encode(values).count).map { $0 <= 4 * 1024 * 1024 } == true
    }
}

enum MusicOrdering {
    static func move(_ ids: [String], track: String, to: Int) throws -> [String] {
        let fields: [String: JSONValue] = ["operation": .string("musicPlaylistOrder"), "ids": .array(ids.map(JSONValue.string)), "trackId": .string(track), "toIndex": .integer(Int64(max(0, to)))]
        return try CoreBridge.invoke(JSONEncoder().encode(JSONValue.object(fields)), as: [String].self)
    }
}
