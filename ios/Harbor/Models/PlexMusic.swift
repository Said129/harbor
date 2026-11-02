import Foundation

struct PlexMusicAccount: Codable, Sendable {
    let origin: String
    let token: String
    let clientId: String
    let section: String
    let sectionUuid: String?
    let server: String?
}
struct PlexMusicCommand: Encodable, Sendable {
    let action: String
    var query: String?
    var limit: Int?
    var album: MusicCatalogAlbum?
    var artist: MusicCatalogArtist?
    var kind: MusicCatalogKind?
    var playlist: MusicCatalogPlaylist?
    var station: MusicCatalogStation?
    var track: MusicTrack?
    var sessionId: String?
    var reference: String?
}
struct PlexMusicRequest: Encodable, Sendable {
    let action: String
    var address: String?
    var token: String?
    var clientId: String?
    var config: PlexMusicAccount?
    var command: PlexMusicCommand?
}
enum NativeMusicProviderRequest: Encodable, Sendable {
    case jellyfin(JellyfinMusicRequest), plex(PlexMusicRequest)
    func encode(to encoder: Encoder) throws {
        switch self {
        case .jellyfin(let request): try request.encode(to: encoder)
        case .plex(let request): try request.encode(to: encoder)
        }
    }
}
