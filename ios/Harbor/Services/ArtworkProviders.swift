import Foundation

/// Desktop's RPDB rated posters (`src/lib/providers/rpdb.ts`). Only the default host is ported:
/// Desktop's custom poster server (`posterBaseUrl`) is skipped, so the key never goes to a user-typed host.
enum RatingPosterDB {
    static let host = "https://api.ratingposterdb.com"

    /// Desktop's `ParsedId`. `mediaType` is "movie" or "series".
    struct Identity: Equatable, Sendable {
        var imdb: String?
        var tmdbID: String?
        var tvdbID: String?
        var mediaType: String
    }

    /// Desktop's `parseMetaId`: `tt…`, `tmdb:movie:N`, `tmdb:tv:N` and `tvdb:N`.
    static func identity(_ metaID: String) -> Identity? {
        if metaID.hasPrefix("tt") {
            // Stricter than Desktop: an IMDb id is a path segment, so it must be digits only.
            let digits = String(metaID.dropFirst(2))
            guard digits.count >= 7, isDigits(digits) else { return nil }
            return Identity(imdb: metaID, tmdbID: nil, tvdbID: nil, mediaType: "movie")
        }
        let parts = metaID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 3, parts[0] == "tmdb", parts[1] == "movie" || parts[1] == "tv", isDigits(parts[2]) {
            return Identity(imdb: nil, tmdbID: parts[2], tvdbID: nil, mediaType: parts[1] == "tv" ? "series" : "movie")
        }
        if parts.count == 2, parts[0] == "tvdb", isDigits(parts[1]) {
            return Identity(imdb: nil, tmdbID: nil, tvdbID: parts[1], mediaType: "series")
        }
        return nil
    }

    /// Desktop's `mergeAlt`: the alternate id fills gaps, and its media type applies only when it carries the TMDB id.
    static func merged(_ id: Identity, alternate: String?) -> Identity {
        guard let alternate, let other = identity(alternate) else { return id }
        let typed = id.tmdbID != nil ? id : (other.tmdbID != nil ? other : id)
        return Identity(
            imdb: id.imdb ?? other.imdb,
            tmdbID: id.tmdbID ?? other.tmdbID,
            tvdbID: id.tvdbID ?? other.tvdbID,
            mediaType: typed.mediaType
        )
    }

    /// The key becomes a path segment, so characters that would change the path are refused rather than encoded.
    static func isUsableKey(_ key: String) -> Bool {
        !key.isEmpty && !key.contains { $0.isWhitespace || "/?#%".contains($0) }
    }

    /// The RPDB poster for a title, or nil when there is no key or the id cannot be used (callers keep their own poster).
    static func posterURL(key: String, metaID: String, altID: String? = nil) -> String? {
        guard isUsableKey(key), let parsed = identity(metaID) else { return nil }
        let id = merged(parsed, alternate: altID)
        let base = host + "/" + key
        if let imdb = id.imdb { return base + "/imdb/poster-default/" + imdb + ".jpg?fallback=true" }
        if let tmdb = id.tmdbID { return base + "/tmdb/poster-default/" + id.mediaType + "-" + tmdb + ".jpg?fallback=true" }
        if let tvdb = id.tvdbID { return base + "/tvdb/poster-default/series-" + tvdb + ".jpg?fallback=true" }
        return nil
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Desktop's Fanart.tv artwork (`src/lib/providers/fanart.ts`): the request paths, and the language and likes ranking.
enum FanartTV {
    static let base = "https://webservice.fanart.tv/v3"

    struct Art: Equatable, Sendable {
        var logo: String?
        var backdrop: String?
        var backdrops: [String]
        var poster: String?
        var banner: String?
        var thumb: String?
    }

    /// One ranked item. `url` is kept even when empty so the top item can decide the result, as on Desktop.
    struct Candidate: Equatable, Sendable {
        let url: String?
        let language: Double
        let likes: Double
        let order: Int
    }

    static func movieURL(key: String, tmdbID: Int) -> String? {
        request(path: "/movies/\(tmdbID)", key: key, id: tmdbID)
    }

    static func tvURL(key: String, tvdbID: Int) -> String? {
        request(path: "/tv/\(tvdbID)", key: key, id: tvdbID)
    }

    private static func request(path: String, key: String, id: Int) -> String? {
        guard id > 0, RatingPosterDB.isUsableKey(key), var parts = URLComponents(string: base + path) else { return nil }
        parts.queryItems = [URLQueryItem(name: "api_key", value: key)]
        return parts.url?.absoluteString
    }

    /// Desktop's `rankItems`: English first, then "00" (no language), then everything else; likes break ties, then the order from Fanart.
    static func ranked(_ items: [JSONValue]) -> [Candidate] {
        let candidates = items.enumerated().map { index, item -> Candidate in
            let lang = item["lang"].string
            let score: Double = lang == "en" ? 1 : (lang == "00" ? 0.5 : 0)
            let likes = item["likes"].textValue.flatMap(Double.init) ?? 0
            return Candidate(url: item["url"].string, language: score, likes: likes.isNaN ? 0 : likes, order: index)
        }
        return candidates.sorted { a, b in
            if a.language != b.language { return a.language > b.language }
            if a.likes != b.likes { return a.likes > b.likes }
            return a.order < b.order
        }
    }

    /// Desktop's `pickEnglish`: the top-ranked url, or nil when that item has none.
    static func best(_ items: [JSONValue]) -> String? {
        ranked(items).first?.url
    }

    /// Desktop's `pickAll`: every ranked url, without empty ones.
    static func all(_ items: [JSONValue]) -> [String] {
        ranked(items).compactMap { $0.url }.filter { !$0.isEmpty }
    }

    static func movieArt(_ json: JSONValue) -> Art {
        let backdrops = all(json["moviebackground"].array)
        return Art(
            logo: best(json["hdmovielogo"].array) ?? best(json["movielogo"].array),
            backdrop: backdrops.first,
            backdrops: backdrops,
            poster: best(json["movieposter"].array),
            banner: best(json["moviebanner"].array),
            thumb: best(json["moviethumb"].array)
        )
    }

    static func tvArt(_ json: JSONValue) -> Art {
        let backdrops = all(json["showbackground"].array)
        return Art(
            logo: best(json["hdtvlogo"].array) ?? best(json["clearlogo"].array),
            backdrop: backdrops.first,
            backdrops: backdrops,
            poster: best(json["tvposter"].array),
            banner: best(json["tvbanner"].array),
            thumb: best(json["tvthumb"].array)
        )
    }
}

/// The network edge for the artwork providers, so tests can answer with canned JSON.
protocol ArtworkJSONTransport: Sendable {
    func json(_ url: String) async throws -> JSONValue
}

struct ArtworkHTTPTransport: ArtworkJSONTransport {
    /// The key travels in the query, so the request uses the credentialed (uncached) session, as TMDB does.
    func json(_ url: String) async throws -> JSONValue {
        try await HTTPClient().json(url, credentialed: true)
    }
}

/// Desktop's Fanart fetch: any failure, empty key or missing item gives nil.
struct FanartClient: Sendable {
    let key: String
    let transport: any ArtworkJSONTransport

    init(key: String, transport: any ArtworkJSONTransport = ArtworkHTTPTransport()) {
        self.key = key
        self.transport = transport
    }

    func movie(tmdbID: Int) async -> FanartTV.Art? {
        guard let url = FanartTV.movieURL(key: key, tmdbID: tmdbID) else { return nil }
        guard let json = try? await transport.json(url), json != .null else { return nil }
        return FanartTV.movieArt(json)
    }

    func tv(tvdbID: Int) async -> FanartTV.Art? {
        guard let url = FanartTV.tvURL(key: key, tvdbID: tvdbID) else { return nil }
        guard let json = try? await transport.json(url), json != .null else { return nil }
        return FanartTV.tvArt(json)
    }
}
