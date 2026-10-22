import CoreGraphics
import Foundation

struct ReadingCustomFont: Codable, Identifiable, Sendable {
    let id: String
    let owner: String
    let name: String
    let format: String
    let bytes: Int
}

actor ReadingFontStore {
    static let shared = ReadingFontStore()
    static let maximumBytes = 32 * 1024 * 1024
    private let root: URL?
    init(root: URL? = nil) { self.root = root }
    func list(owner: String) throws -> [ReadingCustomFont] {
        let folder = try folder(owner: owner)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.compactMap { url -> ReadingCustomFont? in
                guard let value = try? metadata(id: url.deletingPathExtension().lastPathComponent, owner: owner),
                      FileManager.default.fileExists(atPath: folder.appendingPathComponent(value.id + ".font").path) else { return nil }
                return value
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func importFont(_ url: URL, owner: String) throws -> ReadingCustomFont {
        let format = url.pathExtension.lowercased()
        guard url.isFileURL, ["ttf", "otf"].contains(format) else { throw HarborError(code: "reading-font-format") }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var data: Data?, readError: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { file in
            do {
                let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard bytes > 0, bytes <= Self.maximumBytes else { throw HarborError(code: "reading-font-size") }
                let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
                var loaded = Data()
                while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    guard loaded.count <= Self.maximumBytes - chunk.count else { throw HarborError(code: "reading-font-size") }
                    loaded.append(chunk)
                }
                guard !loaded.isEmpty else { throw HarborError(code: "reading-font-format") }
                data = loaded
            } catch { readError = error }
        }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let data, let provider = CGDataProvider(data: data as CFData), CGFont(provider) != nil else { throw HarborError(code: "reading-font-format") }
        try Task.checkCancellation()
        let id = EBookShelf.hash(data), folder = try folder(owner: owner)
        if let existing = try? metadata(id: id, owner: owner), (try? self.data(id: id, owner: owner)) != nil { return existing }
        let base = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = ReadingCustomFont(id: id, owner: EBookShelf.hash(owner), name: base.isEmpty ? "Custom font" : String(base.prefix(36)), format: format, bytes: data.count)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let file = try child(folder, name: id + ".font"), manifest = try child(folder, name: id + ".json")
        let existed = FileManager.default.fileExists(atPath: file.path)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do { try JSONEncoder().encode(value).write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { if !existed { try? FileManager.default.removeItem(at: file) }; throw error }
        return value
    }
    func data(id: String, owner: String) throws -> Data {
        let value = try metadata(id: id, owner: owner), file = try child(folder(owner: owner), name: id + ".font")
        guard try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == value.bytes else { throw HarborError(code: "reading-font-format") }
        let data = try Data(contentsOf: file)
        guard data.count <= Self.maximumBytes, EBookShelf.hash(data) == id,
              let provider = CGDataProvider(data: data as CFData), CGFont(provider) != nil else { throw HarborError(code: "reading-font-format") }
        try Task.checkCancellation(); return data
    }
    func remove(id: String, owner: String) throws {
        _ = try metadata(id: id, owner: owner)
        let folder = try folder(owner: owner)
        try FileManager.default.removeItem(at: child(folder, name: id + ".json"))
        let file = try child(folder, name: id + ".font")
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    private func metadata(id: String, owner: String) throws -> ReadingCustomFont {
        guard id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw HarborError(code: "reading-font-format") }
        let file = try child(folder(owner: owner), name: id + ".json")
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4096 else { throw HarborError(code: "reading-font-format") }
        let value = try JSONDecoder().decode(ReadingCustomFont.self, from: Data(contentsOf: file))
        guard value.id == id, value.owner == EBookShelf.hash(owner), value.bytes > 0, value.bytes <= Self.maximumBytes,
              ["ttf", "otf"].contains(value.format) else { throw HarborError(code: "reading-font-format") }
        return value
    }
    private func folder(owner: String) throws -> URL {
        let base: URL
        if let root { base = root.resolvingSymlinksInPath().standardizedFileURL }
        else {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).resolvingSymlinksInPath().standardizedFileURL
            base = support.appendingPathComponent("Harbor/ReadingFonts")
        }
        guard base.standardizedFileURL.path == base.resolvingSymlinksInPath().standardizedFileURL.path else { throw HarborError(code: "reading-font-format") }
        return try child(base, name: EBookShelf.hash(owner))
    }
    private func child(_ folder: URL, name: String) throws -> URL {
        let value = folder.appendingPathComponent(name).standardizedFileURL
        guard value.deletingLastPathComponent().path == folder.standardizedFileURL.path,
              value.path == value.resolvingSymlinksInPath().standardizedFileURL.path else { throw HarborError(code: "reading-font-format") }
        return value
    }
}
