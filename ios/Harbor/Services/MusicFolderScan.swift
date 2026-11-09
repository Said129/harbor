import Foundation

struct MusicFolderFile: Sendable {
    let url: URL
    let relativePath: String
    let size: Int64
    let modifiedAtSeconds: Int64?
}

struct MusicFolderIndexEntry: Codable, Hashable, Sendable {
    let recordID: String
    let size: Int64
    let modifiedAtSeconds: Int64?
    let preserveWhenMissing: Bool
}

struct MusicFolderSource: Codable, Sendable {
    let id: String
    let name: String
    var bookmark: Data
    var entries: [String: MusicFolderIndexEntry]
    var suppressedPaths: Set<String>
}

enum MusicIncrementalScan {
    static func isUnchanged(_ file: MusicFolderFile, from entry: MusicFolderIndexEntry?) -> Bool {
        guard let entry else { return false }
        return file.size == entry.size && file.modifiedAtSeconds == entry.modifiedAtSeconds
    }

    static func removedPaths(previous: Set<String>, seen: Set<String>, completed: Bool) -> Set<String> {
        guard completed else { return [] }
        return previous.subtracting(seen)
    }

    static func shouldImport(path: String, suppressed: Set<String>) -> Bool {
        !suppressed.contains(path)
    }

    static func recordID(sourceID: String, relativePath: String, existingID: String?) -> String {
        existingID ?? "local:folder:\(sourceID):\(EBookShelf.hash(relativePath))"
    }
}

extension MusicFileService {
    // Desktop's local scanner uses a depth of 12 and never follows links.
    // iOS imports a private copy while the selected folder's access is held.
    func scanFolder(_ input: URL) async throws -> [URL] {
        let files = try await scanFolderEntries(input)
        return files.map(\.url)
    }

    func scanFolderEntries(_ input: URL) async throws -> [MusicFolderFile] {
        let root = input.standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let values = try root.resourceValues(forKeys: keys)
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw HarborError(code: "music-folder") }
        var failed = false
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in failed = true; return false }) else { throw HarborError(code: "music-folder") }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var files: [MusicFolderFile] = []
        var visited = 0
        while let file = entries.nextObject() as? URL {
            try Task.checkCancellation()
            visited += 1
            guard visited <= 400_000 else { throw HarborError(code: "music-folder-limit") }
            if visited.isMultiple(of: 128) { await Task.yield() }
            let standardized = file.standardizedFileURL
            guard standardized.path.hasPrefix(prefix) else { throw HarborError(code: "music-folder") }
            let info = try standardized.resourceValues(forKeys: keys)
            if info.isSymbolicLink == true { continue }
            if entries.level > 12 {
                if info.isDirectory == true { entries.skipDescendants() }
                continue
            }
            if info.isDirectory == true {
                if entries.level == 12 { entries.skipDescendants() }
                continue
            }
            guard info.isRegularFile == true, Self.extensions.contains(standardized.pathExtension.lowercased()) else { continue }
            guard files.count < 100_000, let size = info.fileSize else { throw HarborError(code: "music-folder-limit") }
            let modified = info.contentModificationDate.map { Int64($0.timeIntervalSince1970) }
            files.append(MusicFolderFile(url: standardized, relativePath: String(standardized.path.dropFirst(prefix.count)), size: Int64(size), modifiedAtSeconds: modified))
        }
        guard !failed else { throw HarborError(code: "music-folder") }
        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}
