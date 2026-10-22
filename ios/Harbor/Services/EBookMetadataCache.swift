import Foundation

actor EBookMetadataCache {
    private struct Document: Codable { var schema = 1; let owner: String; let values: [String: String] }
    private let file: URL
    private let owner: String
    init(owner: String, file: URL? = nil) throws {
        self.owner = EBookShelf.hash(owner)
        if let file { self.file = file }
        else {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            self.file = folder.appendingPathComponent("Harbor/Books/Metadata/" + self.owner + ".json")
        }
    }
    nonisolated static func allowed(_ key: String) -> Bool { key == "harbor.ebook.metadata.v1" || key.hasPrefix("harbor.ebook.openlibrary.v2.") }
    func load() throws -> [String: String] {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4 * 1024 * 1024 else { return [:] }
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
        guard document.schema == 1, document.owner == owner else { return [:] }
        return document.values.filter { Self.allowed($0.key) }
    }
    func save(_ values: [String: String]) throws {
        try Task.checkCancellation()
        let data = try JSONEncoder().encode(Document(owner: owner, values: values.filter { Self.allowed($0.key) }))
        guard data.count <= 4 * 1024 * 1024 else { return }
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard folder.standardizedFileURL == folder.resolvingSymlinksInPath().standardizedFileURL,
              file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else { throw HarborError(code: "ebook-cache-path") }
        try Task.checkCancellation(); try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clear() throws {
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
