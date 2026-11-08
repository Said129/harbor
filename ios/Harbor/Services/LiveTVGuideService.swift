import Foundation

private final class LiveTVGuideRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The guide address carries the account's credentials in its query, so a redirect stays on the same origin.
        guard let previous = response.url, let next = request.url, next.scheme == previous.scheme, next.host?.lowercased() == previous.host?.lowercased(),
              next.user == nil, next.password == nil, (next.port ?? 0) == (previous.port ?? 0) else { completionHandler(nil); return }
        completionHandler(request)
    }
}

/// Loads and caches one playlist source's XMLTV guide, like Desktop's `loadEpg` and `epg-store.ts`:
/// a copy younger than one hour is used without a request, and a copy younger than 12 hours is used when the request fails.
actor LiveTVGuideService {
    static let shared = LiveTVGuideService()
    private static let freshFor: TimeInterval = 60 * 60
    private static let usableWhenOffline: TimeInterval = 12 * 60 * 60
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.httpCookieStorage = nil; configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: LiveTVGuideRedirectPolicy(), delegateQueue: nil)
    }

    /// The guide of one playlist source, or nil when the source has no guide address or no guide could be read.
    func guide(_ source: LivePlaylistSource, owner: String, refresh: Bool) async throws -> LiveTVGuide? {
        let urls = Self.urls(for: source)
        guard !urls.isEmpty else { return nil }
        let file = try cacheFile(source, owner: owner)
        let savedAt = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if !refresh, let saved = savedAt, Date().timeIntervalSince(saved) < Self.freshFor {
            return try LiveTVXMLTV.parse(Data(contentsOf: file))
        }
        for url in urls {
            do {
                try Task.checkCancellation()
                let data = try await download(url)
                let guide = try LiveTVXMLTV.parse(data)
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return guide
            } catch {
                try Task.checkCancellation()
            }
        }
        if let saved = savedAt, Date().timeIntervalSince(saved) < Self.usableWhenOffline {
            return try? LiveTVXMLTV.parse(Data(contentsOf: file))
        }
        return nil
    }

    func remove(_ source: LivePlaylistSource, owner: String) throws {
        let file = try cacheFile(source, owner: owner)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    /// Desktop's `useEpg` address rule: an Xtream account names its guide from the player API link, and an M3U link
    /// that ends in get.php or player_api.php names it too. A file import names none.
    static func urls(for source: LivePlaylistSource) -> [URL] {
        let raw: [String]
        if let account = source.xtream {
            guard let api = try? account.api(nil) else { return [] }
            raw = LiveTVEPG.derivedURLs(playlist: api.absoluteString)
        } else if let playlist = source.url {
            raw = LiveTVEPG.derivedURLs(playlist: playlist)
        } else {
            raw = []
        }
        return raw.compactMap { LivePlaylistService.validURL($0) }
    }

    private func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.setValue("application/xml, text/xml, application/octet-stream, */*", forHTTPHeaderField: "Accept")
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        let (fileURL, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw HarborError(code: "iptv-network") }
        guard http.expectedContentLength <= Int64(LiveTVXMLTV.maximumBytes) else { throw HarborError(code: "iptv-size") }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= LiveTVXMLTV.maximumBytes else { throw HarborError(code: "iptv-size") }
        return try Data(contentsOf: fileURL)
    }

    private func cacheFile(_ source: LivePlaylistSource, owner: String) throws -> URL {
        guard let uuid = UUID(uuidString: source.id) else { throw HarborError(code: "iptv-store") }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Harbor/LiveTV", isDirectory: true)
            .appendingPathComponent(EBookShelf.hash(owner), isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let file = root.appendingPathComponent(uuid.uuidString.lowercased() + ".xmltv")
        guard file.resolvingSymlinksInPath().deletingLastPathComponent().path == root.resolvingSymlinksInPath().path else { throw HarborError(code: "iptv-store") }
        return file
    }
}

/// Matches the loaded channels to their programmes, one playlist source at a time, as Desktop's guide view does.
enum LiveTVGuideBuilder {
    /// The programmes now and next can be read from, keyed by channel id. A source whose guide is empty falls back to
    /// Xtream's short EPG for its first 120 channels.
    static func programsByChannel(channels: [LiveChannel], sources: [LivePlaylistSource], owner: String, refresh: Bool) async -> [String: [LiveProgram]] {
        let counts = LiveTVGuideLookup.tvgIDCounts(channels)
        var output: [String: [LiveProgram]] = [:]
        for source in sources {
            let own = channels.filter { $0.source == source.id }
            guard !own.isEmpty else { continue }
            let guide = try? await LiveTVGuideService.shared.guide(source, owner: owner, refresh: refresh)
            if let guide {
                for channel in own {
                    if let programs = LiveTVGuideLookup.programs(for: channel, guide: guide, tvgIDCounts: counts), !programs.isEmpty {
                        output[channel.id] = programs
                    }
                }
            }
            guard guide?.isEmpty ?? true, source.xtream != nil else { continue }
            let fallback = await XtreamShortEPGFallback.hydrate(own, base: [:]) { channel in
                try await XtreamClient(source: source, owner: owner).programs(channel)
            }
            for channel in own {
                let key = channel.tvgID.flatMap { $0.isEmpty ? nil : $0 } ?? channel.id
                if let programs = fallback[key], !programs.isEmpty { output[channel.id] = LiveTVGuideLookup.sanitize(programs) }
            }
        }
        return output
    }
}
