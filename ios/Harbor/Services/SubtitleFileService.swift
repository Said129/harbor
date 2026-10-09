import Foundation

struct ImportedSubtitle: Sendable {
    let url: URL
    let title: String
}

/// A Files selection is copied while its security-scoped access is held.
/// Session copies remain available to mpv until that player has closed.
actor SubtitleFileService {
    static let shared = SubtitleFileService()
    static let extensions: Set<String> = ["srt", "ass", "ssa", "vtt", "sub"]
    private static let maximumSize = 8 * 1024 * 1024

    private func directory(_ session: UUID, create: Bool) throws -> URL {
        let base = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
        let root = base.appendingPathComponent("HarborSubtitles", isDirectory: true).appendingPathComponent(session.uuidString, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var protected = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try protected.setResourceValues(values)
        }
        return root
    }

    func copy(_ input: URL, session: UUID) async throws -> ImportedSubtitle {
        let access = input.startAccessingSecurityScopedResource()
        defer { if access { input.stopAccessingSecurityScopedResource() } }
        let ext = input.pathExtension.lowercased()
        let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard Self.extensions.contains(ext), values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= Self.maximumSize else { throw HarborError(code: "subtitle-file") }
        let root = try directory(session, create: true)
        guard try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < 24 else { throw HarborError(code: "subtitle-capacity") }
        let staging = root.appendingPathComponent("." + UUID().uuidString + ".import")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard FileManager.default.createFile(atPath: staging.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw HarborError(code: "subtitle-file") }
        let reader = try FileHandle(forReadingFrom: input), writer = try FileHandle(forWritingTo: staging)
        defer { try? reader.close(); try? writer.close() }
        var copied = 0
        while let bytes = try reader.read(upToCount: 64 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            copied += bytes.count
            guard copied <= size else { throw HarborError(code: "subtitle-file") }
            try writer.write(contentsOf: bytes)
            await Task.yield()
        }
        guard copied == size else { throw HarborError(code: "subtitle-file") }
        try Task.checkCancellation()
        try writer.synchronize(); try writer.close()
        let url = root.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.moveItem(at: staging, to: url)
        let title = String(input.lastPathComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(200))
        return ImportedSubtitle(url: url, title: title.isEmpty ? "Subtítulo importado" : title)
    }

    func discard(_ file: ImportedSubtitle, session: UUID) {
        guard let root = try? directory(session, create: false), file.url.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: file.url)
    }

    func cleanup(_ session: UUID) {
        guard let root = try? directory(session, create: false) else { return }
        try? FileManager.default.removeItem(at: root)
    }
}
