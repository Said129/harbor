import CryptoKit
import Foundation

struct MusicGenre: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let slug: String
    let name: String
    let family: String
    let countries: [String]
    let aliases: [String]
    var searchHints: [String]?
    var deezerId: Int?
    var displayName: String { (10108...10133).contains(id) ? DesktopInterfaceText.value("music.genre." + slug) : name }
}
struct MusicExploreDefinitions: Decodable, Sendable {
    let genres: [MusicGenre]
    let artwork: [String: String]
    let countries: [String]
    let families: [String]
    let editorialScenes: [String]
    let playlistScenes: [String]
}
struct MusicExploreAsset: Decodable, Sendable {
    struct Program: Decodable, Sendable { let source: String; let sha256: String }
    let schema: Int
    let reference: String
    let inputs: [String: String]
    let definitions: MusicExploreDefinitions
    let mobileExcludedGenreIds: [Int]
    let program: Program
    private static let cached: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "MusicExploreAssets", withExtension: "json") else { throw HarborError(code: "music-explore-assets") }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw HarborError(code: "music-explore-assets") }
        let asset = try JSONDecoder().decode(Self.self, from: data)
        let digest = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987", asset.inputs.count == 6,
              digest == asset.program.sha256, digest == "1994f4118a92cf82eeb2456b5e5b77677bdd1fd92c493dd370212dfa385c6e22",
              asset.definitions.genres.count == 159, asset.definitions.families.count == 8,
              Set(asset.definitions.genres.map(\.id)).count == 159, asset.mobileExcludedGenreIds == [95] else { throw HarborError(code: "music-explore-assets") }
        return asset
    }
    static func read() throws -> Self { try cached.get() }
    var visibleGenres: [MusicGenre] { definitions.genres.filter { !mobileExcludedGenreIds.contains($0.id) } }
}
struct MusicGenreFilters: Codable, Equatable, Sendable {
    var query = ""
    var countries: [String] = []
    var family = ""
    var active: Bool { !query.isEmpty || !countries.isEmpty || !family.isEmpty }
    static func read(_ raw: String, definitions: MusicExploreDefinitions?) -> Self {
        guard let data = raw.data(using: .utf8), var value = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        value.query = String(value.query.prefix(120))
        value.countries = value.countries.filter { definitions?.countries.contains($0) == true }
        if definitions?.families.contains(value.family) != true { value.family = "" }
        return value
    }
    var encoded: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
}
struct MusicGenreSelection: Decodable, Sendable {
    let tracks: [MusicTrack]
    let positions: [Int?]
    let artists: [MusicCatalogItem]
    var albums: [MusicCatalogItem]?
    var playlists: [MusicCatalogItem]?
    var popularity: [String: Double]?
    var done: Bool?
}
