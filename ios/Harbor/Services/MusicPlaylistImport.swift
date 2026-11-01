import Foundation

struct MusicPlaylistImportDraft: Sendable {
    let owner: String
    let filename: String
    let tracks: [MusicTrack]
    let owned: [String: MusicRecord]
    var needsFolder: Bool { tracks.contains { MusicPlaylistFiles.local($0) && owned[$0.id] == nil } }
    var suggestedName: String {
        let file = filename.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        return file.replacingOccurrences(of: #"\.m3u8?$"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
enum MusicPlaylistImportError: Error { case file, folder, missing, storage }

actor MusicPlaylistFiles {
    static let shared = MusicPlaylistFiles()
    nonisolated static func local(_ track: MusicTrack) -> Bool { track.connectorId == "local" || track.playbackUrl.flatMap { URL(string: $0) }?.isFileURL == true }
    nonisolated static func location(_ track: MusicTrack) -> String {
        let raw = track.playbackUrl ?? track.sourceId ?? ""
        return URL(string: raw).flatMap { $0.isFileURL ? $0.path : nil } ?? raw
    }
    func read(_ url: URL, owner: String, records: [MusicRecord]) async throws -> MusicPlaylistImportDraft {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, ["m3u", "m3u8"].contains(url.pathExtension.lowercased()) else { throw MusicPlaylistImportError.file }
        guard let size = values.fileSize, size <= 5 * 1024 * 1024 else { throw HarborError(code: "music-m3u-size") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try await parse(data, base: url.deletingLastPathComponent(), filename: url.lastPathComponent, owner: owner, records: records)
    }
    func parse(_ data: Data, base: URL, filename: String, owner: String, records: [MusicRecord]) async throws -> MusicPlaylistImportDraft {
        try Task.checkCancellation()
        guard data.count <= 5 * 1024 * 1024 else { throw HarborError(code: "music-m3u-size") }
        // URL-safe unpadded base64 fits the existing 8 MB ABI even at the 5 MB
        // source limit and retains Rust's original lossy UTF-8 interpretation.
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let tracks: [MusicTrack] = try await CoreBridge().call("musicImportM3U", ["contentBase64": .string(encoded), "basePath": .string(base.path)])
        var owned: [String: MusicRecord] = [:]
        let local = tracks.filter(Self.local)
        if !local.isEmpty {
            let root = try MusicFileService.root(owner: owner)
            let files = Dictionary(records.map { (root.appendingPathComponent($0.filename).standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
            for track in local {
                let path = URL(fileURLWithPath: Self.location(track)).standardizedFileURL.path
                if let record = files[path], (try? MusicFileService.file(record, owner: owner)) != nil { owned[track.id] = record }
            }
        }
        try Task.checkCancellation()
        return .init(owner: owner, filename: filename, tracks: tracks, owned: owned)
    }
    func folder(_ url: URL) async throws -> MusicPlaylistLocalIndex {
        let files = try await MusicFileService.shared.scanFolder(url)
        return try MusicPlaylistLocalIndex(root: url, files: files)
    }
}

struct MusicPlaylistLocalIndex: Sendable {
    private let entries: [String: [(URL, String)]]
    init(root: URL, files: [URL]) throws {
        let prefix = root.standardizedFileURL.path + (root.path.hasSuffix("/") ? "" : "/")
        var entries: [String: [(URL, String)]] = [:]
        for file in files {
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { throw MusicPlaylistImportError.folder }
            let relative = Self.key(String(path.dropFirst(prefix.count)))
            entries[Self.key(file.lastPathComponent), default: []].append((file, relative))
        }
        self.entries = entries
    }
    private static func key(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "/").decomposedStringWithCanonicalMapping.lowercased() }
    func file(_ track: MusicTrack) throws -> URL {
        let location = Self.key(MusicPlaylistFiles.location(track))
        let name = location.split(separator: "/").last.map(String.init) ?? ""
        let candidates = entries[name] ?? []
        let exact = candidates.filter { location == $0.1 || location.hasSuffix("/" + $0.1) }
        if exact.count == 1 { return exact[0].0 }
        if candidates.count == 1 { return candidates[0].0 }
        throw MusicPlaylistImportError.missing
    }
}

@MainActor enum MusicPlaylistImporter {
    static func run(_ draft: MusicPlaylistImportDraft, name: String, folder: URL?, library: MusicLibrary, store: MusicPlaylistStore,
                    allowed: @escaping @MainActor () -> Bool, cancel: @escaping @MainActor () -> Void,
                    progress: @escaping @MainActor (Int, Int) -> Void) async throws -> MusicPlaylist {
        func validate() throws {
            try Task.checkCancellation()
            guard allowed(), draft.owner == library.owner, store.owner == library.owner, library.ready, store.ready else { throw CancellationError() }
        }
        try validate()
        let _: String = try await CoreBridge().call("musicPlaylistName", ["name": .string(name)])
        try validate()
        guard !draft.needsFolder || folder != nil else { throw MusicPlaylistImportError.folder }
        let token = try library.acquireImport(cancel: cancel)
        let access = folder?.startAccessingSecurityScopedResource() ?? false
        defer { if access { folder?.stopAccessingSecurityScopedResource() }; library.finishImport(token) }
        var staged: [MusicImport] = [], files: [URL: MusicImport] = [:], recordings: [MusicTrack] = []
        var committed = false
        do {
            let index: MusicPlaylistLocalIndex?
            if draft.needsFolder, let folder { index = try await MusicPlaylistFiles.shared.folder(folder) }
            else { index = nil }
            try validate()
            for (offset, track) in draft.tracks.enumerated() {
                try validate()
                if MusicPlaylistFiles.local(track) {
                    let record: MusicRecord
                    if let owned = draft.owned[track.id] {
                        _ = try MusicFileService.file(owned, owner: library.owner); record = owned
                    } else {
                        guard let index else { throw MusicPlaylistImportError.folder }
                        let url = try index.file(track)
                        let copied: MusicImport
                        if let existing = files[url] { copied = existing }
                        else {
                            copied = try await MusicFileService.shared.importFile(url, owner: library.owner)
                            staged.append(copied); files[url] = copied
                        }
                        try validate(); record = copied.record
                    }
                    // Retain the source M3U identity and EXTINF metadata. The
                    // filename points to a genuine file owned by this profile.
                    recordings.append(MusicTrack(id: track.id, connectorId: "local", sourceId: record.filename, playbackUrl: nil,
                        title: track.title, artist: track.artist, album: track.album, artwork: track.artwork,
                        durationSeconds: track.durationSeconds, durationLabel: track.durationLabel))
                } else { recordings.append(track) }
                progress(offset + 1, draft.tracks.count)
            }
            try validate()
            try library.commitImportedFiles(staged.map(\.record), token: token); committed = true
            guard let playlist = store.create(name, recordings: recordings) else { throw MusicPlaylistImportError.storage }
            return playlist
        } catch {
            if !committed {
                for imported in staged where imported.createdFile { try? await MusicFileService.shared.remove(imported.record, owner: library.owner) }
            }
            throw error
        }
    }
}
