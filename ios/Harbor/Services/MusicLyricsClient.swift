import CryptoKit
import Foundation

struct MusicLyricLine: Codable, Equatable, Sendable { let at: Double; let text: String }

struct MusicLyricsTransport: HarborPluginHostTransport {
    var network: any HarborNativeNetworkCalling = HarborNativeNetwork()
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        guard kind == .http, let raw = payload["url"].string, let url = URL(string: raw),
              url.scheme == "https", url.host == "lrclib.net", url.port == nil, url.user == nil, url.password == nil,
              ["/api/get", "/api/search"].contains(url.path), payload["opts"]["method"].string == "GET" else { throw HarborError(code: "music-lyrics-host") }
        return try await HarborNativePluginTransport(policy: .init(sameSiteHeaders: false, publicOnly: true, openHeaders: false, baseURL: nil, blockedHosts: []), network: network).perform(kind, payload: payload)
    }
}

@MainActor final class MusicLyricsClient {
    let scope: PluginExecutionScope
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let transport: any HarborPluginHostTransport
    private var runtime: HarborPluginRuntime?
    private var disposed = false
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         transport: any HarborPluginHostTransport = MusicLyricsTransport()) {
        self.scope = scope; self.currentScope = currentScope; self.transport = transport
    }
    private func validate() throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { throw CancellationError() }
    }
    func query(_ input: [String: JSONValue]) async throws -> JSONValue {
        try validate()
        if runtime == nil {
            guard let url = Bundle.main.url(forResource: "MusicLyricsAssets", withExtension: "json") else { throw HarborError(code: "music-lyrics-assets") }
            let asset = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
            guard asset["schema"].integer == 1, let source = asset["program"]["source"].string,
                  let expected = asset["program"]["sha256"].string,
                  expected == "8e6b5ce889dc352303c3516742d41379522f6d0e709a5f2a35763c009b61a784",
                  SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == expected else { throw HarborError(code: "music-lyrics-assets") }
            runtime = HarborPluginRuntime(id: "trusted-music-lyrics", name: "Harbor Music Lyrics", source: source, format: .raw,
                scope: scope, currentScope: currentScope, transport: transport)
        }
        guard let runtime else { throw CancellationError() }
        let value = try await runtime.call("content", arguments: [.object(input)], timeout: 30)
        try validate(); return value
    }
    func load(_ track: MusicTrack) async throws -> [MusicLyricLine]? {
        // Only identity metadata goes to LRCLIB; never send a private stream URL.
        var metadata: [String: JSONValue] = ["id": .string(track.id), "title": .string(track.title), "artist": .string(track.artist), "durationSeconds": .number(Double(track.durationSeconds))]
        if let album = track.album { metadata["album"] = .string(album) }
        if let connector = track.connectorId { metadata["connectorId"] = .string(connector) }
        let value = try await query(["operation": .string("load"), "track": .object(metadata)])
        return try JSONDecoder().decode([MusicLyricLine]?.self, from: JSONEncoder().encode(value))
    }
    func dispose() { disposed = true; runtime?.dispose(); runtime = nil }
}

enum MusicLyricsTiming {
    static func index(_ lines: [MusicLyricLine], at seconds: Double) -> Int? {
        guard seconds.isFinite else { return nil }
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = low + (high - low) / 2
            if lines[mid].at <= seconds { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }
}
