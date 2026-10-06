import Foundation
import Observation

struct MusicTrack: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let connectorId: String?
    let sourceId: String?
    let playbackUrl: String?
    let title: String
    let artist: String
    let album: String?
    let artwork: String
    let durationSeconds: UInt64
    let durationLabel: String
    var explicit: Bool?
    var version: String?
    var mediaKind: String?
}
struct LocalMusic: Codable, Identifiable, Hashable, Sendable {
    let track: MusicTrack
    let albumKey: String?
    let artistKey: String
    let albumArtist: String?
    let trackNo: UInt32?
    let discNo: UInt32?
    let year: UInt32?
    var id: String { track.id }
}
struct MusicRecord: Codable, Identifiable, Hashable, Sendable {
    let local: LocalMusic
    let filename: String
    let originalName: String
    let size: Int64
    let importedAt: Date
    var cover: String?
    var id: String { local.id }
}
struct MusicImport: Sendable {
    let record: MusicRecord
    let createdFile: Bool
}

@MainActor @Observable
final class MusicLibrary {
    let owner: String
    private(set) var records: [MusicRecord] = []
    private(set) var ready = false
    private(set) var importing = false
    var error: String?
    private var key: String { "music-library-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do {
            let saved = try KeychainStore().read(key, as: [MusicRecord].self) ?? []
            guard Self.valid(saved) else { throw HarborError(code: "music-store") }
            records = saved; ready = true
        } catch { error = "No se pudo recuperar tu biblioteca de Música. Los archivos se conservan." }
    }
    func importFiles(_ urls: [URL]) async {
        guard ready, !importing else { return }
        guard urls.count <= 20 else { error = "Selecciona hasta 20 archivos por importación."; return }
        importing = true; error = nil
        defer { importing = false }
        for url in urls.prefix(20) {
            do {
                try Task.checkCancellation()
                let imported = try await MusicFileService.shared.importFile(url, owner: owner)
                var next = records.filter { $0.id != imported.record.id }; next.append(imported.record)
                do {
                    guard Self.valid(next) else { throw HarborError(code: "music-store") }
                    try KeychainStore().write(next, key: key); records = next
                } catch {
                    if imported.createdFile { try? await MusicFileService.shared.remove(imported.record, owner: owner) }
                    throw error
                }
            } catch is CancellationError { return }
            catch { self.error = safeMessage(error) }
        }
    }
    func remove(_ record: MusicRecord) async {
        guard ready, !importing else { return }
        do {
            let next = records.filter { $0.id != record.id }
            try KeychainStore().write(next, key: key); records = next
            try await MusicFileService.shared.remove(record, owner: owner)
        } catch { error = "No se pudo completar la eliminación de este archivo." }
    }
    private static func valid(_ records: [MusicRecord]) -> Bool {
        records.count <= 500 && Set(records.map(\.id)).count == records.count &&
        records.allSatisfy { MusicFileService.validFilename($0.filename) && $0.local.track.sourceId == $0.filename && $0.local.track.connectorId == "local" && $0.size > 0 && $0.size <= 512 * 1024 * 1024 } &&
        (try? JSONEncoder().encode(records).count).map { $0 <= 8 * 1024 * 1024 } == true
    }
}
