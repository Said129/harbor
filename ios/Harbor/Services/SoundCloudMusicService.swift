import Foundation
import Observation

/// Native transport for the pinned Desktop connector's public endpoints. It
/// retains its consent, public-client discovery and full-stream-only policy.
@MainActor @Observable final class SoundCloudMusicService: MusicCatalogCalling {
    let scope: PluginExecutionScope
    private(set) var enabled: Bool
    private(set) var health = MusicSourceCandidate.Health.unknown
    var connectionRevision: UUID { revision }
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let network: any HarborNativeNetworkCalling
    @ObservationIgnored private var clientID: String?
    @ObservationIgnored private var identityTask: Task<String, Error>?
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var revision = UUID()
    private var key: String { "music.soundcloud.consent." + EBookShelf.hash(scope.owner) }
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         network: any HarborNativeNetworkCalling = HarborNativeNetwork()) {
        self.scope = scope; self.currentScope = currentScope; self.network = network
        enabled = UserDefaults.standard.bool(forKey: "music.soundcloud.consent." + EBookShelf.hash(scope.owner))
    }
    func setEnabled(_ value: Bool) {
        guard !disposed, scope == currentScope() else { return }
        enabled = value; revision = UUID(); UserDefaults.standard.set(value, forKey: key)
        if !value { identityTask?.cancel(); identityTask = nil; clientID = nil }
    }
    private func validate(_ version: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, enabled, scope == currentScope(), version == nil || version == revision else { throw CancellationError() }
    }
    private func fetch(_ raw: String, range: Bool = false) async throws -> HarborNetworkResponse {
        try validate(); let version = revision
        guard let url = URL(string: raw), url.scheme == "https", url.user == nil, url.password == nil, url.port == nil,
              ["soundcloud.com", "a-v2.sndcdn.com", "api-v2.soundcloud.com"].contains(url.host ?? "") else { throw HarborError(code: "music-soundcloud-host") }
        var request = HarborNetworkRequest(url: raw)
        request.publicNetworkOnly = true; request.timeoutMs = range || url.host == "soundcloud.com" ? 2000 : 8000
        request.maxResponseBytes = range ? 50_001 : 2 * 1024 * 1024
        request.headers = ["User-Agent": "Mozilla/5.0 Harbor/0.9.132"]
        if range { request.headers["Range"] = "bytes=0-50000" }
        let result = try await network.perform(request); try validate(version); return result
    }
    private func identity() async throws -> String {
        try validate()
        if let clientID { return clientID }
        if let identityTask { return try await identityTask.value }
        let version = revision
        let task = Task { @MainActor [weak self] () throws -> String in
            guard let self else { throw CancellationError() }
            let deadline = Date().addingTimeInterval(5)
            let response = try await fetch("https://soundcloud.com/")
            guard response.ok else { throw HarborError(code: "music-soundcloud-unavailable") }
            let html = String(decoding: try response.bytes(), as: UTF8.self)
            let scripts = try NSRegularExpression(pattern: #"https://a-v2\.sndcdn\.com/assets/[A-Za-z0-9._~/-]+\.js"#)
            let ns = html as NSString
            var seen = Set<String>()
            let candidates = scripts.matches(in: html, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }.filter { seen.insert($0).inserted }.reversed().prefix(6)
            let found = await withTaskGroup(of: (Bool, String?).self) { group -> String? in
                for url in candidates {
                    group.addTask { [weak self] in
                        guard let self, let response = try? await self.fetch(url, range: true), response.ok, let bytes = try? response.bytes() else { return (false, nil) }
                        let body = String(decoding: bytes, as: UTF8.self) as NSString
                        guard let pattern = try? NSRegularExpression(pattern: #"client_id\s*:\s*"([0-9a-zA-Z]{32})""#),
                              let match = pattern.firstMatch(in: body as String, range: NSRange(location: 0, length: body.length)) else { return (false, nil) }
                        return (false, body.substring(with: match.range(at: 1)))
                    }
                }
                group.addTask {
                    do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) } catch { }
                    return (true, nil)
                }
                var completed = 0
                while let (expired, value) = await group.next() {
                    if let value { group.cancelAll(); return value }
                    if expired { group.cancelAll(); return nil }
                    completed += 1
                    if completed == candidates.count { group.cancelAll(); return nil }
                }
                return nil
            }
            try validate(version)
            if let found { return found }
            throw HarborError(code: "music-soundcloud-identity")
        }
        identityTask = task
        defer { if revision == version { identityTask = nil } }
        let found = try await task.value; try validate(version); clientID = found; return found
    }
    private func call(_ path: String, parameters: [String: String] = [:], retry: Bool = true) async throws -> JSONValue {
        try validate(); let version = revision, id = try await identity()
        guard var url = URLComponents(string: path.hasPrefix("https:") ? path : "https://api-v2.soundcloud.com" + path), url.host == "api-v2.soundcloud.com" else { throw HarborError(code: "music-soundcloud-host") }
        url.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } + [URLQueryItem(name: "client_id", value: id)]
        guard let raw = url.string else { throw HarborError(code: "music-soundcloud-host") }
        let result = try await fetch(raw); try validate(version)
        if [401, 403].contains(result.status), retry {
            if clientID == id { clientID = nil }
            return try await call(path, parameters: parameters, retry: false)
        }
        guard result.ok else { health = .offline; throw HarborError(code: "music-soundcloud-unavailable") }
        let parsed = try JSONDecoder().decode(JSONValue.self, from: result.bytes()); health = .healthy; return parsed
    }
    static func track(_ value: JSONValue) -> MusicTrack? {
        guard value["streamable"] != .bool(false), ["ALLOW", "MONETIZE"].contains(value["policy"].string?.uppercased() ?? "ALLOW"),
              let id = value["id"].integer, let title = value["title"].string, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let seconds = UInt64(max(0, value["full_duration"].integer ?? value["duration"].integer ?? 0) / 1000)
        let artist = value["publisher_metadata"]["artist"].string ?? value["user"]["username"].string ?? "Unknown artist"
        let art = value["artwork_url"].string ?? value["user"]["avatar_url"].string ?? ""
        return .init(id: "soundcloud:\(id)", connectorId: "soundcloud", sourceId: String(id), playbackUrl: nil, title: title, artist: artist,
            album: value["publisher_metadata"]["album_title"].string, artwork: art.replacingOccurrences(of: "-large.jpg", with: "-t500x500.jpg"), durationSeconds: seconds, durationLabel: "\(seconds / 60):\(String(format: "%02d", seconds % 60))")
    }
    private static func playlist(_ value: JSONValue) -> MusicCatalogPlaylist? {
        guard let title = value["title"].string else { return nil }
        let id = value["urn"].string.flatMap { $0.hasPrefix("soundcloud:system-playlists:") ? $0 : nil } ?? value["id"].integer.map(String.init)
        guard let id else { return nil }
        let covers = ([value["artwork_url"], value["calculated_artwork_url"]] + value["tracks"].array.map { $0["artwork_url"] }).compactMap(\.string)
        var seen = Set<String>()
        return .init(id: id, connectorId: "soundcloud", name: title, artwork: Array(covers.filter { seen.insert($0).inserted }.prefix(4)), trackCount: value["track_count"].integer, subtitle: value["user"]["username"].string)
    }
    func home() async throws -> [MusicCatalogRow] {
        guard enabled else { return [] }
        let selections = try await call("/mixed-selections")["collection"].array
        return selections.prefix(6).compactMap { selection in
            let items = selection["items"]["collection"].array.prefix(12).compactMap(Self.playlist).map(MusicCatalogItem.playlist)
            guard !items.isEmpty, let title = selection["title"].string else { return nil }
            return .init(id: "soundcloud:selections:" + (selection["urn"].string ?? title), title: title, titleLiteral: true, subtitle: selection["description"].string, layout: .covers, source: "soundcloud", items: items)
        }
    }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch {
        guard enabled else { return .init(top: nil, tracks: [], albums: [], artists: [], playlists: []) }
        let params = ["q": String(query.prefix(200)), "limit": String(min(100, max(1, limit))), "linked_partitioning": "1"]
        let result = try await call("/search/tracks", parameters: params)
        let tracks = result["collection"].array.compactMap(Self.track)
        return .init(top: tracks.first.map(MusicCatalogItem.track), tracks: tracks, albums: [], artists: [], playlists: [])
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] { throw HarborError(code: "music-soundcloud-album") }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] {
        guard let id = UInt64(artist.id.split(separator: ":").last ?? "") else { throw HarborError(code: "music-soundcloud-artist") }
        return try await call("/users/\(id)/tracks", parameters: ["limit": "50", "linked_partitioning": "1"])["collection"].array.compactMap(Self.track)
    }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] { try validate(); return [] }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        let items: [MusicCatalogItem] = kind == .tracks ? try await artistTop(artist).map(MusicCatalogItem.track) : []
        return .init(items: items, nextCursor: nil, total: nil, scope: .limited)
    }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] {
        let path: String
        if playlist.id.hasPrefix("soundcloud:system-playlists:") { path = "/system-playlists/" + playlist.id }
        else if let id = UInt64(playlist.id) { path = "/playlists/\(id)" }
        else { throw HarborError(code: "music-soundcloud-playlist") }
        let tracks = try await call(path)["tracks"].array
        var output: [MusicTrack] = []
        for start in stride(from: 0, to: tracks.count, by: 50) {
            let entries = Array(tracks[start..<min(start + 50, tracks.count)])
            let missing = entries.filter { Self.track($0) == nil }.compactMap { $0["id"].integer }.map(String.init)
            let hydrated = missing.isEmpty ? [] : try await call("/tracks", parameters: ["ids": missing.joined(separator: ",")]).array
            let known = Dictionary(hydrated.compactMap { value in value["id"].integer.map { ($0, value) } }, uniquingKeysWith: { first, _ in first })
            output += entries.compactMap { Self.track(known[$0["id"].integer ?? -1] ?? $0) }
        }
        return output
    }
    static func bitrate(_ preset: String) -> Int {
        for part in preset.split(whereSeparator: { $0 == "_" || $0 == "-" }) where part.hasSuffix("k") {
            if let value = Int(part.dropLast()) { return value * 1000 }
        }
        return 0
    }
    static func transcoding(_ value: JSONValue) -> JSONValue? {
        var best: (Int, JSONValue)?
        for entry in value["media"]["transcodings"].array {
            guard let url = entry["url"].string, !url.isEmpty else { continue }
            let proto = entry["format"]["protocol"].string?.lowercased() ?? "", preset = entry["preset"].string?.lowercased() ?? ""
            guard ["progressive", "hls"].contains(proto), !preset.hasPrefix("abr") else { continue }
            let score = (proto == "progressive" ? 4000 : 2000) + bitrate(preset) / 1000 - (entry["snipped"] == .bool(true) ? 8000 : 0)
            if best == nil || score > best!.0 { best = (score, entry) }
        }
        return best?.1
    }
    func resolve(_ track: MusicTrack) async throws -> MusicAudioStream {
        guard let id = UInt64((track.sourceId ?? track.id).split(separator: ":").last ?? "") else { throw HarborError(code: "music-soundcloud-track") }
        let value = try await call("/tracks", parameters: ["ids": String(id)]).array.first ?? .null
        guard Self.track(value) != nil, let selected = Self.transcoding(value), selected["snipped"] != .bool(true), let endpoint = selected["url"].string else { throw HarborError(code: "music-soundcloud-no-stream") }
        let parameters = value["track_authorization"].string.map { ["track_authorization": $0] } ?? [:]
        let resolved = try await call(endpoint, parameters: parameters)
        guard let raw = resolved["url"].string, let url = URL(string: raw), url.scheme == "https", let host = url.host,
              [".sndcdn.com", ".soundcloud.com", ".soundcloud.cloud"].contains(where: host.hasSuffix) else { throw HarborError(code: "music-soundcloud-no-stream") }
        let hls = selected["format"]["protocol"].string == "hls"
        return .init(url: url, httpHeaders: [:], mimeType: hls ? "application/vnd.apple.mpegurl" : selected["format"]["mime_type"].string ?? "audio/mpeg", bitrate: UInt64(Self.bitrate(selected["preset"].string ?? "")))
    }
    func dispose() { disposed = true; revision = UUID(); identityTask?.cancel(); identityTask = nil; clientID = nil }
}
