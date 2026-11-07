import Foundation
import Observation
import UniformTypeIdentifiers

/// Creates and resolves the security-scoped bookmarks that stand in for the picked files.
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

/// Holds access to one file while it plays. Call `end()` when the player closes.
@MainActor final class LocalLibraryFileAccess {
    let url: URL
    private var started: Bool

    init(url: URL) {
        self.url = url
        started = url.startAccessingSecurityScopedResource()
    }

    func end() {
        guard started else { return }
        started = false
        url.stopAccessingSecurityScopedResource()
    }
}

/// A file found inside a picked folder, before its bookmark is made.
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

private struct LocalLibraryDocument: Codable, Sendable {
    var version = 1
    var records: [LocalLibraryRecord] = []
}

/// The local library for one profile: a JSON list of bookmarks in Application Support, never the files themselves.
/// Bookmarks are device-specific, so the file is excluded from backups.
@MainActor @Observable final class LocalLibraryStore {
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let bookmarks: any LocalLibraryBookmarks
    private(set) var records: [LocalLibraryRecord] = []
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
                records = try JSONDecoder().decode(LocalLibraryDocument.self, from: data).records
            } else {
                records = []
            }
            ready = true
            error = nil
        } catch {
            records = []
            ready = false
            self.error = DesktopInterfaceText.value("Couldn't open this file")
        }
    }

    /// Adds picked video files. Each URL must come straight from the file picker.
    @discardableResult
    func addFiles(_ urls: [URL]) throws -> Int {
        guard ready else { throw HarborError(code: "local-library") }
        var next = records
        var known = Set(next.map { Self.identity(folder: $0.folder, path: $0.relativePath) })
        var accepted = 0
        var added = 0
        for url in urls {
            guard let record = try? makeRecord(url, folder: nil, relativePath: url.lastPathComponent) else { continue }
            // A file already in the library counts as accepted, so picking it again is not an error.
            accepted += 1
            let id = Self.identity(folder: nil, path: record.relativePath)
            guard !known.contains(id) else { continue }
            known.insert(id)
            next.append(record)
            added += 1
        }
        if accepted == 0 && !urls.isEmpty { throw HarborError(code: "local-library-import") }
        if added > 0 { try commit(next) }
        return added
    }

    /// Adds the video files under a picked folder, skipping files below the minimum size, as Desktop's scan does.
    @discardableResult
    func addFolder(_ folder: URL, megabytes: Int) throws -> Int {
        guard ready else { throw HarborError(code: "local-library") }
        let opened = folder.startAccessingSecurityScopedResource()
        defer { if opened { folder.stopAccessingSecurityScopedResource() } }
        let name = folder.lastPathComponent
        let minimum = Int64(max(0, megabytes)) * 1_048_576
        var next = records
        var known = Set(next.map { Self.identity(folder: $0.folder, path: $0.relativePath) })
        var added = 0
        for entry in try LocalLibraryFolderScan.videoFiles(in: folder) {
            if let size = entry.size, size < minimum { continue }
            let id = Self.identity(folder: name, path: entry.relativePath)
            guard !known.contains(id) else { continue }
            guard let data = try? bookmarks.bookmark(for: entry.url) else { continue }
            known.insert(id)
            let record = LocalLibraryRecord(id: UUID().uuidString, filename: entry.url.lastPathComponent, bookmark: data, size: entry.size, addedAt: Date(), folder: name, relativePath: entry.relativePath)
            next.append(record)
            added += 1
        }
        if added > 0 { try commit(next) }
        return added
    }

    func remove(ids: Set<String>) throws {
        try commit(records.filter { !ids.contains($0.id) })
    }

    /// Resolves a record for playback. The caller keeps the returned access until the player closes.
    func openForPlayback(_ record: LocalLibraryRecord) throws -> LocalLibraryFileAccess {
        guard ready else { throw HarborError(code: "local-library") }
        let resolved = try bookmarks.resolve(record.bookmark)
        let access = LocalLibraryFileAccess(url: resolved.url)
        guard FileManager.default.fileExists(atPath: resolved.url.path) else {
            access.end()
            throw HarborError(code: "local-library-missing")
        }
        // A stale bookmark still opens the file now; re-save it while access is held so it keeps working.
        if resolved.stale, let fresh = try? bookmarks.bookmark(for: resolved.url) {
            let next = records.map { $0.id == record.id ? $0.withBookmark(fresh) : $0 }
            try? commit(next)
        }
        return access
    }

    private static func identity(folder: String?, path: String) -> String {
        (folder ?? "") + "\n" + path
    }

    private func makeRecord(_ url: URL, folder: String?, relativePath: String) throws -> LocalLibraryRecord? {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, LocalFilenameParser.isVideo(url.lastPathComponent) else { return nil }
        let data = try bookmarks.bookmark(for: url)
        let size = values.fileSize.map { Int64($0) }
        return LocalLibraryRecord(id: UUID().uuidString, filename: url.lastPathComponent, bookmark: data, size: size, addedAt: Date(), folder: folder, relativePath: relativePath)
    }

    private func commit(_ next: [LocalLibraryRecord]) throws {
        guard ready, let fileURL = fileURL else { throw HarborError(code: "local-library") }
        let data = try JSONEncoder().encode(LocalLibraryDocument(records: next))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        records = next
        error = nil
    }
}
