import CryptoKit
import Foundation

struct MusicArtistReference: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let connectorId: String
    let name: String
    var artwork: String?
    var musicBrainzId: String?
    var catalog: MusicCatalogArtist { .init(id: id, connectorId: connectorId, name: name, artwork: artwork) }
}
struct MusicArtistPage: Decodable, Sendable {
    let artists: [MusicArtistReference]
    let next: Int?
}
struct MusicArtistAudience: Decodable, Sendable, Identifiable {
    let artist: MusicArtistReference
    var fans: UInt64?
    var listeners: UInt64?
    var plays: UInt64?
    var id: String { artist.id }
    func catalog(locale: Locale) -> MusicCatalogArtist {
        var value = artist.catalog
        if let listeners {
            value.subtitle = DesktopInterfaceText.value("music.explore.listeners", variables: ["count": listeners.formatted(.number.locale(locale))]) + " · Last.fm"
            if let plays { value.subtitle? += " · " + DesktopInterfaceText.value("music.explore.scrobbles", variables: ["count": plays.formatted(.number.locale(locale))]) }
        } else if let fans { value.subtitle = fans.formatted(.number.locale(locale)) + " · " + DesktopInterfaceText.value("music.metadata.deezerFans") }
        return value
    }
}
struct MusicRecordingProfile: Decodable, Sendable {
    struct Credit: Decodable, Sendable {
        let name: String
        let role: String
        let artist: MusicArtistReference
        let source: String
        let sourceUrl: String
        var attributes: [String]?
        var workTitle: String?
    }
    struct Provenance: Decodable, Sendable {
        let source: String
        let url: String
        let matchedBy: String
    }
    let catalogTrack: MusicTrack
    let album: MusicCatalogAlbum
    let primaryArtist: MusicArtistReference
    let credits: [Credit]
    let provenance: [Provenance]
    var isrc: String?
}
/// Desktop's MusicArtistProfile (lib/music/artist-profile.ts), produced by the
/// pinned original module. Empty strings mean "not provided".
struct MusicArtistProfile: Decodable, Equatable, Sendable {
    struct Link: Decodable, Hashable, Sendable {
        let url: String
        /// store, merch, official, source, tour or social.
        let kind: String
        let name: String
    }
    let id: String
    let name: String
    var origin: String?
    var began: String?
    var ended: String?
    let aliases: [String]
    let genres: [String]
    let members: [MusicArtistReference]
    let links: [Link]
    var biography: String?
    var biographyUrl: String?
    var artwork: String?
    var wikidataId: String?
    let sources: [MusicArtistReference]
}
/// The part of the original artist ranking that the interface needs.
struct MusicArtistResolution: Decodable, Sendable {
    let canonical: MusicArtistReference?
}
struct MusicArtistAsset: Decodable, Sendable {
    struct Program: Decodable, Sendable { let source: String; let sha256: String }
    let schema: Int
    let reference: String
    let inputs: [String: String]
    let program: Program
    private static let cached: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "MusicArtistAssets", withExtension: "json") else { throw HarborError(code: "music-artist-assets") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 2 * 1024 * 1024 else { throw HarborError(code: "music-artist-assets") }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        let digest = SHA256.hash(data: Data(value.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard value.schema == 1, value.reference == "0834340cec5531650bfe78cd628628702e636987", value.inputs.count == 12,
              digest == value.program.sha256, digest == "02fb263e3723f4ac5e937dd58b9a07bf70cd11e1d0a1e2adc3e9a8d721f5d9bc" else { throw HarborError(code: "music-artist-assets") }
        return value
    }
    static func read() throws -> Self { try cached.get() }
}
