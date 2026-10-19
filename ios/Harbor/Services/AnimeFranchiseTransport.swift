import Foundation

enum AnimeFranchiseRequest: Hashable, Sendable {
    case kitsu(Int), related(Int), anilist(Int)
    case relations(source: String, id: Int)
    case mapping(String)

    var url: String {
        get throws {
            switch self {
            case .kitsu(let id), .related(let id):
                guard id > 0 else { throw HarborError(code: "anime-id") }
                let suffix = self == .kitsu(id) ? "" : "/media-relationships?include=destination&page[limit]=12"
                return "https://kitsu.io/api/edge/anime/\(id)" + suffix
            case .relations(let source, let id):
                guard ["kitsu", "myanimelist", "anilist", "anidb"].contains(source), id > 0 else { throw HarborError(code: "anime-id") }
                return "https://relations.yuna.moe/api/ids?source=\(source)&id=\(id)"
            case .mapping(let id):
                guard let identity = AnimePublicIdentity(id) else { throw HarborError(code: "anime-id") }
                return "https://api.ani.zip/mappings?\(identity.mappingKey)=\(identity.number)"
            case .anilist: throw HarborError(code: "anime-id")
            }
        }
    }
}

struct AnimePublicIdentity: Sendable {
    let provider: String
    let number: String
    init?(_ raw: String) {
        if raw.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil { provider = "imdb"; number = raw; return }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, ["kitsu", "mal", "anilist", "anidb"].contains(String(parts[0])), !parts[1].isEmpty,
              parts[1].utf8.allSatisfy({ (48...57).contains($0) }), let id = Int(parts[1]), id > 0 else { return nil }
        provider = String(parts[0]); number = String(id)
    }
    var mappingKey: String { provider + "_id" }
    var relationsSource: String? { provider == "imdb" ? nil : provider == "mal" ? "myanimelist" : provider }
}

protocol AnimeFranchiseTransport: Sendable {
    func get(_ request: AnimeFranchiseRequest) async throws -> JSONValue
}

struct AnimeFranchiseHTTPTransport: AnimeFranchiseTransport {
    func get(_ request: AnimeFranchiseRequest) async throws -> JSONValue {
        if case .anilist(let id) = request {
            guard id > 0, id <= Int(Int32.max) else { throw HarborError(code: "anime-id") }
            return try await HTTPClient().anilist(query: Self.query, variables: .object(["id": .integer(Int64(id))]))
        }
        let kitsu: Bool
        switch request { case .kitsu, .related: kitsu = true; default: kitsu = false }
        return try await HTTPClient().json(request.url, accept: kitsu ? "application/vnd.api+json" : "application/json")
    }
    private static let query = """
    query ($id: Int) { Media(id: $id, type: ANIME) { id relations { edges { relationType(version: 2) node {
      id format episodes status averageScore seasonYear title { english romaji userPreferred }
      coverImage { large } bannerImage description(asHtml: false) startDate { year month day }
    } } } } }
    """
}
