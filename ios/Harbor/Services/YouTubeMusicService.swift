import Foundation
import Observation

/// The source Desktop plays from by default: YouTube Music search, and the audio the
/// player endpoint hands to a visionOS client. No account is involved. Without a visitor
/// id YouTube answers "sign in to confirm you're not a bot", so the id a search response
/// names is kept and sent with every player request.
@MainActor @Observable final class YouTubeMusicService: MusicCatalogCalling {
    let scope: PluginExecutionScope
    private(set) var enabled: Bool
    private(set) var health = MusicSourceCandidate.Health.unknown
    var connectionRevision: UUID { revision }
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let network: any HarborNativeNetworkCalling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var visitor: String?
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var revision = UUID()
    private var key: String { Self.enabledKey(scope.owner) }

    nonisolated static let songsFilter = "EgWKAQIIAWoMEA4QChADEAQQCRAF"
    nonisolated static let visitorKey = "music.youtube.visitor.v1"
    nonisolated static let musicAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    nonisolated static let visionAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
    private static let searchURL = "https://music.youtube.com/youtubei/v1/search?alt=json"
    private static let playerURL = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
    nonisolated private static let terminalReasons =["private video", "has been removed", "no longer available", "terminated", "copyright", "not available in your country", "video unavailable"]
    nonisolated static func enabledKey(_ owner: String) -> String { "music.youtube.enabled." + EBookShelf.hash(owner) }

    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         network: any HarborNativeNetworkCalling = HarborNativeNetwork(), defaults: UserDefaults = .standard) {
        self.scope = scope; self.currentScope = currentScope; self.network = network; self.defaults = defaults
        // Desktop plays from YouTube without any setup, so the source starts on.
        enabled = defaults.object(forKey: Self.enabledKey(scope.owner)) as? Bool ?? true
        let stored = defaults.string(forKey: Self.visitorKey)
        visitor = stored.flatMap { !$0.isEmpty && $0.utf8.count <= 512 ? $0 : nil }
    }
    func setEnabled(_ value: Bool) {
        guard !disposed, scope == currentScope() else { return }
        enabled = value; revision = UUID(); defaults.set(value, forKey: key)
    }
    private func validate(_ version: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, enabled, scope == currentScope(), version == nil || version == revision else { throw CancellationError() }
    }
    func dispose() { disposed = true; revision = UUID() }

    // MARK: Transport

    private func post(_ url: String, headers: [String: String], body: JSONValue) async throws -> JSONValue {
        try validate(); let version = revision
        var request = HarborNetworkRequest(url: url)
        request.method = "POST"; request.headers = headers
        request.bodyBase64 = try JSONEncoder().encode(body).base64EncodedString()
        request.openHeaders = true; request.publicNetworkOnly = true
        request.timeoutMs = 12_000; request.maxResponseBytes = 4 * 1024 * 1024
        let result = try await network.perform(request); try validate(version)
        guard result.ok else { health = .offline; throw HarborError(code: "music-youtube-unavailable") }
        do { return try JSONDecoder().decode(JSONValue.self, from: result.bytes()) }
        catch { health = .offline; throw HarborError(code: "music-youtube-response") }
    }
    private func musicSearch(_ query: String) async throws -> JSONValue {
        let body: JSONValue = .object(["query": .string(query), "params": .string(Self.songsFilter), "context": Self.musicContext(Date())])
        var headers = ["Content-Type": "application/json", "User-Agent": Self.musicAgent, "Origin": "https://music.youtube.com", "Cookie": "SOCS=CAI"]
        if let visitor { headers["X-Goog-Visitor-Id"] = visitor }
        let response = try await post(Self.searchURL, headers: headers, body: body)
        if visitor == nil { remember(response["responseContext"]["visitorData"].string) }
        return response
    }
    private func remember(_ value: String?) {
        guard visitor == nil, let value, !value.isEmpty, value.utf8.count <= 512 else { return }
        visitor = value; defaults.set(value, forKey: Self.visitorKey)
    }
    private func forgetVisitor() { visitor = nil; defaults.removeObject(forKey: Self.visitorKey) }
    private func ensureVisitor() async throws -> String {
        if let visitor { return visitor }
        _ = try await musicSearch("music")
        guard let visitor else { throw HarborError(code: "music-youtube-visitor") }
        return visitor
    }

    // MARK: Catalog

    private static let empty = MusicCatalogSearch(top: nil, tracks: [], albums: [], artists: [], playlists: [])
    func home() async throws -> [MusicCatalogRow] { [] }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch {
        guard enabled else { return Self.empty }
        try validate(); let version = revision
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if text.isEmpty { return Self.empty }
        let response = try await musicSearch(text); try validate(version)
        let tracks = Array(Self.tracks(from: response).prefix(min(100, max(1, limit))))
        health = .healthy
        return .init(top: tracks.first.map(MusicCatalogItem.track), tracks: tracks, albums: [], artists: [], playlists: [])
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] { throw HarborError(code: "music-youtube-unsupported") }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] { try await search(artist.name, limit: 20).tracks }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] { try validate(); return [] }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        let items: [MusicCatalogItem] = kind == .tracks && cursor == nil ? try await artistTop(artist).map(MusicCatalogItem.track) : []
        return .init(items: items, nextCursor: nil, total: nil, scope: .limited)
    }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] { throw HarborError(code: "music-youtube-unsupported") }

    // MARK: Playback

    enum Verdict { case stream(MusicAudioStream), challenge, unavailable }
    func resolve(_ track: MusicTrack) async throws -> MusicAudioStream {
        guard let video = Self.videoID(track) else { throw HarborError(code: "music-youtube-track") }
        try validate(); let version = revision
        var retried = false
        while true {
            let id = try await ensureVisitor()
            let headers = ["Content-Type": "application/json", "User-Agent": Self.visionAgent, "Origin": "https://www.youtube.com",
                           "X-Youtube-Client-Name": "101", "X-Youtube-Client-Version": "1.02", "X-Goog-Visitor-Id": id]
            let response = try await post(Self.playerURL, headers: headers, body: Self.playerBody(video)); try validate(version)
            switch Self.verdict(response) {
            case .stream(let stream): health = .healthy; return stream
            case .challenge where !retried: retried = true; forgetVisitor()
            case .challenge: health = .degraded; throw HarborError(code: "music-youtube-challenge")
            case .unavailable: throw HarborError(code: "music-youtube-unavailable")
            }
        }
    }

    // MARK: Pure rules

    nonisolated static func clientVersion(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "1.%04d%02d%02d.01.00", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }
    nonisolated static func musicContext(_ date: Date) -> JSONValue {
        .object(["client": .object(["clientName": .string("WEB_REMIX"), "clientVersion": .string(clientVersion(date)), "hl": .string("en"), "gl": .string("US")]), "user": .object([:])])
    }
    nonisolated static func playerBody(_ video: String) -> JSONValue {
        .object(["videoId": .string(video), "contentCheckOk": .bool(true), "racyCheckOk": .bool(true),
                 "context": .object(["client": .object(["clientName": .string("VISIONOS"), "clientVersion": .string("1.02"), "deviceMake": .string("Apple"),
                                                         "deviceModel": .string("RealityDevice17,1"), "userAgent": .string(visionAgent), "osName": .string("visionOS"),
                                                         "osVersion": .string("26.5.23O471"), "hl": .string("en"), "timeZone": .string("UTC"), "utcOffsetMinutes": .integer(0)]),
                                      "user": .object([:])])])
    }
    nonisolated static func videoID(_ track: MusicTrack) -> String? {
        var raw = track.sourceId ?? track.id
        if raw.hasPrefix("youtube:") { raw.removeFirst("youtube:".count) }
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return raw.count == 11 && raw.allSatisfy(allowed.contains) ? raw : nil
    }
    nonisolated static func verdict(_ response: JSONValue) -> Verdict {
        let status = response["playabilityStatus"]["status"].string ?? "OK"
        if status != "OK" {
            let reason = (response["playabilityStatus"]["reason"].string ?? "").lowercased()
            if status == "ERROR" || terminalReasons.contains(where: reason.contains) { return .unavailable }
            return .challenge
        }
        return stream(response).map(Verdict.stream) ?? .challenge
    }
    /// AAC first, as it plays everywhere; Opus when only that is offered. Scrambled
    /// formats carry no url and are skipped.
    nonisolated static func stream(_ response: JSONValue) -> MusicAudioStream? {
        let formats = response["streamingData"]["adaptiveFormats"].array.filter { ($0["mimeType"].string ?? "").hasPrefix("audio/") }
        func usable(_ format: JSONValue) -> URL? {
            guard let raw = format["url"].string, let url = URL(string: raw), url.scheme == "https", let host = url.host, host.hasSuffix(".googlevideo.com") else { return nil }
            return url
        }
        let chosen = [140, 251].lazy.compactMap { itag in formats.first { $0["itag"].integer == itag && usable($0) != nil } }.first
            ?? formats.filter { usable($0) != nil }.max { ($0["bitrate"].integer ?? 0) < ($1["bitrate"].integer ?? 0) }
        guard let chosen, let url = usable(chosen) else { return nil }
        let mime = chosen["mimeType"].string?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "audio/mp4"
        return .init(url: url, httpHeaders: ["User-Agent": visionAgent], mimeType: mime, bitrate: UInt64(max(0, chosen["bitrate"].integer ?? 0)))
    }
    nonisolated static func tracks(from response: JSONValue) -> [MusicTrack] {
        let tab = response["contents"]["tabbedSearchResultsRenderer"]["tabs"].array.first ?? .null
        var output: [MusicTrack] = [], seen = Set<String>()
        for section in tab["tabRenderer"]["content"]["sectionListRenderer"]["contents"].array {
            for item in section["musicShelfRenderer"]["contents"].array {
                if let track = track(item["musicResponsiveListItemRenderer"]), seen.insert(track.id).inserted { output.append(track) }
            }
        }
        return output
    }
    nonisolated static func track(_ row: JSONValue) -> MusicTrack? {
        guard row["musicItemRendererDisplayPolicy"].string != "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT",
              let video = row["playlistItemData"]["videoId"].string, video.count == 11 else { return nil }
        let columns = row["flexColumns"].array
        guard columns.count >= 2 else { return nil }
        func runs(_ column: JSONValue) -> [String] { column["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"].array.compactMap { $0["text"].string } }
        let title = runs(columns[0]).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var groups: [String] = [], current = ""
        for text in runs(columns[1]) {
            if text.trimmingCharacters(in: .whitespaces) == "\u{2022}" { groups.append(current); current = "" } else { current += text }
        }
        groups.append(current)
        groups = groups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if groups.count > 2, ["Song", "Video"].contains(groups[0]) { groups.removeFirst() }
        let duration = groups.last.flatMap { seconds($0) != nil ? $0 : nil }
        if duration != nil { groups.removeLast() }
        let artist = groups.first ?? "Unknown artist"
        let album = groups.count > 1 ? groups[1] : nil
        let total = duration.flatMap(seconds) ?? 0
        let art = row["thumbnail"]["musicThumbnailRenderer"]["thumbnail"]["thumbnails"].array.last?["url"].string ?? ""
        var track = MusicTrack(id: "youtube:" + video, connectorId: "youtube", sourceId: video, playbackUrl: nil, title: title, artist: artist, album: album,
                               artwork: artwork(art), durationSeconds: total, durationLabel: duration ?? "")
        if row["badges"].array.contains(where: { $0["musicInlineBadgeRenderer"]["icon"]["iconType"].string == "MUSIC_EXPLICIT_BADGE" }) { track.explicit = true }
        return track
    }
    nonisolated static func seconds(_ label: String) -> UInt64? {
        let parts = label.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        return parts.reduce(UInt64(0)) { $0 * 60 + (UInt64($1) ?? 0) }
    }
    nonisolated static func artwork(_ raw: String) -> String {
        guard let range = raw.range(of: #"=w\d+-h\d+"#, options: .regularExpression) else { return raw }
        return raw.replacingCharacters(in: range, with: "=w544-h544")
    }
}
