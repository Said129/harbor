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
    let lastfm: LastFmMusicService?
    let catalog: any MusicCatalogCalling
    private let policy = MusicSourcePolicy()
    private let localRecords: @MainActor () -> [MusicRecord]
    private let localRevision: (@MainActor () -> UInt64)?
    private var indexedRevision: UInt64?
    private var localIndex: MusicLocalRecordIndex?
    private let currentScope: @MainActor () -> PluginExecutionScope
    init(server: SubsonicMusicService, playlists: MusicPlaylistStore,
         localRecords: @escaping @MainActor () -> [MusicRecord], localRevision: (@MainActor () -> UInt64)? = nil,
         lyrics: MusicLyricsClient? = nil, soundcloud: SoundCloudMusicService? = nil, jellyfin: JellyfinMusicService? = nil, plex: PlexMusicService? = nil, audio: MusicAudioPreferences? = nil, lastfm: LastFmMusicService? = nil, catalog: (any MusicCatalogCalling)? = nil, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.server = server; scope = server.scope; self.playlists = playlists
        self.localRecords = localRecords; self.localRevision = localRevision; self.currentScope = currentScope
        self.lyrics = lyrics
        self.soundcloud = soundcloud; self.jellyfin = jellyfin; self.plex = plex
        self.audio = audio
        self.lastfm = lastfm
        self.catalog = catalog ?? MusicCatalogClient()
    }
    /// A fresh artist-metadata client bound to this session's profile scope. The
    /// expanded player sits outside the music screen, so it cannot inherit one.
    func makeArtistMetadataClient() -> MusicArtistClient { MusicArtistClient(scope: scope, currentScope: currentScope) }
    func validate() throws {
        try server.validateCatalogScope()
        guard scope == currentScope(), playlists.owner == scope.owner,
              audio == nil || audio?.owner == scope.owner,
              lastfm == nil || lastfm?.scope == scope else { throw CancellationError() }
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
    func alternativeSources(for track: MusicTrack) async throws -> [MusicSourceCandidate] {
        let candidates = try await sources(for: track)
        try Task.checkCancellation(); try validate()
        return try policy.selectable(candidates, current: track)
    }
    func replacingSource(_ selected: MusicTrack, in queue: [MusicTrack], at index: Int) throws -> [MusicTrack] {
        try validate()
        return try policy.replace(queue, at: index, with: selected)
    }

    func continuationHistory() -> [MusicTrack] {
        guard (try? validate()) != nil else { return [] }
        let collections = MusicCollections.shared
        collections.prepare(owner: scope.owner)
        let library = localRecords()
        return collections.tracks(.recent, store: playlists, library: library, owner: scope.owner) +
            collections.tracks(.liked, store: playlists, library: library, owner: scope.owner)
    }

    func loadContinuation(mode: MusicQueueContinuationMode, origin: MusicQueueOrigin?, current: MusicTrack,
                          queue: [MusicTrack], history: [MusicTrack]) async throws -> MusicQueueContinuationResult {
        try validate()
        let excluded = MusicQueueContinuationRules.excluded(current: current, queue: queue, history: history,
                                                              discover: mode == .discover)
        let allowVideo = current.mediaKind == "video"
        if mode == .discover || origin?.kind == "similar" {
            let candidates = try await catalog.search(current.artist, limit: 40).tracks
            try validate()
            let tracks = MusicQueueContinuationRules.fresh(candidates, excluded: excluded, allowVideo: allowVideo)
            return .init(tracks: tracks, origin: origin, exhausted: tracks.isEmpty)
        }

        let candidates: [MusicTrack]
        if let origin {
            switch origin.kind {
            case "playlist":
                candidates = playlists.recordings(in: origin.id, local: localRecords())
            case "catalog":
                candidates = try await catalogTracks(from: origin, current: current)
            case "liked", "recent":
                let collection = MusicPersonalCollection(rawValue: origin.kind) ?? .liked
                let collections = MusicCollections.shared
                collections.prepare(owner: scope.owner)
                candidates = collections.tracks(collection, store: playlists, library: localRecords(), owner: scope.owner)
            default:
                candidates = []
            }
        } else {
            candidates = try await sourceTracks(for: current)
        }
        try validate()
        let tracks = MusicQueueContinuationRules.fresh(candidates, excluded: excluded, allowVideo: allowVideo)
        return .init(tracks: tracks, origin: origin, exhausted: tracks.isEmpty)
    }

    private func catalogTracks(from origin: MusicQueueOrigin, current: MusicTrack) async throws -> [MusicTrack] {
        let parts = origin.id.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[2].isEmpty else { return [] }
        let connector = String(parts[0]), itemID = String(parts[2])
        switch parts[1] {
        case "album":
            return try await catalog.albumTracks(.init(id: itemID, connectorId: connector, title: origin.name,
                                                        artist: current.artist, artwork: current.artwork,
                                                        year: nil, trackCount: nil, explicit: nil))
        case "artist":
            return try await catalog.artistTop(.init(id: itemID, connectorId: connector, name: origin.name,
                                                      artwork: current.artwork, subtitle: nil))
        case "playlist":
            return try await catalog.playlistTracks(.init(id: itemID, connectorId: connector, name: origin.name,
                                                            artwork: [], trackCount: nil, subtitle: nil))
        case "station":
            return try await catalog.stationTracks(.init(id: itemID, connectorId: connector, name: origin.name,
                                                           artwork: current.artwork, subtitle: nil))
        default:
            return []
        }
    }

    private func sourceTracks(for current: MusicTrack) async throws -> [MusicTrack] {
        let connector = current.collectionOrigin?.connectorId ?? current.connectorId ?? ""
        if connector == "local" { return localRecords().map(\.local.track) }
        let source: (any MusicCatalogCalling)?
        switch connector {
        case "subsonic": source = server
        case "soundcloud": source = soundcloud?.enabled == true ? soundcloud : nil
        case "jellyfin": source = jellyfin?.configured == true ? jellyfin : nil
        case "plex": source = plex?.configured == true ? plex : nil
        default: source = nil
        }
        guard let source else { return [] }
        return try await source.search(current.artist, limit: 40).tracks
    }

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
        try validate()
        do { _ = try await server.submitScrobble(track, startedAtSeconds: startedAt) }
        catch is CancellationError { throw CancellationError() }
        catch { Diagnostics.shared.recordFailure(error) }
        try validate()
        try await lastfm?.scrobble(track, startedAt: startedAt)
    }
}
