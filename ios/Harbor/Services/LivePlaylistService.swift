import Foundation

private final class PlaylistRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, ["http", "https"].contains(url.scheme), url.user == nil, url.password == nil, !(response.url?.scheme == "https" && url.scheme != "https") else { completionHandler(nil); return }
        var safe = request; safe.httpShouldHandleCookies = false
        if url.host != response.url?.host || url.port != response.url?.port || url.scheme != response.url?.scheme { for name in ["Authorization", "Cookie", "Referer"] { safe.setValue(nil, forHTTPHeaderField: name) } }
        completionHandler(safe)
    }
}

actor LivePlaylistService {
    static let shared = LivePlaylistService()
    nonisolated static let maximumBytes = 32 * 1024 * 1024
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: PlaylistRedirectPolicy(), delegateQueue: nil)
    }
    func load(_ source: LivePlaylistSource, owner: String, refresh: Bool) async throws -> [LiveChannel] {
        let file = try cacheFile(source, owner: owner)
        let exists = FileManager.default.fileExists(atPath: file.path)
        let savedAt = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let fresh = savedAt.map { Date().timeIntervalSince($0) < 6 * 60 * 60 } ?? false
        if exists, source.url == nil || (!refresh && fresh) { return try M3UParser.parse(Self.read(file), source: source.id) }
        guard let raw = source.url, let url = Self.validURL(raw) else { throw HarborError(code: "iptv-url") }
        do {
            let data = try await download(url)
            let channels = try M3UParser.parse(data, source: source.id)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return channels
        } catch {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: file.path) { return try M3UParser.parse(Self.read(file), source: source.id) }
            throw error
        }
    }
    func importFile(_ url: URL, source: LivePlaylistSource, owner: String) throws -> [LiveChannel] {
        let data = try Self.read(url), channels = try M3UParser.parse(data, source: source.id)
        try data.write(to: cacheFile(source, owner: owner), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return channels
    }
    func remove(_ source: LivePlaylistSource, owner: String) throws {
        let file = try cacheFile(source, owner: owner)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    nonisolated static func validURL(_ raw: String) -> URL? {
        guard !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains), let url = URL(string: raw), ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw HarborError(code: "iptv-network") }
            guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw HarborError(code: "iptv-size") }
            var data = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard data.count < Self.maximumBytes else { throw HarborError(code: "iptv-size") }; data.append(byte) }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as HarborError { throw error }
        catch { throw HarborError(code: "iptv-network") }
    }
    private func cacheFile(_ source: LivePlaylistSource, owner: String) throws -> URL {
        guard let uuid = UUID(uuidString: source.id) else { throw HarborError(code: "iptv-store") }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Harbor/LiveTV", isDirectory: true).appendingPathComponent(EBookShelf.hash(owner), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let file = root.appendingPathComponent(uuid.uuidString.lowercased() + ".m3u")
        guard file.resolvingSymlinksInPath().deletingLastPathComponent().path == root.resolvingSymlinksInPath().path else { throw HarborError(code: "iptv-store") }
        return file
    }
    nonisolated private static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var data = Data()
        while let part = try handle.read(upToCount: 64 * 1024), !part.isEmpty { try Task.checkCancellation(); guard data.count <= maximumBytes - part.count else { throw HarborError(code: "iptv-size") }; data.append(part) }
        return data
    }
}
