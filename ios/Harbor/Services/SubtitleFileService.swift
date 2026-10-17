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
    private static let remoteSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    static func remoteRequest(_ text: String) throws -> URLRequest {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { throw HarborError(code: "subtitle-file") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, text/vtt, application/octet-stream, */*", forHTTPHeaderField: "Accept")
        return request
    }

    func download(_ input: PlaybackSource.Subtitle, session: UUID) async throws -> ImportedSubtitle {
        try Task.checkCancellation()
        let request = try Self.remoteRequest(input.url)
        let root = try directory(session, create: true)
        guard try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < 24 else { throw HarborError(code: "subtitle-capacity") }
        let (bytes, response) = try await Self.remoteSession.bytes(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.expectedContentLength <= Int64(Self.maximumSize) else { throw HarborError(code: "subtitle-file") }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumSize else { throw HarborError(code: "subtitle-file") }
            data.append(byte)
        }
        try Task.checkCancellation()
        let prefix = String(data: data.prefix(1024), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !data.isEmpty, !prefix.hasPrefix("<!doctype html"), !prefix.hasPrefix("<html"), data.prefix(2) != Data([0x50, 0x4b]) else { throw HarborError(code: "subtitle-file") }
        let supplied = request.url?.pathExtension.lowercased() ?? ""
        let ext = Self.extensions.contains(supplied) ? supplied : prefix.contains("[script info]") ? "ass" : prefix.hasPrefix("webvtt") ? "vtt" : "srt"
        let url = root.appendingPathComponent(UUID().uuidString + "." + ext)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return ImportedSubtitle(url: url, title: input.title ?? "Addon")
    }

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

    func synchronized(_ text: String, vtt: Bool, session: UUID) throws -> ImportedSubtitle {
        let data = Data(text.utf8)
        guard !data.isEmpty, data.count <= Self.maximumSize else { throw HarborError(code: "subtitle-file") }
        let root = try directory(session, create: true)
        guard try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < 24 else { throw HarborError(code: "subtitle-capacity") }
        let url = root.appendingPathComponent(UUID().uuidString + (vtt ? ".vtt" : ".srt"))
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return ImportedSubtitle(url: url, title: "Sincronizado automáticamente")
    }

    func cleanup(_ session: UUID) {
        guard let root = try? directory(session, create: false) else { return }
        try? FileManager.default.removeItem(at: root)
    }
}
