import Foundation
import Observation

@MainActor protocol MusicArtistCalling: AnyObject {
    func roster(_ genre: Int, offset: Int) async throws -> MusicArtistPage
    func audience(_ artists: [MusicArtistReference]) async throws -> [MusicArtistAudience]
    func recording(_ track: MusicTrack) async throws -> MusicRecordingProfile?
}
struct MusicArtistTransport: HarborPluginHostTransport {
    var network: any HarborNativeNetworkCalling = HarborNativeNetwork()
    func perform(_ kind: HarborPluginBridgeKind, payload: JSONValue) async throws -> JSONValue {
        guard kind == .http, let raw = payload["url"].string, let url = URL(string: raw),
              url.scheme == "https", ["musicbrainz.org", "api.deezer.com", "ws.audioscrobbler.com"].contains(url.host?.lowercased() ?? ""),
              url.port == nil, url.user == nil, url.password == nil, payload["opts"]["method"].string == "GET" else { throw HarborError(code: "music-artist-host") }
        let policy = HarborPluginNetworkPolicy(sameSiteHeaders: false, publicOnly: true, openHeaders: false, baseURL: nil, blockedHosts: [])
        return try await HarborNativePluginTransport(policy: policy, network: network).perform(kind, payload: payload)
    }
}
@MainActor @Observable final class MusicArtistClient: MusicArtistCalling {
    let scope: PluginExecutionScope
    private(set) var hasAPIKey = false
    private(set) var keyFailure = false
    private(set) var credentialVersion = UUID()
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let transport: any HarborPluginHostTransport
    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private var runtime: HarborPluginRuntime?
    @ObservationIgnored private var disposed = false
    private var keyName: String { "music-lastfm-api-key-" + EBookShelf.hash(scope.owner) }
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         transport: any HarborPluginHostTransport = MusicArtistTransport()) {
        self.scope = scope; self.currentScope = currentScope; self.transport = transport
        do { apiKey = try KeychainStore().read(keyName, as: String.self); hasAPIKey = apiKey != nil }
        catch { keyFailure = true }
    }
    func saveAPIKey(_ supplied: String) throws {
        try validate()
        let value = supplied.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 200, !value.contains(where: { $0.isNewline }) else { throw HarborError(code: "music-artist-key") }
        if value.isEmpty { try KeychainStore().remove(keyName) }
        else { try KeychainStore().write(value, key: keyName) }
        runtime?.dispose(); runtime = nil; apiKey = value.isEmpty ? nil : value
        hasAPIKey = apiKey != nil; keyFailure = false; credentialVersion = UUID()
    }
    func query<T: Decodable & Sendable>(_ operation: String, arguments: [String: JSONValue] = [:], as type: T.Type) async throws -> T {
        try validate()
        let version = credentialVersion
        if runtime == nil {
            let asset = try MusicArtistAsset.read()
            runtime = HarborPluginRuntime(id: "trusted-music-artists", name: "Harbor Music Artists", source: asset.program.source, format: .raw,
                scope: scope, currentScope: currentScope, transport: transport)
        }
        guard let runtime else { throw CancellationError() }
        var input = arguments; input["operation"] = .string(operation); input["apiKey"] = apiKey.map(JSONValue.string) ?? .null
        let result: JSONValue
        do { result = try await runtime.call("content", arguments: [.object(input)], timeout: 90) }
        catch { try validate(version); throw error }
        try validate(version)
        return try JSONDecoder().decode(type, from: JSONEncoder().encode(result))
    }
    func roster(_ genre: Int, offset: Int = 0) async throws -> MusicArtistPage {
        guard genre != 95, offset >= 0, offset <= 1_000_000 else { throw HarborError(code: "music-artist-page") }
        return try await query("roster", arguments: ["genre": .number(Double(genre)), "offset": .number(Double(offset))], as: MusicArtistPage.self)
    }
    func audience(_ artists: [MusicArtistReference]) async throws -> [MusicArtistAudience] {
        guard artists.count <= 3 else { throw HarborError(code: "music-artist-batch") }
        let value = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(artists))
        return try await query("stats", arguments: ["artists": value], as: [MusicArtistAudience].self)
    }
    func recording(_ track: MusicTrack) async throws -> MusicRecordingProfile? {
        // Catalog enrichment must never receive a private playback URL or replace playback identity.
        var value: [String: JSONValue] = ["id": .string(track.id), "title": .string(track.title), "artist": .string(track.artist),
            "durationSeconds": .number(Double(track.durationSeconds)), "artwork": .string(track.artwork), "durationLabel": .string(track.durationLabel)]
        for (key, text) in [("connectorId", track.connectorId), ("sourceId", track.sourceId), ("album", track.album), ("mediaKind", track.mediaKind), ("isrc", track.isrc)] { if let text { value[key] = .string(text) } }
        let id = UUID().uuidString, version = credentialVersion
        return try await withTaskCancellationHandler {
            try await query("recording", arguments: ["track": .object(value), "requestId": .string(id)], as: MusicRecordingProfile?.self)
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, !self.disposed, self.credentialVersion == version, self.scope == self.currentScope() else { return }
                _ = try? await self.query("cancelRecording", arguments: ["requestId": .string(id)], as: JSONValue.self)
            }
        }
    }
    private func validate(_ version: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { dispose(); throw CancellationError() }
        if let version, version != credentialVersion { throw CancellationError() }
    }
    func dispose() { guard !disposed else { return }; disposed = true; runtime?.dispose(); runtime = nil; apiKey = nil }
}
