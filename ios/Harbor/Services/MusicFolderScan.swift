import Foundation

extension MusicFileService {
    // Desktop's local scanner uses a depth of 12 and never follows links.
    // iOS imports a private copy while the selected folder's access is held.
    func scanFolder(_ input: URL) async throws -> [URL] {
        let root = input.standardizedFileURL
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        let values = try root.resourceValues(forKeys: keys)
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw HarborError(code: "music-folder") }
        var failed = false
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in failed = true; return false }) else { throw HarborError(code: "music-folder") }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var files: [URL] = []
        var visited = 0
        while let file = entries.nextObject() as? URL {
            try Task.checkCancellation()
            visited += 1
            guard visited <= 20_000 else { throw HarborError(code: "music-folder-limit") }
            if visited.isMultiple(of: 128) { await Task.yield() }
            guard file.standardizedFileURL.path.hasPrefix(prefix) else { throw HarborError(code: "music-folder") }
            let info = try file.resourceValues(forKeys: keys)
            if info.isSymbolicLink == true { entries.skipDescendants(); continue }
            if entries.level > 12 { entries.skipDescendants(); continue }
            if info.isDirectory == true {
                if entries.level == 12 { entries.skipDescendants() }
                continue
            }
            guard info.isRegularFile == true, Self.extensions.contains(file.pathExtension.lowercased()) else { continue }
            guard files.count < 500 else { throw HarborError(code: "music-folder-limit") }
            files.append(file)
        }
        guard !failed else { throw HarborError(code: "music-folder") }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
