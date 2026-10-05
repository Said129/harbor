import Foundation
import ZIPFoundation

/// Read images directly from a validated ZIP. No archive path is extracted.
final class MangaArchive {
    private let archive: Archive
    let paths: [String]
    init(file: URL) throws {
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 256 * 1024 * 1024 else { throw HarborError(code: "manga-size") }
        archive = try Archive(url: file, accessMode: .read)
        var count = 0, total: UInt64 = 0, images: [String] = []
        for entry in archive {
            count += 1
            guard count <= 10_000, entry.uncompressedSize <= 32 * 1024 * 1024 else { throw HarborError(code: "manga-size") }
            total += entry.uncompressedSize
            guard total <= 1024 * 1024 * 1024 else { throw HarborError(code: "manga-size") }
            let path = entry.path
            guard entry.type == .file, Self.safe(path), !path.hasPrefix("__MACOSX/"), !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }), ["jpg", "jpeg", "png", "webp", "gif", "avif", "bmp", "heic", "tiff"].contains((path as NSString).pathExtension.lowercased()) else { continue }
            images.append(path)
        }
        guard !images.isEmpty, images.count <= 5_000 else { throw HarborError(code: "manga-format") }
        paths = images.sorted { $0.compare($1, options: [.numeric, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) == .orderedAscending }
    }
    func data(_ path: String) throws -> Data {
        guard paths.contains(path), let entry = archive[path], entry.type == .file else { throw HarborError(code: "manga-format") }
        var payload = Data()
        let crc = try archive.extract(entry) { chunk in
            try Task.checkCancellation()
            guard payload.count <= 32 * 1024 * 1024 - chunk.count else { throw HarborError(code: "manga-size") }
            payload.append(chunk)
        }
        guard payload.count == Int(entry.uncompressedSize), crc == entry.checksum else { throw HarborError(code: "manga-format") }
        return payload
    }
    private static func safe(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }
}

actor MangaLocalStore {
    static let shared = MangaLocalStore()
    private var opened: [String: MangaArchive] = [:]
    private var recent: [String] = []
    func importArchive(_ input: URL, owner: String) throws -> MangaBook {
        let book = MangaBook(id: "local:" + UUID().uuidString, title: input.deletingPathExtension().lastPathComponent)
        let file = try Self.file(book, owner)
        guard (try input.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 256 * 1024 * 1024 else { throw HarborError(code: "manga-size") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        try FileManager.default.copyItem(at: input, to: file)
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            _ = try archive(book, owner: owner)
            return book
        } catch { try? FileManager.default.removeItem(at: file); throw error }
    }
    func importFolder(_ input: URL, owner: String) throws -> MangaBook {
        let root = input.resolvingSymlinksInPath().standardizedFileURL
        let book = MangaBook(id: "local:" + UUID().uuidString, title: input.lastPathComponent, folderChapters: true)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw HarborError(code: "manga-format") }
        var images: [(String, URL)] = [], total = 0, count = 0
        for case let source as URL in enumerator {
            try Task.checkCancellation(); count += 1
            guard count <= 10_000 else { throw HarborError(code: "manga-size") }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            let resolved = source.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/") else { throw HarborError(code: "manga-format") }
            guard values.isRegularFile == true, ["jpg", "jpeg", "png", "webp", "gif", "avif", "bmp", "heic", "tiff"].contains(source.pathExtension.lowercased()) else { continue }
            let size = values.fileSize ?? 0
            guard size > 0, size <= 32 * 1024 * 1024, total <= 240 * 1024 * 1024 - size, images.count < 5_000 else { throw HarborError(code: "manga-size") }
            total += size; images.append((String(source.path.dropFirst(root.path.count + 1)), resolved))
        }
        guard !images.isEmpty else { throw HarborError(code: "manga-format") }
        let file = try Self.file(book, owner)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        do {
            let zip = try Archive(url: file, accessMode: .create)
            for (path, source) in images { try Task.checkCancellation(); try zip.addEntry(with: path, fileURL: source) }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            _ = try archive(book, owner: owner)
            return book
        } catch { try? FileManager.default.removeItem(at: file); throw error }
    }
    func chapters(_ book: MangaBook, owner: String) throws -> [MangaChapter] {
        let paths = try archive(book, owner: owner).paths
        guard book.folderChapters == true else { return [MangaChapter(id: "local", title: book.title, pages: paths.count)] }
        let groups = Dictionary(grouping: paths, by: Self.chapter)
        return groups.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { key in
            let files = groups[key] ?? []
            if key == "local" && groups.count > 1 && files.allSatisfy({ ($0 as NSString).deletingPathExtension.lowercased() == "cover" }) { return nil }
            return MangaChapter(id: key, title: key == "local" ? book.title : key, pages: files.count)
        }
    }
    func pages(_ book: MangaBook, owner: String, chapter: String? = nil) throws -> [MangaPage] {
        let paths = try archive(book, owner: owner).paths
        let filtered = book.folderChapters == true && chapter != nil ? paths.filter { Self.chapter($0) == chapter } : paths
        return filtered.enumerated().map { MangaPage(id: $0.offset, path: $0.element) }
    }
    func data(_ book: MangaBook, owner: String, path: String) throws -> Data { try archive(book, owner: owner).data(path) }
    func remove(_ book: MangaBook, owner: String) throws {
        let key = Self.key(book, owner), file = try Self.file(book, owner)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        opened[key] = nil; recent.removeAll { $0 == key }
    }
    private func archive(_ book: MangaBook, owner: String) throws -> MangaArchive {
        let key = Self.key(book, owner)
        if let archive = opened[key] { return archive }
        let archive = try MangaArchive(file: Self.file(book, owner))
        opened[key] = archive; recent.removeAll { $0 == key }; recent.append(key)
        while recent.count > 2 { opened.removeValue(forKey: recent.removeFirst()) }
        return archive
    }
    nonisolated private static func key(_ book: MangaBook, _ owner: String) -> String { EBookShelf.hash(owner + "|" + book.id) }
    nonisolated private static func chapter(_ path: String) -> String { path.contains("/") ? String(path.split(separator: "/")[0]) : "local" }
    nonisolated private static func file(_ book: MangaBook, _ owner: String) throws -> URL {
        guard book.server == nil else { throw HarborError(code: "manga-format") }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false).resolvingSymlinksInPath().standardizedFileURL
        let file = support.appendingPathComponent("Harbor/Manga/" + key(book, owner) + ".cbz")
        guard file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else { throw HarborError(code: "manga-store") }
        return file
    }
}
