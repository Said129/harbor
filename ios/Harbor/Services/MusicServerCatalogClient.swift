import Foundation

/// The shared catalog keeps anonymous discovery and the active profile's private
/// server in one route. A private reference never falls back to the public API.
@MainActor final class MusicServerCatalogClient: MusicCatalogCalling {
    let server: SubsonicMusicService
    private let catalog: any MusicCatalogCalling
    private let currentScope: @MainActor () -> PluginExecutionScope
    private let browseTimeout: Duration
    init(server: SubsonicMusicService, catalog: any MusicCatalogCalling = MusicCatalogClient(),
         browseTimeout: Duration = .seconds(12), currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.server = server; self.catalog = catalog; self.browseTimeout = browseTimeout; self.currentScope = currentScope
    }
    private func validate(_ version: UUID) throws {
        try server.validateCatalogScope()
        guard server.scope == currentScope(), version == server.credentialVersion else { throw CancellationError() }
    }
    private func scoped<T: Sendable>(_ work: @MainActor () async throws -> T) async throws -> T {
        let version = server.credentialVersion; try validate(version)
        do { let value = try await work(); try validate(version); return value }
        catch { try validate(version); throw error }
    }
    private func client(_ id: String) -> any MusicCatalogCalling { if id == "subsonic" { return server }; return catalog }
    func home() async throws -> [MusicCatalogRow] {
        try await scoped {
            async let publicRows = Self.rows(catalog, timeout: browseTimeout)
            async let privateRows = Self.rows(server, timeout: browseTimeout)
            let replies = await (publicRows, privateRows)
            var seen = Set<String>()
            // rows::order_rows ranks catalog before subsonic, omits failed
            // sources and retains the first row with a given id.
            return (replies.0 + replies.1).filter { seen.insert($0.id).inserted }
        }
    }
    private static func rows(_ client: any MusicCatalogCalling, timeout: Duration) async -> [MusicCatalogRow] {
        await withTaskGroup(of: [MusicCatalogRow].self) { group in
            group.addTask { do { return try await client.home() } catch { return [] } }
            group.addTask { do { try await Task.sleep(for: timeout) } catch { }; return [] }
            let value = await group.next() ?? []; group.cancelAll(); return value
        }
    }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch {
        try await scoped {
            guard server.configured, server.health != .offline else { return try await catalog.search(query, limit: limit) }
            // Registry fan-out is ordered by connector id: catalog, subsonic.
            async let publicResult = Self.search(catalog, query: query, limit: limit)
            async let privateResult = Self.search(server, query: query, limit: limit)
            let replies = await (publicResult, privateResult)
            return try MusicCatalogMerge.search([replies.0, replies.1], limit: limit)
        }
    }
    private static func search(_ client: any MusicCatalogCalling, query: String, limit: Int) async -> MusicCatalogReply {
        do { return .success(try await client.search(query, limit: limit)) }
        catch is CancellationError { return .cancelled }
        catch { return .failure }
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] {
        try await scoped { try await client(album.connectorId).albumTracks(album) }
    }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] {
        try await scoped { try await client(artist.connectorId).artistTop(artist) }
    }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] {
        try await scoped { try await client(artist.connectorId).artistRows(artist) }
    }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        try await scoped { try await client(artist.connectorId).artistCatalog(artist, kind: kind, cursor: cursor) }
    }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] {
        try await scoped { try await client(playlist.connectorId).playlistTracks(playlist) }
    }
}

extension SubsonicMusicService: MusicCatalogCalling {
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] {
        try validateCatalogScope()
        // The source connector uses MusicConnector's empty artist_rows default.
        return []
    }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        try validateCatalogScope()
        guard cursor == nil else { throw HarborError(code: "music-server-pagination") }
        let items: [MusicCatalogItem]
        switch kind {
        case .tracks: items = try await artistTop(artist).map(MusicCatalogItem.track)
        case .albums: items = []
        }
        return .init(items: items, nextCursor: nil, total: nil, scope: .limited)
    }
}

enum MusicCatalogReply: Sendable { case success(MusicCatalogSearch), failure, cancelled }
enum MusicCatalogMerge {
    private static func identity(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    static func search(_ replies: [MusicCatalogReply], limit: Int) throws -> MusicCatalogSearch {
        if replies.contains(where: { if case .cancelled = $0 { true } else { false } }) { throw CancellationError() }
        let values: [MusicCatalogSearch] = replies.compactMap { if case .success(let value) = $0 { value } else { nil } }
        guard !values.isEmpty else { throw HarborError(code: "music-catalog-unavailable") }
        let maximum = max(0, limit)
        var tracks: [MusicTrack] = [], albums: [MusicCatalogAlbum] = [], artists: [MusicCatalogArtist] = [], playlists: [MusicCatalogPlaylist] = []
        var recordings = Set<[String]>(), albumKeys = Set<[String]>(), artistKeys = Set<String>(), playlistKeys = Set<[String]>()
        let depth = values.map { $0.tracks.count }.max() ?? 0
        for index in 0..<depth {
            for value in values where index < value.tracks.count && tracks.count < maximum {
                let track = value.tracks[index]
                if recordings.insert([identity(track.title), identity(track.artist)]).inserted { tracks.append(track) }
            }
        }
        for value in values {
            for album in value.albums where albums.count < maximum {
                if albumKeys.insert([identity(album.title), identity(album.artist)]).inserted { albums.append(album) }
            }
            for artist in value.artists where artists.count < maximum {
                if artistKeys.insert(identity(artist.name)).inserted { artists.append(artist) }
            }
            for playlist in value.playlists where playlists.count < maximum {
                if playlistKeys.insert([identity(playlist.name), playlist.connectorId]).inserted { playlists.append(playlist) }
            }
        }
        return .init(top: values.compactMap(\.top).first, tracks: tracks, albums: albums, artists: artists, playlists: playlists)
    }
}
