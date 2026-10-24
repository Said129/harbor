import Foundation

struct MusicCatalogAlbum: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let connectorId: String
    let title: String
    let artist: String
    let artwork: String
    var year: Int?
    var trackCount: Int?
    var explicit: Bool?
}
struct MusicCatalogArtist: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let connectorId: String
    let name: String
    var artwork: String?
    var subtitle: String?
}
struct MusicCatalogPlaylist: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let connectorId: String
    let name: String
    let artwork: [String]
    var trackCount: Int?
    var subtitle: String?
}
struct MusicCatalogStation: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let connectorId: String
    let name: String
    let artwork: String
    var subtitle: String?
}
enum MusicCatalogItem: Decodable, Hashable, Sendable, Identifiable {
    case track(MusicTrack), album(MusicCatalogAlbum), artist(MusicCatalogArtist), playlist(MusicCatalogPlaylist), station(MusicCatalogStation)
    private enum CodingKeys: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .kind) {
        case "track": self = .track(try MusicTrack(from: decoder))
        case "album": self = .album(try MusicCatalogAlbum(from: decoder))
        case "artist": self = .artist(try MusicCatalogArtist(from: decoder))
        case "playlist": self = .playlist(try MusicCatalogPlaylist(from: decoder))
        case "station": self = .station(try MusicCatalogStation(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: values, debugDescription: "Unknown pinned music catalog kind")
        }
    }
    var id: String {
        switch self {
        case .track(let value): "track|" + (value.connectorId ?? "") + "|" + value.id
        case .album(let value): "album|" + value.connectorId + "|" + value.id
        case .artist(let value): "artist|" + value.connectorId + "|" + value.id
        case .playlist(let value): "playlist|" + value.connectorId + "|" + value.id
        case .station(let value): "station|" + value.connectorId + "|" + value.id
        }
    }
    var title: String {
        switch self {
        case .track(let value): value.title
        case .album(let value): value.title
        case .artist(let value): value.name
        case .playlist(let value): value.name
        case .station(let value): value.name
        }
    }
    var subtitle: String? {
        switch self {
        case .track(let value): value.artist
        case .album(let value): value.artist
        case .artist(let value): value.subtitle
        case .playlist(let value): value.subtitle
        case .station(let value): value.subtitle
        }
    }
    var artwork: String? {
        switch self {
        case .track(let value): value.artwork
        case .album(let value): value.artwork
        case .artist(let value): value.artwork
        case .playlist(let value): value.artwork.first
        case .station(let value): value.artwork
        }
    }
    var isArtist: Bool { if case .artist = self { true } else { false } }
}
enum MusicCatalogKind: String, Codable, CaseIterable, Sendable { case tracks, albums }
enum MusicCatalogScope: String, Decodable, Sendable { case catalog, top, limited }
enum MusicCatalogLayout: String, Decodable, Sendable { case covers, circles, trackGrid, wide }
struct MusicCatalogRow: Decodable, Sendable, Identifiable {
    let id: String
    let title: String
    let titleLiteral: Bool
    let subtitle: String?
    let layout: MusicCatalogLayout
    let source: String
    let items: [MusicCatalogItem]
    var displayTitle: String { titleLiteral ? title : DesktopInterfaceText.value(title) }
}
struct MusicCatalogPage: Decodable, Sendable {
    let items: [MusicCatalogItem]
    let nextCursor: String?
    let total: UInt64?
    let scope: MusicCatalogScope
}
struct MusicCatalogSearch: Decodable, Sendable {
    let top: MusicCatalogItem?
    let tracks: [MusicTrack]
    let albums: [MusicCatalogAlbum]
    let artists: [MusicCatalogArtist]
    let playlists: [MusicCatalogPlaylist]
}
struct MusicCatalogConnection: Decodable, Sendable {
    let id: String
    let name: String
    let status: String
    let capabilities: [String]
    let anonymous: Bool
}
struct MusicCatalogRequest: Encodable, Sendable {
    let operation: String
    var query: String?
    var limit: Int?
    var album: MusicCatalogAlbum?
    var artist: MusicCatalogArtist?
    var kind: MusicCatalogKind?
    var cursor: String?
    var playlist: MusicCatalogPlaylist?
}
