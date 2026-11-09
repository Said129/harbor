import Foundation
import Observation

struct MusicAudioQuality: Codable, Hashable, Sendable {
    var codec: String?
    var lossless: Bool?
    var sampleRateHz: Double?
    var bitDepth: Double?
    var bitrateKbps: Double?
}
struct MusicCollectionOrigin: Codable, Hashable, Sendable {
    let id: String
    var connectorId: String?
    var title: String?
    var artist: String?
    var artwork: String?
}
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
    var isrc: String?
    var releaseDate: String?
    var collectionOrigin: MusicCollectionOrigin?
    var quality: MusicAudioQuality?
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

struct MusicLibraryDocument: Codable, Sendable {
    var version: Int
    var records: [MusicRecord]
    var trackedFolder: MusicFolderSource?

    init(records: [MusicRecord] = [], trackedFolder: MusicFolderSource? = nil) {
        version = 1
        self.records = records
        self.trackedFolder = trackedFolder
    }

    private enum CodingKeys: String, CodingKey { case version, records, trackedFolder }

    init(from decoder: Decoder) throws {
        if var legacy = try? decoder.unkeyedContainer() {
            var records: [MusicRecord] = []
            while !legacy.isAtEnd { records.append(try legacy.decode(MusicRecord.self)) }
            self.init(records: records)
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            records: try values.decode([MusicRecord].self, forKey: .records),
            trackedFolder: try values.decodeIfPresent(MusicFolderSource.self, forKey: .trackedFolder)
        )
        version = try values.decode(Int.self, forKey: .version)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(records, forKey: .records)
        try values.encodeIfPresent(trackedFolder, forKey: .trackedFolder)
    }
}

@MainActor @Observable
final class MusicLibrary {
    let owner: String
    @ObservationIgnored private let bookmarks: any LocalLibraryBookmarks
    private(set) var records: [MusicRecord] = []
    private var trackedFolder: MusicFolderSource?
    private(set) var ready = false
    var importing: Bool { MusicImportCoordinator.shared.busy(owner) }
    var hasTrackedFolder: Bool { trackedFolder != nil }
    private(set) var revision: UInt64 = 0
    private(set) var scanning = false
    private(set) var importCompleted = 0
    private(set) var importTotal = 0
    private(set) var importMessage: String?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    var error: String?
    private var key: String { "music-library-" + EBookShelf.hash(owner) }
    init(owner: String, bookmarks: any LocalLibraryBookmarks = SystemLocalLibraryBookmarks()) {
        self.owner = owner
        self.bookmarks = bookmarks
        do {
            let saved = try KeychainStore().read(key, as: MusicLibraryDocument.self) ?? MusicLibraryDocument()
            guard Self.valid(saved) else { throw HarborError(code: "music-store") }
            records = saved.records; trackedFolder = saved.trackedFolder; ready = true
        } catch { self.error = "No se pudo recuperar tu biblioteca de Música. Los archivos se conservan." }
    }
    func importFiles(_ urls: [URL]) {
        guard ready, !importing else { return }
        guard urls.count <= 100_000 else { error = safeMessage(HarborError(code: "music-capacity")); return }
        startImport(urls, folder: nil)
    }
    func importFolder(_ url: URL) {
        guard ready, !importing else { return }
        startImport([], folder: url)
    }
    func rescanFolder() {
        guard ready, !importing, trackedFolder != nil else { return }
        startImport([], folder: nil, rescan: true)
    }
    func cancelImport() { MusicImportCoordinator.shared.cancel(owner) }
    func acquireImport(cancel: @escaping @MainActor () -> Void) throws -> UUID {
        guard ready, let token = MusicImportCoordinator.shared.acquire(owner, cancel: cancel) else { throw HarborError(code: "music-store") }
        return token
    }
    func finishImport(_ token: UUID) { MusicImportCoordinator.shared.release(owner, token: token); scanning = false }
    func commitImportedFiles(_ added: [MusicRecord], token: UUID) throws {
        guard ready, MusicImportCoordinator.shared.contains(owner, token: token) else { throw CancellationError() }
        guard !added.isEmpty else { return }
        var next = records
        var positions = Dictionary(next.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var filenames = Dictionary(next.enumerated().map { ($0.element.filename, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for record in added {
            let index = positions[record.id] ?? filenames[record.filename]
            let value = index.map { stableRecord(record, id: next[$0].id, importedAt: next[$0].importedAt) } ?? record
            if let index {
                let previous = next[index]
                next[index] = value
                if previous.filename != value.filename, filenames[previous.filename] == index { filenames[previous.filename] = nil }
                filenames[value.filename] = index
                positions[value.id] = index
            } else {
                let index = next.count
                next.append(value); positions[value.id] = index; filenames[value.filename] = index
            }
        }
        try persist(records: next, folder: trackedFolder)
        records = next; revision &+= 1
    }
    private func startImport(_ urls: [URL], folder: URL?, rescan: Bool = false) {
        guard let token = try? acquireImport(cancel: { [weak self] in self?.importTask?.cancel() }) else { return }
        scanning = folder != nil || rescan; error = nil; importMessage = nil
        importCompleted = 0; importTotal = 0
        let owner = owner
        importTask = Task { [weak self] in
            guard let self else { MusicImportCoordinator.shared.release(owner, token: token); return }
            await self.performImport(urls, folder: folder, rescan: rescan, token: token)
            self.importTask = nil
        }
    }
    private func performImport(_ urls: [URL], folder: URL?, rescan: Bool, token: UUID) async {
        defer { finishImport(token) }
        if rescan || folder != nil {
            await performFolderImport(selectedFolder: folder)
        } else {
            await performFileImport(urls)
        }
    }

    private func performFileImport(_ files: [URL]) async {
        scanning = false; importTotal = files.count
        guard !files.isEmpty else { importMessage = "No hay archivos de audio compatibles en la selección."; return }
        var nextRecords = records
        var positions = Dictionary(nextRecords.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var filenames = Dictionary(nextRecords.enumerated().map { ($0.element.filename, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var added = 0, existing = 0, failed = 0
        for url in files {
            do {
                try Task.checkCancellation()
                let imported = try await MusicFileService.shared.importFile(url, owner: owner)
                let existingIndex = positions[imported.record.id] ?? filenames[imported.record.filename]
                let previousRecord = existingIndex.map { nextRecords[$0] }
                let value = existingIndex.map { stableRecord(imported.record, id: nextRecords[$0].id, importedAt: nextRecords[$0].importedAt) } ?? imported.record
                let previousValue = existingIndex.map { nextRecords[$0] }
                if let existingIndex { nextRecords[existingIndex] = value }
                else { nextRecords.append(value) }
                do {
                    try Task.checkCancellation()
                    try persist(records: nextRecords, folder: trackedFolder)
                    if let existingIndex {
                        if let previousValue, previousValue.filename != value.filename, filenames[previousValue.filename] == existingIndex { filenames[previousValue.filename] = nil }
                        filenames[value.filename] = existingIndex; positions[value.id] = existingIndex
                    } else {
                        let index = nextRecords.count - 1
                        positions[value.id] = index; filenames[value.filename] = index
                    }
                    records = nextRecords; revision &+= 1
                    if existingIndex != nil { existing += 1 } else { added += 1 }
                    if let old = previousRecord, old.filename != value.filename {
                        try? await MusicFileService.shared.remove(old, owner: owner, keeping: nextRecords)
                    }
                } catch {
                    if let existingIndex, let previousValue { nextRecords[existingIndex] = previousValue }
                    else { nextRecords.removeLast() }
                    if imported.createdFile, filenames[imported.record.filename] == nil {
                        try? await MusicFileService.shared.remove(imported.record, owner: owner, keepingFilenames: Set(nextRecords.map(\.filename)), keepingCovers: Set(nextRecords.compactMap(\.cover)))
                    }
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

    private func performFolderImport(selectedFolder: URL?) async {
        var staged: [MusicImport] = []
        var source: MusicFolderSource
        let root: URL
        do {
            if let selectedFolder {
                root = selectedFolder
                if let trackedFolder, let resolved = try? bookmarks.resolve(trackedFolder.bookmark),
                   resolved.url.standardizedFileURL.path == root.standardizedFileURL.path {
                    source = trackedFolder
                } else {
                    source = MusicFolderSource(id: UUID().uuidString, name: root.lastPathComponent, bookmark: Data(), entries: [:], suppressedPaths: [])
                }
            } else {
                guard let trackedFolder else { throw HarborError(code: "music-folder") }
                source = trackedFolder
                root = try bookmarks.resolve(trackedFolder.bookmark).url
            }
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            try Task.checkCancellation()
            // Recreate the bookmark while the directory grant is held. This works with iOS's
            // ordinary bookmark options and does not depend on macOS security-scope flags.
            let refreshedBookmark: Data
            do { refreshedBookmark = try bookmarks.bookmark(for: root) }
            catch {
                guard selectedFolder != nil else { throw error }
                let files = try await MusicFileService.shared.scanFolderEntries(root)
                try Task.checkCancellation()
                scanning = false; importTotal = files.count
                await performFileImport(files.map(\.url))
                importMessage = (importMessage ?? "Importación completada.") + " · Se importó una vez; vuelve a elegir la carpeta para actualizarla."
                return
            }
            source.bookmark = refreshedBookmark
            source = MusicFolderSource(id: source.id, name: root.lastPathComponent, bookmark: source.bookmark,
                                       entries: source.entries, suppressedPaths: source.suppressedPaths)
            let sameSource = trackedFolder?.id == source.id
            let previousEntries = sameSource ? source.entries : [:]
            let files = try await MusicFileService.shared.scanFolderEntries(root)
            try Task.checkCancellation()
            scanning = false; importTotal = files.count
            var nextRecords = records
            var nextEntries = previousEntries
            var positions = Dictionary(nextRecords.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            var filenames = Dictionary(nextRecords.enumerated().map { ($0.element.filename, $0.offset) }, uniquingKeysWith: { first, _ in first })
            var changedRecordIDs = Set<String>()
            var processedFilenames: [String: Set<String>] = [:]
            var failed = 0
            let seen = Set(files.map(\.relativePath))
            let unchangedRecordIDs = Set(files.compactMap { file -> String? in
                guard let previous = previousEntries[file.relativePath], positions[previous.recordID] != nil,
                      MusicIncrementalScan.isUnchanged(file, from: previous) else { return nil }
                return previous.recordID
            })
            for file in files {
                try Task.checkCancellation()
                if !MusicIncrementalScan.shouldImport(path: file.relativePath, suppressed: source.suppressedPaths) {
                    nextEntries.removeValue(forKey: file.relativePath)
                    importCompleted += 1
                    continue
                }
                let previous = previousEntries[file.relativePath]
                if let previous, let index = positions[previous.recordID], MusicIncrementalScan.isUnchanged(file, from: previous) {
                    nextEntries[file.relativePath] = previous
                    processedFilenames[previous.recordID, default: []].insert(nextRecords[index].filename)
                    importCompleted += 1
                    continue
                }
                do {
                    let imported = try await MusicFileService.shared.importFile(file.url, owner: owner)
                    staged.append(imported)
                    let priorIndex = previous.flatMap { positions[$0.recordID] }
                    let priorRecord = priorIndex.map { nextRecords[$0] }
                    let hasUnchangedSibling = previous.map { unchangedRecordIDs.contains($0.recordID) } ?? false
                    let processedSiblingHasOtherContent = previous.flatMap { processedFilenames[$0.recordID] }.map {
                        $0.count > 1 || !$0.contains(imported.record.filename)
                    } ?? false
                    let priorWasChangedToOtherContent = priorIndex.map {
                        changedRecordIDs.contains(nextRecords[$0].id) && nextRecords[$0].filename != imported.record.filename
                    } ?? false
                    let splitSharedEntry = hasUnchangedSibling || processedSiblingHasOtherContent || priorWasChangedToOtherContent
                    let adoptedIndex: Int?
                    if let priorIndex, !splitSharedEntry { adoptedIndex = priorIndex }
                    else { adoptedIndex = filenames[imported.record.filename] }
                    let adopted = adoptedIndex.map { nextRecords[$0] }
                    let stableID = MusicIncrementalScan.recordID(sourceID: source.id, relativePath: file.relativePath, existingID: adopted?.id)
                    let value = stableRecord(imported.record, id: stableID, importedAt: adopted?.importedAt ?? Date())
                    if let index = positions[stableID] {
                        let old = nextRecords[index]
                        nextRecords[index] = value
                        if old.filename != value.filename, filenames[old.filename] == index { filenames[old.filename] = nil }
                        filenames[value.filename] = index
                    } else {
                        let index = nextRecords.count
                        nextRecords.append(value); positions[stableID] = index; filenames[value.filename] = index
                    }
                    if let previous, previous.recordID == stableID, priorRecord?.filename != imported.record.filename {
                        changedRecordIDs.insert(stableID)
                    }
                    if let previous { processedFilenames[previous.recordID, default: []].insert(imported.record.filename) }
                    nextEntries[file.relativePath] = MusicFolderIndexEntry(
                        recordID: stableID,
                        size: file.size,
                        modifiedAtSeconds: file.modifiedAtSeconds,
                        preserveWhenMissing: previous?.preserveWhenMissing ?? (adopted != nil)
                    )
                } catch is CancellationError { throw CancellationError() }
                catch let failure as HarborError where failure.code == "music-file" {
                    failed += 1
                    if let previous, let index = positions[previous.recordID] {
                        nextEntries[file.relativePath] = previous
                        processedFilenames[previous.recordID, default: []].insert(nextRecords[index].filename)
                    }
                }
                importCompleted += 1
            }
            try Task.checkCancellation()
            let removedPaths = MusicIncrementalScan.removedPaths(previous: Set(previousEntries.keys), seen: seen, completed: true)
            var removedIDs = Set<String>()
            for path in removedPaths {
                if let entry = nextEntries.removeValue(forKey: path), !entry.preserveWhenMissing { removedIDs.insert(entry.recordID) }
            }
            let retainedIDs = Set(nextEntries.values.map(\.recordID))
            let removedRecords = nextRecords.filter { removedIDs.contains($0.id) && !retainedIDs.contains($0.id) }
            nextRecords.removeAll { removedIDs.contains($0.id) && !retainedIDs.contains($0.id) }
            source.entries = nextEntries
            let document = MusicLibraryDocument(records: nextRecords, trackedFolder: source)
            guard Self.valid(document) else { throw HarborError(code: "music-store") }
            try Task.checkCancellation()
            try KeychainStore().write(document, key: key)
            let previousRecords = records
            records = nextRecords; trackedFolder = source; revision &+= 1
            let updated = Dictionary(nextRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            let cleanup = previousRecords.filter { old in
                guard let current = updated[old.id] else { return true }
                return old.filename != current.filename || old.cover != current.cover
            } + removedRecords
            let keepingFilenames = Set(nextRecords.map(\.filename))
            let keepingCovers = Set(nextRecords.compactMap(\.cover))
            var cleaned = Set<String>()
            for old in cleanup where cleaned.insert(old.id + "|" + old.filename).inserted {
                try? await MusicFileService.shared.remove(old, owner: owner, keepingFilenames: keepingFilenames, keepingCovers: keepingCovers)
            }
            let previousIDs = Set(previousRecords.map(\.id))
            let added = nextRecords.filter { !previousIDs.contains($0.id) }.count
            importMessage = "\(added) canciones nuevas · \(removedPaths.count) ya no están en la carpeta" + (failed > 0 ? " · \(failed) archivos no se pudieron leer" : "")
        } catch is CancellationError {
            await discardStagedImports(from: staged)
            importMessage = "Rescan cancelado. La biblioteca anterior se conserva."
        } catch {
            await discardStagedImports(from: staged)
            self.error = safeMessage(error)
            importMessage = "No se completó el rescan. La biblioteca anterior se conserva."
        }
    }

    func remove(_ record: MusicRecord) async {
        guard ready, !importing else { return }
        do {
            let next = records.filter { $0.id != record.id }
            var nextFolder = trackedFolder
            if var folder = nextFolder {
                let paths = folder.entries.filter { $0.value.recordID == record.id }.map(\.key)
                for path in paths { folder.entries.removeValue(forKey: path); folder.suppressedPaths.insert(path) }
                nextFolder = folder
            }
            try persist(records: next, folder: nextFolder); records = next; trackedFolder = nextFolder; revision &+= 1
            try await MusicFileService.shared.remove(record, owner: owner, keeping: next)
        } catch { self.error = "No se pudo completar la eliminación de este archivo." }
    }

    private func persist(records: [MusicRecord], folder: MusicFolderSource?) throws {
        let document = MusicLibraryDocument(records: records, trackedFolder: folder)
        guard Self.valid(document) else { throw HarborError(code: "music-store") }
        try KeychainStore().write(document, key: key)
    }

    private func discardStagedImports(from imports: [MusicImport]) async {
        let keepingFilenames = Set(records.map(\.filename))
        let keepingCovers = Set(records.compactMap(\.cover))
        for imported in imports where imported.createdFile && !keepingFilenames.contains(imported.record.filename) {
            try? await MusicFileService.shared.remove(imported.record, owner: owner, keepingFilenames: keepingFilenames, keepingCovers: keepingCovers)
        }
    }

    private func stableRecord(_ record: MusicRecord, id: String, importedAt: Date) -> MusicRecord {
        let old = record.local.track
        let track = MusicTrack(id: id, connectorId: old.connectorId, sourceId: old.sourceId, playbackUrl: old.playbackUrl,
                               title: old.title, artist: old.artist, album: old.album, artwork: old.artwork,
                               durationSeconds: old.durationSeconds, durationLabel: old.durationLabel, explicit: old.explicit,
                               version: old.version, mediaKind: old.mediaKind, isrc: old.isrc, releaseDate: old.releaseDate,
                               collectionOrigin: old.collectionOrigin, quality: old.quality)
        let local = LocalMusic(track: track, albumKey: record.local.albumKey, artistKey: record.local.artistKey,
                               albumArtist: record.local.albumArtist, trackNo: record.local.trackNo,
                               discNo: record.local.discNo, year: record.local.year)
        return MusicRecord(local: local, filename: record.filename, originalName: record.originalName,
                           size: record.size, importedAt: importedAt, cover: record.cover)
    }

    private static func valid(_ document: MusicLibraryDocument) -> Bool {
        guard document.version == 1, document.records.count <= 100_000,
              Set(document.records.map(\.id)).count == document.records.count,
              document.records.allSatisfy({ MusicFileService.validFilename($0.filename) && $0.local.track.sourceId == $0.filename && $0.local.track.connectorId == "local" && $0.size > 0 }) else { return false }
        if let folder = document.trackedFolder {
            let ids = Set(document.records.map(\.id))
            guard !folder.id.isEmpty, folder.id.count <= 128, !folder.name.isEmpty, !folder.bookmark.isEmpty,
                  folder.entries.count <= 100_000,
                  folder.entries.allSatisfy({ validRelativePath($0.key) && ids.contains($0.value.recordID) && $0.value.size >= 0 }),
                  folder.suppressedPaths.count <= 100_000,
                  folder.suppressedPaths.allSatisfy(validRelativePath),
                  Set(folder.entries.keys).isDisjoint(with: folder.suppressedPaths) else { return false }
        }
        return (try? JSONEncoder().encode(document).count).map { $0 <= 16 * 1024 * 1024 } == true
    }

    private static func validRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, path.count <= 4096, !path.hasPrefix("/") else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
