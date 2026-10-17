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
    private(set) var scanning = false
    private(set) var importCompleted = 0
    private(set) var importTotal = 0
    private(set) var importMessage: String?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    var error: String?
    private var key: String { "music-library-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do {
            let saved = try KeychainStore().read(key, as: [MusicRecord].self) ?? []
            guard Self.valid(saved) else { throw HarborError(code: "music-store") }
            records = saved; ready = true
        } catch { self.error = "No se pudo recuperar tu biblioteca de Música. Los archivos se conservan." }
    }
    func importFiles(_ urls: [URL]) {
        guard ready, !importing else { return }
        guard urls.count <= 20 else { error = "Selecciona hasta 20 archivos por importación."; return }
        startImport(urls, folder: nil)
    }
    func importFolder(_ url: URL) {
        guard ready, !importing else { return }
        startImport([], folder: url)
    }
    func cancelImport() { importTask?.cancel() }
    private func startImport(_ urls: [URL], folder: URL?) {
        importing = true; scanning = folder != nil; error = nil; importMessage = nil
        importCompleted = 0; importTotal = 0
        importTask = Task { [weak self] in
            guard let self else { return }
            await self.performImport(urls, folder: folder)
            self.importTask = nil
        }
    }
    private func performImport(_ urls: [URL], folder: URL?) async {
        let access = folder?.startAccessingSecurityScopedResource() ?? false
        defer {
            if access { folder?.stopAccessingSecurityScopedResource() }
            importing = false; scanning = false
        }
        let files: [URL]
        do {
            if let folder { files = try await MusicFileService.shared.scanFolder(folder) }
            else { files = urls }
            try Task.checkCancellation()
        } catch is CancellationError { importMessage = "Importación cancelada."; return }
        catch { self.error = safeMessage(error); return }
        scanning = false; importTotal = files.count
        guard !files.isEmpty else { importMessage = "No hay archivos de audio compatibles en la selección."; return }
        var added = 0, existing = 0, failed = 0
        for url in files {
            do {
                try Task.checkCancellation()
                let imported = try await MusicFileService.shared.importFile(url, owner: owner)
                let known = records.contains { $0.id == imported.record.id }
                var next = records.filter { $0.id != imported.record.id }; next.append(imported.record)
                do {
                    try Task.checkCancellation()
                    guard next.count <= 500 else { throw HarborError(code: "music-capacity") }
                    guard Self.valid(next) else { throw HarborError(code: "music-store") }
                    try KeychainStore().write(next, key: key); records = next
                    if known { existing += 1 } else { added += 1 }
                } catch {
                    if imported.createdFile { try? await MusicFileService.shared.remove(imported.record, owner: owner) }
                    throw error
                }
            } catch is CancellationError {
                importMessage = "Importación cancelada. Se conservan las \(added) canciones añadidas."
                return
            } catch {
                failed += 1; self.error = safeMessage(error)
                if let failure = error as? HarborError, ["music-capacity", "music-store"].contains(failure.code) { break }
            }
            importCompleted += 1
        }
        importMessage = "\(added) canciones añadidas · \(existing) ya estaban en tu biblioteca" + (failed > 0 ? " · \(failed) archivos no se pudieron importar" : "")
    }
    func remove(_ record: MusicRecord) async {
        guard ready, !importing else { return }
        do {
            let next = records.filter { $0.id != record.id }
            try KeychainStore().write(next, key: key); records = next
            try await MusicFileService.shared.remove(record, owner: owner)
        } catch { self.error = "No se pudo completar la eliminación de este archivo." }
    }
    private static func valid(_ records: [MusicRecord]) -> Bool {
        records.count <= 500 && Set(records.map(\.id)).count == records.count &&
        records.allSatisfy { MusicFileService.validFilename($0.filename) && $0.local.track.sourceId == $0.filename && $0.local.track.connectorId == "local" && $0.size > 0 && $0.size <= 512 * 1024 * 1024 } &&
        (try? JSONEncoder().encode(records).count).map { $0 <= 8 * 1024 * 1024 } == true
    }
}
