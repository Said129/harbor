import Foundation

private final class XtreamRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Credentials are part of the API query. Keep the whole redirect at its origin.
        guard let previous = response.url, let next = request.url, next.scheme == previous.scheme, next.host?.lowercased() == previous.host?.lowercased(), port(next) == port(previous), next.user == nil, next.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
    private func port(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
}

actor XtreamClient {
    let source: LivePlaylistSource
    let owner: String
    private let account: XtreamAccount
    private let session: URLSession
    private static let maximumBytes = 32 * 1024 * 1024
    init(source: LivePlaylistSource, owner: String) throws {
        guard let account = source.xtream, UUID(uuidString: source.id) != nil else { throw HarborError(code: "xtream-credentials") }
        self.source = source; self.owner = owner; self.account = account
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate: XtreamRedirectPolicy(), delegateQueue: nil)
    }
    func capabilities(refresh: Bool = false) async throws -> XtreamCapabilities {
        let raw = try await request(nil, refresh: refresh), info = raw["user_info"]
        guard case .object = info else { throw HarborError(code: "xtream-response") }
        guard Self.number(info["auth"]) == 1, !["expired", "banned", "disabled"].contains((info["status"].string ?? "").lowercased()) else { throw HarborError(code: "xtream-authorization") }
        var base = account.base
        if raw["server_info"]["server_protocol"].string?.lowercased() == "https", var url = URLComponents(string: base) {
            let port = raw["server_info"]["https_port"].textValue ?? raw["server_info"]["port"].textValue
            if let port = port.flatMap(Int.init), (1...65_535).contains(port) { url.scheme = "https"; url.port = port; base = url.url?.absoluteString ?? base }
        }
        return XtreamCapabilities(formats: info["allowed_output_formats"].array.compactMap(\.string).map { $0.lowercased() }, streamBase: base)
    }
    func live(refresh: Bool) async throws -> [LiveChannel] {
        let caps = try await capabilities(refresh: refresh)
        async let categories = request("get_live_categories", refresh: refresh)
        async let streams = request("get_live_streams", refresh: refresh)
        let (groups, rows) = try await (categories, streams), names = try categoryNames(groups)
        let preferred = source.xtreamContainer == "m3u8" ? "m3u8" : "ts"
        let ext = caps.formats.isEmpty || caps.formats.contains(preferred) ? preferred : caps.formats.contains("ts") ? "ts" : caps.formats.contains("m3u8") ? "m3u8" : preferred
        return try boundedRows(rows).compactMap { row in
            guard let id = row["stream_id"].textValue else { return nil }
            let url = try account.stream(kind: "live", id: id, ext: ext, base: caps.streamBase)
            var attrs = ["xtream-stream-id": id]
            if (Self.number(row["tv_archive"]) ?? 0) > 0 { attrs["catchup"] = "xtream"; attrs["catchup-days"] = row["tv_archive_duration"].textValue }
            return LiveChannel(id: source.id + "::xt::" + id, source: source.id, tvgID: row["epg_channel_id"].string, name: Self.decodedName(row["name"].string, fallback: "Canal " + id), logo: row["stream_icon"].string, group: row["category_id"].textValue.flatMap { names[$0] }, url: url, catchup: nil, duration: nil, attributes: attrs)
        }
    }
    func vod(series: Bool, refresh: Bool) async throws -> [LiveChannel] {
        let prefix = series ? "series" : "vod"
        async let categories = request("get_\(prefix)_categories", refresh: refresh)
        async let streams = request(series ? "get_series" : "get_vod_streams", refresh: refresh)
        let (groups, rows) = try await (categories, streams), names = try categoryNames(groups)
        return try boundedRows(rows).compactMap { row in
            guard let id = row[series ? "series_id" : "stream_id"].textValue else { return nil }
            let declared = row["stream_type"].string?.lowercased()
            if let declared, !declared.isEmpty, !(series ? ["series"] : ["movie", "vod"]).contains(declared) { return nil }
            let url = series ? "" : try account.stream(kind: "movie", id: id, ext: row["container_extension"].string)
            var attrs = ["tvg-type": series ? "series" : "movie"]
            if series { attrs["xtream-series-id"] = id }
            return LiveChannel(id: source.id + (series ? "::xtseries::" : "::xtvod::") + id, source: source.id, tvgID: nil, name: Self.decodedName(row["name"].string, fallback: (series ? "Serie " : "Película ") + id), logo: row[series ? "cover" : "stream_icon"].string, group: row["category_id"].textValue.flatMap { names[$0] }, url: url, catchup: nil, duration: nil, attributes: attrs)
        }
    }
    func episodes(_ series: VODSeries, refresh: Bool = false) async throws -> [VODEpisode] {
        guard series.source == source.id, let id = series.xtreamID else { throw HarborError(code: "xtream-response") }
        let raw = try await request("get_series_info", extra: ["series_id": id], refresh: refresh)
        guard case .object(let seasons) = raw["episodes"] else { throw HarborError(code: "xtream-response") }
        var output: [VODEpisode] = [], seen = Set<String>()
        for (number, value) in seasons {
            for row in try boundedRows(value) {
                try Task.checkCancellation()
                guard let id = row["id"].textValue, seen.insert(id).inserted else { continue }
                guard output.count < 10_000 else { throw HarborError(code: "iptv-size") }
                let season = row["season"].textValue.flatMap(Int.init) ?? Int(number) ?? 1, episode = row["episode_num"].textValue.flatMap(Int.init) ?? 0
                let title = row["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
                let channel = LiveChannel(id: source.id + "::xtep::" + id, source: source.id, tvgID: nil, name: series.title + " S\(season)E\(episode)", logo: row["info"]["movie_image"].string ?? series.logo, group: series.group, url: try account.stream(kind: "series", id: id, ext: row["container_extension"].string), catchup: nil, duration: Self.number(row["info"]["duration_secs"]), attributes: ["tvg-type": "series"])
                output.append(VODEpisode(channel: channel, season: season, episode: episode, title: title.flatMap { $0.isEmpty ? nil : $0 } ?? "Episodio \(episode)", plot: row["info"]["plot"].string))
            }
        }
        return output.sorted { $0.season == $1.season ? $0.episode < $1.episode : $0.season < $1.season }
    }
    func programs(_ channel: LiveChannel) async throws -> [LiveProgram] {
        guard channel.source == source.id, let id = channel.attributes["xtream-stream-id"] else { throw HarborError(code: "xtream-response") }
        let raw = try await request("get_short_epg", extra: ["stream_id": id, "limit": "8"], refresh: true)
        guard case .array(let rows) = raw["epg_listings"] else { throw HarborError(code: "xtream-response") }
        return rows.prefix(64).compactMap { row in
            guard let start = Self.number(row["start_timestamp"]), let end = Self.number(row["stop_timestamp"]), start.isFinite, end.isFinite, end > start else { return nil }
            return LiveProgram(id: id + ":" + String(start), title: Self.decodedName(row["title"].string, fallback: "Programa"), description: row["description"].string.map { Self.decodedName($0, fallback: "") }, start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
        }.sorted { $0.start < $1.start }
    }
    private func categoryNames(_ json: JSONValue) throws -> [String: String] {
        var names: [String: String] = [:]
        for row in try boundedRows(json) { if let id = row["category_id"].textValue { names[id] = row["category_name"].string ?? "" } }
        return names
    }
    private func boundedRows(_ json: JSONValue) throws -> [JSONValue] {
        guard case .array(let rows) = json, rows.count <= 100_000 else { throw HarborError(code: "xtream-response") }; return rows
    }
    private func request(_ action: String?, extra: [String: String] = [:], refresh: Bool) async throws -> JSONValue {
        let file = try cacheFile(action: action, extra: extra)
        let savedAt = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if !refresh, let savedAt, Date().timeIntervalSince(savedAt) < 6 * 60 * 60 { let result = try Self.read(file); try Self.validate(result, action: action); return result }
        do {
            var request = URLRequest(url: try account.api(action, extra: extra), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
            request.setValue("IPTVSmartersPro/3.1.5", forHTTPHeaderField: "User-Agent"); request.setValue("application/json, */*", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), response.expectedContentLength <= Int64(Self.maximumBytes) else { throw HarborError(code: "xtream-network") }
            var data = Data()
            for try await byte in bytes { try Task.checkCancellation(); guard data.count < Self.maximumBytes else { throw HarborError(code: "iptv-size") }; data.append(byte) }
            let result = try JSONDecoder().decode(JSONValue.self, from: data)
            try Self.validate(result, action: action)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); try trimCache(file.deletingLastPathComponent()); return result
        } catch {
            try Task.checkCancellation()
            if action != nil, FileManager.default.fileExists(atPath: file.path), let previous = try? Self.read(file), (try? Self.validate(previous, action: action)) != nil { return previous }
            if let safe = error as? HarborError { throw safe }
            throw HarborError(code: "xtream-network")
        }
    }
    private func cacheFile(action: String?, extra: [String: String]) throws -> URL {
        let directory = try Self.directory(source: source.id, owner: owner)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let key = (action ?? "account") + "|" + extra.sorted { $0.key < $1.key }.map { $0.key + "=" + $0.value }.joined(separator: "&")
        return directory.appendingPathComponent(EBookShelf.hash(key) + ".json")
    }
    private func trimCache(_ directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey]).filter { $0.pathExtension == "json" }.sorted {
            let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return first > second
        }
        var bytes = 0
        for (index, file) in files.enumerated() {
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, file.resolvingSymlinksInPath().deletingLastPathComponent().path == directory.resolvingSymlinksInPath().path else { continue }
            bytes += values.fileSize ?? 0
            if index >= 48 || bytes > 128 * 1024 * 1024 { try FileManager.default.removeItem(at: file) }
        }
    }
    private static func read(_ file: URL) throws -> JSONValue {
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var data = Data()
        while let part = try handle.read(upToCount: 64 * 1024), !part.isEmpty { guard data.count <= maximumBytes - part.count else { throw HarborError(code: "iptv-size") }; data.append(part) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    nonisolated private static func directory(source: String, owner: String) throws -> URL {
        guard let uuid = UUID(uuidString: source) else { throw HarborError(code: "iptv-store") }
        let parent = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Harbor/LiveTV", isDirectory: true).appendingPathComponent(EBookShelf.hash(owner), isDirectory: true)
        let directory = parent.appendingPathComponent(uuid.uuidString.lowercased(), isDirectory: true)
        guard directory.resolvingSymlinksInPath().deletingLastPathComponent().path == parent.resolvingSymlinksInPath().path else { throw HarborError(code: "iptv-store") }; return directory
    }
    nonisolated static func remove(source: String, owner: String) throws {
        let directory = try directory(source: source, owner: owner)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    nonisolated static func decodedName(_ raw: String?, fallback: String) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return fallback }
        guard raw.count % 4 == 0, raw.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil, let data = Data(base64Encoded: raw), let decoded = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !decoded.isEmpty, !decoded.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }) else { return raw }
        return decoded
    }
    nonisolated private static func number(_ value: JSONValue) -> Double? { value.numericValue ?? value.string.flatMap(Double.init) }
    nonisolated private static func validate(_ value: JSONValue, action: String?) throws {
        if action == nil {
            guard case .object = value["user_info"] else { throw HarborError(code: "xtream-response") }
            guard number(value["user_info"]["auth"]) == 1, !["expired", "banned", "disabled"].contains((value["user_info"]["status"].string ?? "").lowercased()) else { throw HarborError(code: "xtream-authorization") }
        } else if action == "get_series_info" {
            guard case .object(let seasons) = value["episodes"], seasons.count <= 1_000 else { throw HarborError(code: "xtream-response") }
            for episodes in seasons.values { try validateRows(episodes) }
        } else if action == "get_short_epg" { try validateRows(value["epg_listings"]) }
        else { try validateRows(value) }
    }
    nonisolated private static func validateRows(_ value: JSONValue) throws {
        guard case .array(let rows) = value, rows.count <= 100_000, rows.allSatisfy({ row in if case .object = row { return true }; return false }) else { throw HarborError(code: "xtream-response") }
    }
}
