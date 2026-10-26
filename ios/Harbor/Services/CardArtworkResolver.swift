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
    case tvdbIMDb(String)
    case simklAnime(Int)
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
        case .tvdbIMDb(let id):
            guard id.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { throw HarborError(code: "card-artwork-request") }
            return base + "/api/tvdb/artwork?imdb=" + id
        case .simklAnime(let id): return try HTTPClient.simklArtworkRequest(id).url!.absoluteString
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
        if case .simklAnime(let id) = request { return try await SimklArtworkCatalog.shared.response(id) }
        return try await HTTPClient().json(request.url(configuration: configuration), credentialed: request.credentialed)
    }
}

/// Lazy card-only public artwork. Coalesced lookups never delay the catalog itself.
actor CardArtworkResolver {
    static let shared = CardArtworkResolver()
    private struct Cached { let artwork: ResolvedCardArtwork; let at: Date }
    private struct CachedPoster { let url: String?; let at: Date }
    private struct CachedRequest { let value: JSONValue?; let at: Date; let cost: Int }
    private let transport: any CardArtworkTransport
    private let anime: AnimeArtwork
    private let gate = AnimeMetadataGate()
    private var curated: [String: String]?
    private var curatedPending: Task<[String: String], Never>?
    private var cached: [String: Cached] = [:]
    private var pending: [String: Task<ResolvedCardArtwork, Never>] = [:]
    private var posters: [String: CachedPoster] = [:]
    private var posterPending: [String: Task<String?, Never>] = [:]
    private var requests: [String: CachedRequest] = [:]
    private var requestPending: [String: Task<JSONValue?, Never>] = [:]
    private var requestCost = 0
    init(transport: any CardArtworkTransport = CardArtworkHTTPTransport(), anime: AnimeArtwork = .shared) { self.transport = transport; self.anime = anime }

    nonisolated static func canLocalizePoster(_ media: Media, configuration: MetadataConfiguration) -> Bool {
        !configuration.tmdbKey.isEmpty && (tmdb(media.artworkID) != nil || media.artworkID.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil)
            && CardArtworkPolicy(languages: configuration.imageLanguages, metadataLanguage: configuration.language, originalLanguage: nil).localizes
    }
    func poster(_ media: Media, configuration: MetadataConfiguration) async -> String? {
        guard !Task.isCancelled, Self.canLocalizePoster(media, configuration: configuration) else { return nil }
        let key = Self.cacheKey(media, configuration)
        if let saved = posters[key], Date().timeIntervalSince(saved.at) < (saved.url == nil ? 300 : 3_600) { return saved.url }
        if let task = posterPending[key] { return await task.value }
        let task = Task { await self.localizedPoster(media, configuration: configuration) }
        posterPending[key] = task
        let value = await task.value; posterPending[key] = nil
        if posters.count >= 1_200, let oldest = posters.min(by: { $0.value.at < $1.value.at })?.key { posters[oldest] = nil }
        posters[key] = CachedPoster(url: value, at: Date()); return value
    }
    private func localizedPoster(_ media: Media, configuration: MetadataConfiguration) async -> String? {
        var reference = Self.tmdb(media.artworkID)
        if reference == nil {
            let kind = media.type == "movie" ? "movie" : "tv"
            let found = await request(.tmdbFind(media.artworkID), configuration)
            if let id = found?[kind == "movie" ? "movie_results" : "tv_results"].array.first?["id"].integer { reference = (kind, id) }
        }
        guard let reference else { return nil }
        // Desktop's card hook omits originalLang; Original therefore means neutral
        // artwork here, while metadata galleries can rank a known original language.
        let policy = CardArtworkPolicy(languages: configuration.imageLanguages, metadataLanguage: configuration.language, originalLanguage: nil)
        let images = await request(.tmdbImages(kind: reference.kind, id: reference.id, languages: policy.parameter), configuration)
        return policy.poster(images?["posters"].array ?? [])
    }

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
        let parts = [media.identity, media.artworkID, media.logo ?? "", media.poster ?? "", media.background ?? "", media.originalLanguage ?? "", media.animeFormat ?? "", media.name, media.releaseInfo ?? "", configuration.tmdbKey, configuration.language, configuration.imageLanguages.joined(separator: ","), pinnedLogo ?? ""]
        return SHA256.hash(data: Data(parts.joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func request(_ request: CardArtworkRequest, _ configuration: MetadataConfiguration) async -> JSONValue? {
        let transport = transport
        // Poster and TV cards share these responses. Secrets never enter a raw
        // cache key, and decoded image lists have a separate bounded memory cost.
        guard request.credentialed else { return try? await gate.run { try await transport.get(request, configuration: configuration) } }
        let raw = "\(request)\u{0}\(configuration.tmdbKey)\u{0}\(configuration.language)"
        let key = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        if let saved = requests[key], Date().timeIntervalSince(saved.at) < (saved.value == nil ? 30 : 3_600) { return saved.value }
        if let task = requestPending[key] { return await task.value }
        let task = Task { try? await self.gate.run { try await transport.get(request, configuration: configuration) } }
        requestPending[key] = task
        let value = await task.value; requestPending[key] = nil
        if let previous = requests.removeValue(forKey: key) { requestCost -= previous.cost }
        let cost = value.flatMap { try? JSONEncoder().encode($0).count } ?? 0
        if cost <= 16 * 1_024 * 1_024 {
            while requests.count >= 400 || requestCost + cost > 16 * 1_024 * 1_024 {
                guard let oldest = requests.min(by: { $0.value.at < $1.value.at })?.key, let removed = requests.removeValue(forKey: oldest) else { break }
                requestCost -= removed.cost
            }
            requests[key] = CachedRequest(value: value, at: Date(), cost: cost); requestCost += cost
        }
        return value
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
    func wideCandidates(_ input: Media, configuration: MetadataConfiguration) async -> [String] {
        var media = input; media.id = input.artworkID
        let kind = media.type == "movie" ? "movie" : "tv"
        let simklParts = media.id.split(separator: ":")
        let simkl = simklParts.count == 2 && simklParts[0] == "simkl" ? Int(simklParts[1]).flatMap { $0 > 0 ? $0 : nil } : nil
        let isAnime = AnimeService.isAnime(media.id) || simkl != nil
        let derived = isAnime && ["SPECIAL", "OVA", "ONA", "MUSIC"].contains(media.animeFormat?.uppercased() ?? "")
        var reference = Self.tmdb(media.id), imdb = media.id.hasPrefix("tt") ? media.id : media.imdbID
        var kitsu: Int?, series: Int?, mappingSource: String?
        if let simkl {
            let detail = await request(.simklAnime(simkl), configuration)
            let ids = detail?["ids"]
            kitsu = ids?["kitsu"].textValue.flatMap(Int.init); series = ids?["tvdb"].integer
            imdb = ids?["imdb"].string ?? imdb
            if let number = ids?["tmdb"].integer, number > 0 { reference = (kind, number) }
            if kitsu == nil {
                if let mal = ids?["mal"].integer, mal > 0 { mappingSource = "mal:\(mal)" }
                else if let anidb = ids?["anidb"].integer, anidb > 0 { mappingSource = "anidb:\(anidb)" }
            }
        } else if isAnime, let identity = AnimePublicIdentity(media.id) {
            if identity.provider == "kitsu" { kitsu = Int(identity.number) }
            mappingSource = media.id
        }
        if let source = mappingSource, let identity = AnimePublicIdentity(source), let mapping = await request(.mapping(source), configuration),
           mapping["mappings"][identity.mappingKey].textValue == identity.number {
            let ids = mapping["mappings"]
            kitsu = kitsu ?? ids["kitsu_id"].integer; series = series ?? ids["thetvdb_id"].integer; imdb = imdb ?? ids["imdb_id"].string
        }
        if !derived, series == nil, let kitsu, kitsu > 0, mappingSource != "kitsu:\(kitsu)",
           let mapping = await request(.mapping("kitsu:\(kitsu)"), configuration), mapping["mappings"]["kitsu_id"].integer == kitsu {
            series = mapping["mappings"]["thetvdb_id"].integer; imdb = imdb ?? mapping["mappings"]["imdb_id"].string
        }
        if reference == nil, !configuration.tmdbKey.isEmpty {
            if isAnime {
                var hits = await request(.tmdbSearch(kind: kind, name: media.name, year: media.releaseInfo), configuration)
                if hits?["results"].array.isEmpty != false, media.releaseInfo != nil { hits = await request(.tmdbSearch(kind: kind, name: media.name, year: nil), configuration) }
                if let hit = AnimeCardArtworkMatch.best(hits?["results"].array ?? [], name: media.name, year: media.releaseInfo, kind: kind, exact: derived), let id = hit["id"].integer { reference = (kind, id) }
            } else if let imdb, let result = await request(.tmdbFind(imdb), configuration), let id = result[kind == "movie" ? "movie_results" : "tv_results"].array.first?["id"].integer { reference = (kind, id) }
        }
        async let tmdbArtwork = tmdbWideImages(reference, configuration)
        async let tvdbArtwork = tvdbWideImages(series: derived ? nil : series, imdb: derived ? nil : imdb, configuration)
        let values = await tmdbArtwork + tvdbArtwork + [media.background].compactMap { $0 }
        let alternatives = PosterBehaviorPolicy.alternatives(values, poster: media.poster)
        if !alternatives.isEmpty || !isAnime { return alternatives }
        var empty = media; empty.background = nil
        let staticArt = await anime.enrich([empty]).first?.background
        if let staticArt { return PosterBehaviorPolicy.alternatives([staticArt], poster: media.poster) }
        let canonical = kitsu.flatMap { $0 > 0 ? "kitsu:\($0)" : nil } ?? media.id
        guard AnimeService.isAnime(canonical) else { return [] }
        let full = await request(.anime(kind: media.type == "movie" ? "movie" : "series", id: canonical), configuration)
        return PosterBehaviorPolicy.alternatives([full?["meta"]["background"].string].compactMap { $0 }, poster: media.poster)
    }
    private func tmdbWideImages(_ reference: (kind: String, id: Int)?, _ configuration: MetadataConfiguration) async -> [String] {
        guard let reference, !configuration.tmdbKey.isEmpty else { return [] }
        let policy = CardArtworkPolicy(languages: configuration.imageLanguages, metadataLanguage: configuration.language, originalLanguage: nil)
        let images = await request(.tmdbImages(kind: reference.kind, id: reference.id, languages: policy.parameter), configuration)
        return (images?["backdrops"].array ?? []).enumerated().sorted {
            let a = $0.element["vote_average"].textValue.flatMap(Double.init) ?? 0, b = $1.element["vote_average"].textValue.flatMap(Double.init) ?? 0
            return a == b ? $0.offset < $1.offset : a > b
        }.prefix(12).compactMap { CardArtworkPolicy.tmdbImage($0.element["file_path"].string, size: "w780") }
    }
    private func tvdbWideImages(series: Int?, imdb: String?, _ configuration: MetadataConfiguration) async -> [String] {
        let result: JSONValue?
        if let series, series > 0 { result = await request(.tvdb(series), configuration) }
        else if let imdb, imdb.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil { result = await request(.tvdbIMDb(imdb), configuration) }
        else { return [] }
        return result?["backgrounds"].array.compactMap { CardArtworkPolicy.image($0.string) } ?? []
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
    nonisolated private static func tmdb(_ id: String) -> (kind: String, id: Int)? {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "tmdb", ["movie", "tv"].contains(String(parts[1])), let number = Int(parts[2]), number > 0 else { return nil }
        return (String(parts[1]), number)
    }
}
