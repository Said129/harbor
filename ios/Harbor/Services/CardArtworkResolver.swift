import Foundation
import CryptoKit

struct ResolvedCardArtwork: Equatable, Sendable {
    var logo: String?
    var backdrop: String?
}

enum CardArtworkRequest: Hashable, Sendable {
    case curated
    case cinemeta(kind: String, id: String)
    case anime(kind: String, id: String)
    case mapping(String)
    case tvdb(Int)
    case tmdbFind(String)
    case tmdbIdentity(kind: String, id: Int)
    case tmdbImages(kind: String, id: Int, languages: String)
    case tmdbSearch(kind: String, name: String, year: String?)

    func url(configuration: MetadataConfiguration) throws -> String {
        let base = HarborIdentityServer.community.base
        var path: String, parameters: [String: String] = [:]
        switch self {
        case .curated: return base + "/curated-logos.json"
        case .cinemeta(let kind, let id):
            guard ["movie", "series"].contains(kind), id.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { throw HarborError(code: "card-artwork-request") }
            return "https://v3-cinemeta.strem.io/meta/\(kind)/\(id).json"
        case .anime(let kind, let id):
            guard ["movie", "series"].contains(kind), AnimeService.isAnime(id) else { throw HarborError(code: "card-artwork-request") }
            return "https://anime-kitsu.strem.fun/meta/\(kind)/\(id).json"
        case .mapping(let id): return try AnimeFranchiseRequest.mapping(id).url
        case .tvdb(let id):
            guard id > 0 else { throw HarborError(code: "card-artwork-request") }
            return base + "/api/tvdb/artwork?series=\(id)"
        case .tmdbFind(let imdb):
            guard imdb.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { throw HarborError(code: "card-artwork-request") }
            path = "find/" + imdb; parameters["external_source"] = "imdb_id"
        case .tmdbIdentity(let kind, let id):
            guard ["movie", "tv"].contains(kind), id > 0 else { throw HarborError(code: "card-artwork-request") }
            path = "\(kind)/\(id)/external_ids"
        case .tmdbImages(let kind, let id, let languages):
            guard ["movie", "tv"].contains(kind), id > 0 else { throw HarborError(code: "card-artwork-request") }
            path = "\(kind)/\(id)/images"; parameters["include_image_language"] = languages
        case .tmdbSearch(let kind, let name, let year):
            guard ["movie", "tv"].contains(kind), !name.isEmpty else { throw HarborError(code: "card-artwork-request") }
            path = "search/" + kind; parameters["query"] = name; parameters["include_adult"] = "false"
            if let year { parameters[kind == "tv" ? "first_air_date_year" : "year"] = year }
        }
        guard !configuration.tmdbKey.isEmpty, var url = URLComponents(string: "https://api.themoviedb.org/3/" + path) else { throw HarborError(code: "metadata-not-configured") }
        parameters["api_key"] = configuration.tmdbKey; parameters["language"] = configuration.language
        url.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let value = url.string else { throw HarborError(code: "card-artwork-request") }; return value
    }
    var credentialed: Bool {
        switch self { case .tmdbFind, .tmdbIdentity, .tmdbImages, .tmdbSearch: true; default: false }
    }
}

protocol CardArtworkTransport: Sendable {
    func get(_ request: CardArtworkRequest, configuration: MetadataConfiguration) async throws -> JSONValue
}

struct CardArtworkHTTPTransport: CardArtworkTransport {
    func get(_ request: CardArtworkRequest, configuration: MetadataConfiguration) async throws -> JSONValue {
        if case .mapping(let id) = request { return try await AnimeFranchiseService.shared.response(.mapping(id)) }
        return try await HTTPClient().json(request.url(configuration: configuration), credentialed: request.credentialed)
    }
}

/// Lazy card-only public artwork. Coalesced lookups never delay the catalog itself.
actor CardArtworkResolver {
    static let shared = CardArtworkResolver()
    private struct Cached { let artwork: ResolvedCardArtwork; let at: Date }
    private let transport: any CardArtworkTransport
    private let anime: AnimeArtwork
    private let gate = AnimeMetadataGate()
    private var curated: [String: String]?
    private var curatedPending: Task<[String: String], Never>?
    private var cached: [String: Cached] = [:]
    private var pending: [String: Task<ResolvedCardArtwork, Never>] = [:]
    init(transport: any CardArtworkTransport = CardArtworkHTTPTransport(), anime: AnimeArtwork = .shared) { self.transport = transport; self.anime = anime }

    func resolve(_ media: Media, configuration: MetadataConfiguration, pinnedLogo: String? = nil) async -> ResolvedCardArtwork {
        let original = ResolvedCardArtwork(logo: CardArtworkPolicy.image(pinnedLogo) ?? CardArtworkPolicy.image(media.logo), backdrop: media.background != media.poster ? CardArtworkPolicy.image(media.background) : nil)
        guard !Task.isCancelled, ["movie", "series", "anime"].contains(media.type), AnimePublicIdentity(media.id) != nil || Self.tmdb(media.id) != nil else { return original }
        let pin = CardArtworkPolicy.image(pinnedLogo)
        let key = Self.cacheKey(media, configuration, pinnedLogo: pin)
        if let saved = cached[key], Date().timeIntervalSince(saved.at) < (saved.artwork.logo == nil ? 300 : 3_600) { return saved.artwork }
        if let task = pending[key] { return await task.value }
        let task = Task { await self.perform(media, configuration: configuration, pinnedLogo: pin) }
        pending[key] = task
        let value = await task.value
        pending[key] = nil
        if cached.count >= 1_200, let oldest = cached.min(by: { $0.value.at < $1.value.at })?.key { cached[oldest] = nil }
        cached[key] = Cached(artwork: value, at: Date()); return value
    }
    nonisolated static func cacheKey(_ media: Media, _ configuration: MetadataConfiguration, pinnedLogo: String? = nil) -> String {
        // Only a digest of configuration enters the cache key; no key is logged or persisted.
        let parts = [media.identity, media.logo ?? "", media.poster ?? "", media.background ?? "", media.originalLanguage ?? "", media.animeFormat ?? "", media.name, media.releaseInfo ?? "", configuration.tmdbKey, configuration.language, configuration.imageLanguages.joined(separator: ","), pinnedLogo ?? ""]
        return SHA256.hash(data: Data(parts.joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func request(_ request: CardArtworkRequest, _ configuration: MetadataConfiguration) async -> JSONValue? {
        let transport = transport
        return try? await gate.run { try await transport.get(request, configuration: configuration) }
    }
    private func curatedLogos(_ configuration: MetadataConfiguration) async -> [String: String] {
        if let curated { return curated }
        if let curatedPending { return await curatedPending.value }
        let task = Task { () -> [String: String] in
            let result = await self.request(.curated, configuration)
            return (result?["logos"].objectValue ?? [:]).compactMapValues { CardArtworkPolicy.image($0.string) }
        }
        curatedPending = task
        let value = await task.value; curated = value; curatedPending = nil; return value
    }
    private func perform(_ media: Media, configuration: MetadataConfiguration, pinnedLogo: String?) async -> ResolvedCardArtwork {
        let policy = CardArtworkPolicy(languages: configuration.imageLanguages, metadataLanguage: configuration.language, originalLanguage: media.originalLanguage)
        let isAnime = AnimeService.isAnime(media.id)
        let enriched = isAnime ? await anime.enrich([media]).first ?? media : media
        var result = ResolvedCardArtwork(logo: nil, backdrop: media.background != media.poster ? CardArtworkPolicy.image(media.background) : nil)
        if result.backdrop == nil, enriched.background != media.poster { result.backdrop = CardArtworkPolicy.image(enriched.background) }
        let curated = await curatedLogos(configuration)[media.id]
        let own = CardArtworkPolicy.image(media.logo) ?? CardArtworkPolicy.image(enriched.logo)
        let localize = !configuration.tmdbKey.isEmpty && policy.localizes && !isAnime
        result.logo = pinnedLogo ?? (localize ? nil : curated ?? own)
        let kind = media.type == "movie" ? "movie" : "tv"
        if media.id.hasPrefix("tt") {
            if result.logo == nil, localize, let found = await request(.tmdbFind(media.id), configuration),
               let id = found[kind == "movie" ? "movie_results" : "tv_results"].array.first?["id"].integer {
                let images = await request(.tmdbImages(kind: kind, id: id, languages: policy.parameter), configuration)
                result.logo = policy.logo(images?["logos"].array ?? [])
            }
            if result.logo == nil {
                let full = await request(.cinemeta(kind: media.type == "movie" ? "movie" : "series", id: media.id), configuration)
                result.logo = CardArtworkPolicy.image(full?["meta"]["logo"].string)
            }
        } else if let reference = Self.tmdb(media.id), result.logo == nil, !configuration.tmdbKey.isEmpty {
            let identity = await request(.tmdbIdentity(kind: reference.kind, id: reference.id), configuration)
            let images = await request(.tmdbImages(kind: reference.kind, id: reference.id, languages: policy.parameter), configuration)
            result.logo = policy.logo(images?["logos"].array ?? [])
            if result.logo == nil, let imdb = identity?["imdb_id"].string {
                result.logo = await curatedLogos(configuration)[imdb]
                if result.logo == nil {
                    let full = await request(.cinemeta(kind: reference.kind == "movie" ? "movie" : "series", id: imdb), configuration)
                    result.logo = CardArtworkPolicy.image(full?["meta"]["logo"].string)
                }
            }
        } else if isAnime, result.logo == nil || result.backdrop == nil {
            var mapping: JSONValue?
            let identity = AnimePublicIdentity(media.id)!
            if identity.provider != "kitsu" { mapping = await request(.mapping(media.id), configuration) }
            let mapped = mapping?["mappings"]
            let matches = mapped?[identity.mappingKey].textValue == identity.number
            let kitsu = identity.provider == "kitsu" ? Int(identity.number) : matches ? mapped?["kitsu_id"].integer : nil
            let canonical = kitsu.map { "kitsu:\($0)" } ?? media.id
            let full = await request(.anime(kind: media.type == "movie" ? "movie" : "series", id: canonical), configuration)
            let meta = full?["meta"]
            if result.logo == nil { result.logo = CardArtworkPolicy.image(meta?["logo"].string) }
            if result.backdrop == nil, meta?["background"].string != meta?["poster"].string { result.backdrop = CardArtworkPolicy.image(meta?["background"].string) }
            let derived = ["SPECIAL", "OVA", "ONA", "MUSIC"].contains(media.animeFormat?.uppercased() ?? "")
            if !derived, result.logo == nil || result.backdrop == nil {
                if mapping == nil { mapping = await request(.mapping(canonical), configuration) }
                if let kitsu, mapping?["mappings"]["kitsu_id"].integer == kitsu, let series = mapping?["mappings"]["thetvdb_id"].integer {
                    let artwork = await request(.tvdb(series), configuration)
                    if result.logo == nil { result.logo = artwork?["clearLogos"].array.compactMap { CardArtworkPolicy.image($0.string) }.first }
                    if result.backdrop == nil { result.backdrop = artwork?["backgrounds"].array.compactMap { CardArtworkPolicy.image($0.string) }.first }
                }
            }
            if !configuration.tmdbKey.isEmpty, result.logo == nil || result.backdrop == nil {
                let name = meta?["name"].string ?? media.name, year = meta?["releaseInfo"].string ?? media.releaseInfo
                var hits = await request(.tmdbSearch(kind: kind, name: name, year: year), configuration)
                if hits?["results"].array.isEmpty != false, year != nil { hits = await request(.tmdbSearch(kind: kind, name: name, year: nil), configuration) }
                if let hit = AnimeCardArtworkMatch.best(hits?["results"].array ?? [], name: name, year: year, kind: kind, exact: derived), let id = hit["id"].integer {
                    let imagePolicy = CardArtworkPolicy(languages: configuration.imageLanguages, metadataLanguage: configuration.language, originalLanguage: hit["original_language"].string)
                    let images = await request(.tmdbImages(kind: kind, id: id, languages: imagePolicy.parameter), configuration)
                    if result.logo == nil { result.logo = imagePolicy.logo(images?["logos"].array ?? []) }
                    if result.backdrop == nil { result.backdrop = CardArtworkPolicy.tmdbImage(images?["backdrops"].array.first?["file_path"].string, size: "w1280") }
                }
            }
        }
        result.logo = result.logo ?? curated ?? own
        return result
    }
    private static func tmdb(_ id: String) -> (kind: String, id: Int)? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "tmdb", ["movie", "tv"].contains(String(parts[1])), let number = Int(parts[2]), number > 0 else { return nil }
        return (String(parts[1]), number)
    }
}
