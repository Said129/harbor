import Foundation
import Observation
import UniformTypeIdentifiers

/// Creates and resolves the security-scoped bookmarks that stand in for the picked files and folders.
protocol LocalLibraryBookmarks: Sendable {
    func bookmark(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, stale: Bool)
}

/// iOS needs no `.withSecurityScope` option: a bookmark made from a picker URL carries the grant.
struct SystemLocalLibraryBookmarks: LocalLibraryBookmarks {
    func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ data: Data) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}

/// Holds access to a bookmarked scope (a file, or a picked folder) while the file plays. Call `end()` when the player closes.
@MainActor final class LocalLibraryFileAccess {
    /// The video file to play.
    let file: URL
    private let scope: URL
    private var started: Bool

    init(scope: URL, file: URL) {
        self.scope = scope
        self.file = file
        started = scope.startAccessingSecurityScopedResource()
    }

    func end() {
        guard started else { return }
        started = false
        scope.stopAccessingSecurityScopedResource()
    }
}

/// A file found inside a picked folder, before it is recorded.
struct LocalLibraryFolderEntry: Sendable {
    let url: URL
    let relativePath: String
    let size: Int64?
}

enum LocalLibraryFolderScan {
    /// Desktop's `harbor_scan_folder` uses `WalkDir::max_depth(8)` and never follows links.
    static let maximumDepth = 8
    static let maximumFiles = 5_000

    static func videoFiles(in root: URL) throws -> [LocalLibraryFolderEntry] {
        let rootURL = root.standardizedFileURL
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let keySet = Set(keys)
        guard let walker = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            throw HarborError(code: "local-folder")
        }
        var found: [LocalLibraryFolderEntry] = []
        while let next = walker.nextObject() as? URL {
            let values = try next.resourceValues(forKeys: keySet)
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                // Children of a directory at the limit would sit below depth 8.
                if walker.level >= maximumDepth { walker.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, LocalFilenameParser.isVideo(next.lastPathComponent) else { continue }
            let path = next.standardizedFileURL.path
            guard path.hasPrefix(prefix) else { continue }
            let size = values.fileSize.map { Int64($0) }
            found.append(LocalLibraryFolderEntry(url: next, relativePath: String(path.dropFirst(prefix.count)), size: size))
            guard found.count < maximumFiles else { throw HarborError(code: "local-folder-limit") }
        }
        return found
    }
}

/// Desktop's `adjacent_subtitles` (`src-tauri/src/local_lib.rs`): the subtitle files that belong to a video in a picked folder.
enum LocalSubtitleSidecars {
    static let extensions: Set<String> = ["srt", "ass", "ssa", "vtt"]

    /// `siblings` are the file names beside the video, the video included. A folder with one video takes every subtitle in it;
    /// otherwise a subtitle belongs to the video when its name is the video's name followed by a dot, a dash or an underscore.
    static func matches(video: String, siblings: [String]) -> [String] {
        let videoStem = (video as NSString).deletingPathExtension.lowercased()
        let videoCount = siblings.filter { LocalFilenameParser.isVideo($0) }.count
        let found: [String] = siblings.filter { (name: String) -> Bool in
            let ext = (name as NSString).pathExtension.lowercased()
            guard extensions.contains(ext) else { return false }
            if videoCount == 1 { return true }
            let stem = (name as NSString).deletingPathExtension.lowercased()
            guard stem.hasPrefix(videoStem) else { return false }
            let suffix = String(stem.dropFirst(videoStem.count))
            return suffix.isEmpty || [".", "-", "_"].contains(String(suffix.prefix(1)))
        }
        return found.sorted()
    }

    /// The subtitle files beside `video` in its folder. Only a folder the person picked can be listed, so a single picked
    /// file has none. Call it while the folder's access is open.
    static func urls(for video: URL) -> [URL] {
        let folder = video.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return [] }
        let names: [String] = entries.compactMap { (url: URL) -> String? in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true ? url.lastPathComponent : nil
        }
        let wanted = Set(matches(video: video.lastPathComponent, siblings: names))
        return entries.filter { wanted.contains($0.lastPathComponent) }.sorted { $0.path < $1.path }
    }
}

private struct LocalLibraryDocument: Codable, Sendable {
    var version = 1
    var records: [LocalLibraryRecord] = []
    var folders: [LocalLibraryFolder] = []
}

/// The local library for one profile: bookmarks in Application Support, never copies of the files.
/// Bookmarks are device-specific, so the file is excluded from backups.
@MainActor @Observable final class LocalLibraryStore {
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let bookmarks: any LocalLibraryBookmarks
    private(set) var records: [LocalLibraryRecord] = []
    private(set) var folders: [LocalLibraryFolder] = []
    /// False when the saved file could not be read. Writes are refused then, so the damaged file is kept.
    private(set) var ready = false
    private(set) var error: String?

    /// Video types for the file picker. Extensions iOS has no built-in type for are mapped by name.
    static var contentTypes: [UTType] {
        let named: [UTType] = LocalFilenameParser.videoExtensions.sorted().map { UTType(filenameExtension: $0) ?? UTType.movie }
        return [UTType.movie, UTType.video] + named
    }

    init(owner: String, fileURL: URL? = nil, bookmarks: any LocalLibraryBookmarks = SystemLocalLibraryBookmarks()) {
        self.bookmarks = bookmarks
        self.fileURL = fileURL ?? (try? Self.defaultFile(owner: owner))
        reload()
    }

    nonisolated static func defaultFile(owner: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("HarborLocalLibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
        return directory.appendingPathComponent(EBookShelf.hash(owner) + ".json")
    }

    func reload() {
        guard let fileURL = fileURL else {
            ready = false
            error = DesktopInterfaceText.value("Couldn't open this file")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let data = try Data(contentsOf: fileURL)
                let document = try JSONDecoder().decode(LocalLibraryDocument.self, from: data)
                records = document.records
                folders = document.folders
            } else {
                records = []
                folders = []
            }
            ready = true
            error = nil
        } catch {
            records = []
            folders = []
            ready = false
            self.error = DesktopInterfaceText.value("Couldn't open this file")
        }
    }

    /// Adds picked video files. Each URL must come straight from the file picker.
    /// Returns how many picked videos were valid. A file already in the library still counts, so picking it again is not an error.
    @discardableResult
    func addFiles(_ urls: [URL]) throws -> Int {
        guard ready else { throw HarborError(code: "local-library") }
        var next = records
        var known = Set(next.filter { $0.folderID == nil }.map(\.relativePath))
        var accepted = 0
        for url in urls {
            guard let record = try? makeRecord(url) else { continue }
            accepted += 1
            guard !known.contains(record.relativePath) else { continue }
            known.insert(record.relativePath)
            next.append(record)
        }
        if accepted == 0 && !urls.isEmpty { throw HarborError(code: "local-library-import") }
        if next.count != records.count { try commit(records: next, folders: folders) }
        return accepted
    }

    /// Adds the video files under a picked folder, skipping files below the minimum size as Desktop's scan does.
    /// Returns the number of new files. The folder is bookmarked once; its files open through that bookmark.
    @discardableResult
    func addFolder(_ folder: URL, megabytes: Int) throws -> Int {
        guard ready else { throw HarborError(code: "local-library") }
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        let minimum = Int64(max(0, megabytes)) * 1_048_576
        var nextFolders = folders
        let folderID: String
        if let existing = folders.first(where: { isSameFolder($0, folder) }) {
            folderID = existing.id
        } else {
            let data = try bookmarks.bookmark(for: folder)
            let created = LocalLibraryFolder(id: UUID().uuidString, name: folder.lastPathComponent, bookmark: data)
            nextFolders.append(created)
            folderID = created.id
        }
        var nextRecords = records
        var known = Set(nextRecords.filter { $0.folderID == folderID }.map(\.relativePath))
        var added = 0
        for entry in try LocalLibraryFolderScan.videoFiles(in: folder) {
            if let size = entry.size, size < minimum { continue }
            guard !known.contains(entry.relativePath) else { continue }
            known.insert(entry.relativePath)
            let record = LocalLibraryRecord(
                id: UUID().uuidString,
                filename: entry.url.lastPathComponent,
                bookmark: nil,
                size: entry.size,
                addedAt: Date(),
                folderID: folderID,
                folderName: folder.lastPathComponent,
                relativePath: entry.relativePath
            )
            nextRecords.append(record)
            added += 1
        }
        if added > 0 { try commit(records: nextRecords, folders: nextFolders) }
        return added
    }

    func remove(ids: Set<String>) throws {
        try commit(records: records.filter { !ids.contains($0.id) }, folders: folders)
    }

    /// Resolves a record for playback. The caller keeps the returned access until the player closes.
    func openForPlayback(_ record: LocalLibraryRecord) throws -> LocalLibraryFileAccess {
        guard ready else { throw HarborError(code: "local-library") }
        if let data = record.bookmark {
            let resolved = try bookmarks.resolve(data)
            let access = LocalLibraryFileAccess(scope: resolved.url, file: resolved.url)
            guard FileManager.default.fileExists(atPath: resolved.url.path) else {
                access.end()
                throw HarborError(code: "local-library-missing")
            }
            // A stale bookmark still opens the file now; re-save it while access is held so it keeps working.
            if resolved.stale, let fresh = try? bookmarks.bookmark(for: resolved.url) {
                try? commit(records: records.map { $0.id == record.id ? $0.withBookmark(fresh) : $0 }, folders: folders)
            }
            return access
        }
        guard let folderID = record.folderID, let source = folders.first(where: { $0.id == folderID }) else {
            throw HarborError(code: "local-library-missing")
        }
        let resolved = try bookmarks.resolve(source.bookmark)
        let file = URL(fileURLWithPath: record.relativePath, relativeTo: resolved.url)
        let access = LocalLibraryFileAccess(scope: resolved.url, file: file)
        guard FileManager.default.fileExists(atPath: file.path) else {
            access.end()
            throw HarborError(code: "local-library-missing")
        }
        if resolved.stale, let fresh = try? bookmarks.bookmark(for: resolved.url) {
            let nextFolders = folders.map { $0.id == folderID ? LocalLibraryFolder(id: $0.id, name: $0.name, bookmark: fresh) : $0 }
            try? commit(records: records, folders: nextFolders)
        }
        return access
    }

    /// Whether a saved folder bookmark points at the folder just picked.
    private func isSameFolder(_ saved: LocalLibraryFolder, _ folder: URL) -> Bool {
        guard let resolved = try? bookmarks.resolve(saved.bookmark) else { return false }
        return resolved.url.standardizedFileURL.path == folder.standardizedFileURL.path
    }

    private func makeRecord(_ url: URL) throws -> LocalLibraryRecord? {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, LocalFilenameParser.isVideo(url.lastPathComponent) else { return nil }
        let data = try bookmarks.bookmark(for: url)
        let size = values.fileSize.map { Int64($0) }
        return LocalLibraryRecord(id: UUID().uuidString, filename: url.lastPathComponent, bookmark: data, size: size, addedAt: Date(), folderID: nil, folderName: nil, relativePath: url.lastPathComponent)
    }

    /// Writes the library and drops any folder that no file refers to any more.
    private func commit(records nextRecords: [LocalLibraryRecord], folders nextFolders: [LocalLibraryFolder]) throws {
        guard ready, let fileURL = fileURL else { throw HarborError(code: "local-library") }
        let referenced = Set(nextRecords.compactMap { $0.folderID })
        let kept = nextFolders.filter { referenced.contains($0.id) }
        let data = try JSONEncoder().encode(LocalLibraryDocument(records: nextRecords, folders: kept))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        records = nextRecords
        folders = kept
        error = nil
    }
}
