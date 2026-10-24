import Foundation

protocol MusicCatalogNetworking: Sendable {
    func performMusicCatalog(_ request: MusicCatalogRequest) async throws -> HarborNetworkResponse
}
protocol MusicCatalogCalling: Sendable {
    func home() async throws -> [MusicCatalogRow]
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack]
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack]
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow]
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack]
}
struct MusicCatalogClient: MusicCatalogCalling {
    var network: any MusicCatalogNetworking = HarborNativeNetwork()
    private func request<T: Decodable & Sendable>(_ request: MusicCatalogRequest, as type: T.Type) async throws -> T {
        let response = try await network.performMusicCatalog(request)
        try Task.checkCancellation()
        guard response.ok else { throw HarborError(code: response.status == 504 ? "music-catalog-timeout" : "music-catalog-unavailable") }
        do { return try JSONDecoder().decode(type, from: response.bytes()) }
        catch let error as HarborError { throw error }
        catch { throw HarborError(code: "music-catalog-response-format") }
    }
    func home() async throws -> [MusicCatalogRow] { try await request(.init(operation: "home"), as: [MusicCatalogRow].self) }
    func search(_ query: String, limit: Int = 24) async throws -> MusicCatalogSearch {
        try await request(.init(operation: "search", query: query, limit: limit), as: MusicCatalogSearch.self)
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] {
        try await request(.init(operation: "albumTracks", album: album), as: [MusicTrack].self)
    }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] {
        try await request(.init(operation: "artistTop", artist: artist), as: [MusicTrack].self)
    }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] {
        try await request(.init(operation: "artistRows", artist: artist), as: [MusicCatalogRow].self)
    }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        try await request(.init(operation: "artistCatalog", artist: artist, kind: kind, cursor: cursor), as: MusicCatalogPage.self)
    }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] {
        try await request(.init(operation: "playlistTracks", playlist: playlist), as: [MusicTrack].self)
    }
    func connection() async throws -> MusicCatalogConnection {
        try await request(.init(operation: "connection"), as: MusicCatalogConnection.self)
    }
}
