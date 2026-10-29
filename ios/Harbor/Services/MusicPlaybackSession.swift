import Foundation

@MainActor final class MusicPlaybackSession: MusicPlaybackResolving {
    let scope: PluginExecutionScope
    let server: SubsonicMusicService
    let playlists: MusicPlaylistStore
    private let localRecords: @MainActor () -> [MusicRecord]
    private let currentScope: @MainActor () -> PluginExecutionScope
    init(server: SubsonicMusicService, playlists: MusicPlaylistStore,
         localRecords: @escaping @MainActor () -> [MusicRecord], currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.server = server; scope = server.scope; self.playlists = playlists
        self.localRecords = localRecords; self.currentScope = currentScope
    }
    func validate() throws {
        try server.validateCatalogScope()
        guard scope == currentScope(), playlists.owner == scope.owner else { throw CancellationError() }
    }
    func localRecord(_ track: MusicTrack) -> MusicRecord? {
        guard (try? validate()) != nil, track.connectorId == "local" else { return nil }
        return localRecords().first { $0.id == track.id }
    }
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution {
        try validate(); let version = server.credentialVersion
        guard playlists.remember([track]) else { throw HarborError(code: "music-store") }
        let stream: MusicAudioStream
        if let record = localRecord(track) {
            stream = .init(url: try MusicFileService.file(record, owner: scope.owner), httpHeaders: [:], mimeType: "audio/*", bitrate: 0)
        } else if let raw = track.playbackUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  let url = URL(string: raw), ["http", "https", "rtsp", "rtsps", "rtmp", "rtmps"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false {
            stream = .init(url: url, httpHeaders: [:], mimeType: "audio/*", bitrate: 0)
        } else if track.connectorId == "subsonic" {
            stream = try await server.resolve(track)
        } else { throw HarborError(code: "music-source-required") }
        try validate()
        guard track.connectorId != "subsonic" || version == server.credentialVersion else { throw CancellationError() }
        return .init(stream: stream, valid: { [weak self] in
            guard let self, (try? self.validate()) != nil else { return false }
            return track.connectorId != "subsonic" || version == self.server.credentialVersion
        })
    }
    func scrobble(_ track: MusicTrack, startedAt: UInt64) async throws {
        try validate(); _ = try await server.submitScrobble(track, startedAtSeconds: startedAt)
    }
}
