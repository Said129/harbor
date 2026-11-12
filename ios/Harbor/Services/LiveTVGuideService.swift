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
    /// Desktop keeps parsed guides in memory (`epg-store.ts` `cache`). Two are kept here, so a Programación screen
    /// does not parse the whole XMLTV file again each time it opens.
    private static let parsedLimit = 2
    private struct ParsedGuide {
        let savedAt: Date
        let guide: LiveTVGuide
    }
    private var parsed: [String: ParsedGuide] = [:]
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
            return try cachedGuide(file, savedAt: saved)
        }
        // Desktop's `doFetchWithFallback`: an address whose guide has no programmes is skipped, and the next one is tried.
        var empty: LiveTVGuide?
        for url in urls {
            do {
                try Task.checkCancellation()
                let data = try await download(url)
                let guide = try LiveTVXMLTV.parse(data, window: Self.window())
                if guide.isEmpty { empty = guide; continue }
                try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                // The parsed copy is keyed by the file's own modification date, the same value `cachedGuide` reads back.
                if let written = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    parsed[file.path] = ParsedGuide(savedAt: written, guide: guide)
                }
                return guide
            } catch {
                try Task.checkCancellation()
            }
        }
        if let saved = savedAt, Date().timeIntervalSince(saved) < Self.usableWhenOffline {
            return try? cachedGuide(file, savedAt: saved)
        }
        return empty
    }

    /// The parsed copy of the saved guide, reused while the file has not changed on disk.
    private func cachedGuide(_ file: URL, savedAt: Date) throws -> LiveTVGuide {
        if let entry = parsed[file.path], entry.savedAt == savedAt { return entry.guide }
        let guide = try LiveTVXMLTV.parse(Data(contentsOf: file), window: Self.window())
        if parsed[file.path] == nil, parsed.count >= Self.parsedLimit { parsed.removeAll() }
        parsed[file.path] = ParsedGuide(savedAt: savedAt, guide: guide)
        return guide
    }

    /// The programmes kept from a guide: twelve hours of catch-up history through three days ahead. Desktop keeps every
    /// programme; iOS bounds the copy in memory so a very large guide cannot fill a phone.
    static func window(now: Date = Date()) -> ClosedRange<Date> {
        now.addingTimeInterval(-12 * 3600)...now.addingTimeInterval(72 * 3600)
    }

    func remove(_ source: LivePlaylistSource, owner: String) throws {
        let file = try cacheFile(source, owner: owner)
        parsed[file.path] = nil
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    /// Desktop's `useEpg` address rule: the guide address the user typed comes first (`epgUrl`). Then an Xtream account
    /// names its guide from the player API link, and an M3U link that ends in get.php or player_api.php names it too.
    /// A file import names none.
    static func urls(for source: LivePlaylistSource) -> [URL] {
        var raw: [String] = []
        if let typed = source.epgURL, !typed.isEmpty { raw.append(typed) }
        if let account = source.xtream {
            guard let api = try? account.api(nil) else { return raw.compactMap { LivePlaylistService.validURL($0) } }
            raw.append(contentsOf: LiveTVEPG.derivedURLs(playlist: api.absoluteString))
        } else if let playlist = source.url {
            raw.append(contentsOf: LiveTVEPG.derivedURLs(playlist: playlist))
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
