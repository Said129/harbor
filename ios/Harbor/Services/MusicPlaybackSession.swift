import Foundation

@MainActor final class MusicPlaybackSession: MusicPlaybackResolving {
    let scope: PluginExecutionScope
    let server: SubsonicMusicService
    let playlists: MusicPlaylistStore
    let lyrics: MusicLyricsClient?
    let plex: PlexMusicService?
    let jellyfin: JellyfinMusicService?
    let soundcloud: SoundCloudMusicService?
    let audio: MusicAudioPreferences?
    private let policy = MusicSourcePolicy()
    private let localRecords: @MainActor () -> [MusicRecord]
    private let localRevision: (@MainActor () -> UInt64)?
    private var indexedRevision: UInt64?
    private var localIndex: MusicLocalRecordIndex?
    private let currentScope: @MainActor () -> PluginExecutionScope
    init(server: SubsonicMusicService, playlists: MusicPlaylistStore,
         localRecords: @escaping @MainActor () -> [MusicRecord], localRevision: (@MainActor () -> UInt64)? = nil,
         lyrics: MusicLyricsClient? = nil, soundcloud: SoundCloudMusicService? = nil, jellyfin: JellyfinMusicService? = nil, plex: PlexMusicService? = nil, audio: MusicAudioPreferences? = nil, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.server = server; scope = server.scope; self.playlists = playlists
        self.localRecords = localRecords; self.localRevision = localRevision; self.currentScope = currentScope
        self.lyrics = lyrics
        self.soundcloud = soundcloud; self.jellyfin = jellyfin; self.plex = plex
        self.audio = audio
    }
    func validate() throws {
        try server.validateCatalogScope()
        guard scope == currentScope(), playlists.owner == scope.owner,
              audio == nil || audio?.owner == scope.owner else { throw CancellationError() }
    }
    func localRecord(_ track: MusicTrack) -> MusicRecord? {
        guard (try? validate()) != nil, track.connectorId == "local" else { return nil }
        guard let revision = localRevision?() else { return MusicLocalRecordIndex(localRecords()).record(track) }
        if indexedRevision != revision { localIndex = MusicLocalRecordIndex(localRecords()); indexedRevision = revision }
        return localIndex?.record(track)
    }
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution {
        try validate()
        if track.connectorId == "catalog" || track.connectorId == nil && track.playbackUrl == nil {
            let candidates = try await sources(for: track)
            guard let choice = try policy.choose(track, candidates: candidates, preferred: UserDefaults.standard.string(forKey: "harbor.music.preferredSource")) else { throw HarborError(code: "music-source-required") }
            var resolution = try await resolveSelected(choice.track)
            resolution.recording = choice.track; return resolution
        }
        return try await resolveSelected(track)
    }
    func sources(for track: MusicTrack) async throws -> [MusicSourceCandidate] {
        try validate()
        let version = server.credentialVersion, cloudVersion = soundcloud?.connectionRevision, jellyfinVersion = jellyfin?.credentialVersion, plexVersion = plex?.credentialVersion
        let locals = localRecords().map(\.local.track)
        async let localMatches = MusicRecordingMatching.ranked(locals, for: track)
        async let serverMatches = matching(server.configured ? server : nil, track: track)
        async let cloudMatches = matching(soundcloud?.enabled == true ? soundcloud : nil, track: track)
        async let jellyfinMatches = matching(jellyfin?.configured == true ? jellyfin : nil, track: track)
        async let plexMatches = matching(plex?.configured == true ? plex : nil, track: track)
        let replies = try await (localMatches, serverMatches, cloudMatches, jellyfinMatches, plexMatches)
        try validate()
        guard version == server.credentialVersion, cloudVersion == soundcloud?.connectionRevision, jellyfinVersion == jellyfin?.credentialVersion, plexVersion == plex?.credentialVersion else { throw CancellationError() }
        var values: [MusicSourceCandidate] = []
        if track.playbackUrl != nil || localRecord(track) != nil {
            values.append(.init(connectorId: track.connectorId ?? "direct", connectorName: track.connectorId ?? "Direct stream", health: .healthy, track: track))
        }
        values += replies.0.prefix(3).map { .init(connectorId: "local", connectorName: "Local file", health: .healthy, track: $0) }
        values += replies.1.prefix(3).map { .init(connectorId: "subsonic", connectorName: "Subsonic", health: server.health, track: $0) }
        values += replies.2.prefix(3).map { .init(connectorId: "soundcloud", connectorName: "SoundCloud", health: soundcloud?.health ?? .unknown, track: $0) }
        values += replies.3.prefix(3).map { .init(connectorId: "jellyfin", connectorName: "Jellyfin", health: jellyfin?.health ?? .unknown, track: $0) }
        values += replies.4.prefix(3).map { .init(connectorId: "plex", connectorName: "Plex", health: plex?.health ?? .unknown, track: $0) }
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }
    private func matching(_ client: (any MusicCatalogCalling)?, track: MusicTrack) async throws -> [MusicTrack] {
        guard let client else { return [] }
        do {
            let result = try await client.search(track.artist + " " + track.title, limit: 20)
            return try await MusicRecordingMatching.ranked(result.tracks, for: track)
        } catch is CancellationError { throw CancellationError() }
        catch { return [] }
    }
    func choose(_ selected: MusicTrack, for requested: MusicTrack) throws -> MusicTrack { try validate(); return try policy.adopt(selected, requested: requested) }
    private func resolveSelected(_ track: MusicTrack) async throws -> MusicPlaybackResolution {
        try validate(); let version = server.credentialVersion
        let cloudVersion = soundcloud?.connectionRevision
        guard playlists.remember([track]) else { throw HarborError(code: "music-store") }
        if track.connectorId == "plex" {
            guard let plex else { throw HarborError(code: "music-source-required") }
            let resolution = try await plex.resolve(track); try validate(); return resolution
        }
        if track.connectorId == "jellyfin" {
            guard let jellyfin else { throw HarborError(code: "music-source-required") }
            let resolution = try await jellyfin.resolve(track); try validate(); return resolution
        }
        let stream: MusicAudioStream
        if let record = localRecord(track) {
            stream = .init(url: try MusicFileService.file(record, owner: scope.owner), httpHeaders: [:], mimeType: "audio/*", bitrate: 0)
        } else if let raw = track.playbackUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
                  let url = URL(string: raw), ["http", "https", "rtsp", "rtsps", "rtmp", "rtmps"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false {
            stream = .init(url: url, httpHeaders: [:], mimeType: "audio/*", bitrate: 0)
        } else if track.connectorId == "subsonic" {
            stream = try await server.resolve(track)
        } else if track.connectorId == "soundcloud", let soundcloud {
            stream = try await soundcloud.resolve(track)
        } else { throw HarborError(code: "music-source-required") }
        try validate()
        guard track.connectorId != "subsonic" || version == server.credentialVersion else { throw CancellationError() }
        return .init(stream: stream, valid: { [weak self] in
            guard let self, (try? self.validate()) != nil else { return false }
            return (track.connectorId != "subsonic" || version == self.server.credentialVersion) &&
                (track.connectorId != "soundcloud" || cloudVersion == self.soundcloud?.connectionRevision && self.soundcloud?.enabled == true)
        })
    }
    func scrobble(_ track: MusicTrack, startedAt: UInt64) async throws {
        try validate(); _ = try await server.submitScrobble(track, startedAtSeconds: startedAt)
    }
}
