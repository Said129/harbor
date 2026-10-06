import Foundation
import Observation

struct FavoriteMedia: Codable, Sendable {
    let media: Media
    let addedAt: Date
    var valid: Bool {
        !media.id.isEmpty && media.id.utf8.count <= 4_096 && !media.name.isEmpty && media.name.utf8.count <= 1_024
            && addedAt.timeIntervalSince1970.isFinite && addedAt.timeIntervalSince1970 >= 0
    }
    var record: LibraryRecord {
        var fields: [String: JSONValue] = ["_id": .string(media.id), "type": .string(media.type), "name": .string(media.name), "temp": .bool(true), "_ctime": .string(ISO8601DateFormatter().string(from: addedAt))]
        for (key, value) in [("poster", media.poster), ("background", media.background), ("logo", media.logo), ("releaseInfo", media.releaseInfo)] {
            if let value { fields[key] = .string(value) }
        }
        return LibraryRecord(raw: .object(fields))
    }
}

/// Desktop media favorites are distinct from the Stremio watchlist.
@MainActor @Observable
final class MediaFavorites {
    let owner: String
    private(set) var entries: [FavoriteMedia] = []
    private(set) var ready = false
    private(set) var error: String?
    private var key: String { "media-favorites-" + EBookShelf.hash(owner) }
    init(owner: String) { self.owner = owner; reload() }
    func reload() {
        ready = false
        do {
            let saved = try KeychainStore().read(key, as: [FavoriteMedia].self) ?? []
            guard saved.count <= 1_000, saved.allSatisfy(\.valid), Set(saved.map { $0.media.identity }).count == saved.count else { throw HarborError(code: "favorite-store") }
            entries = saved; ready = true; error = nil
        } catch { self.error = "No se pudieron recuperar los favoritos de este iPhone. Los datos guardados se conservan." }
    }
    func contains(_ media: Media) -> Bool { entries.contains { $0.media.identity == media.identity } }
    func toggle(_ media: Media) {
        guard ready else { return }
        var next = entries.filter { $0.media.identity != media.identity }
        if !contains(media) {
            // Save the actual identity/cover, then reload full metadata when opened.
            var compact = Media(id: media.id, type: media.type, name: media.name)
            compact.poster = media.poster; compact.background = media.background; compact.logo = media.logo; compact.releaseInfo = media.releaseInfo
            next.append(FavoriteMedia(media: compact, addedAt: Date()))
        }
        do {
            guard next.count <= 1_000, next.allSatisfy(\.valid), try JSONEncoder().encode(next).count <= 1024 * 1024 else { throw HarborError(code: "favorite-store") }
            try KeychainStore().write(next, key: key); entries = next; error = nil
        } catch { self.error = "No se pudo guardar el favorito. Los favoritos anteriores se conservan." }
    }
}
