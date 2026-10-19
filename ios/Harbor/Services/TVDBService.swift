import Foundation

protocol TVDBTransport: Sendable {
    func get(_ request: TVDBRequest) async throws -> JSONValue
}

struct TVDBHTTPTransport: TVDBTransport {
    func get(_ request: TVDBRequest) async throws -> JSONValue {
        try await HTTPClient().tvdb(request)
    }
}

/// Preserve Desktop's public TVDB proxy protocol on the community continuation.
/// No account, personal key, token or cookie is sent to this metadata service.
actor TVDBService {
    static let shared = TVDBService()
    private struct Cached { let value: JSONValue; let expires: Date }
    private let transport: any TVDBTransport
    private var cache: [TVDBRequest: Cached] = [:]
    private var pending: [TVDBRequest: Task<JSONValue, Error>] = [:]
    init(transport: any TVDBTransport = TVDBHTTPTransport()) { self.transport = transport }

    func data(_ request: TVDBRequest) async throws -> JSONValue {
        _ = try request.path
        if let saved = cache[request], saved.expires > Date() { return saved.value }
        if let task = pending[request] { return try await task.value }
        let transport = transport
        let task = Task {
            let response = try await transport.get(request)
            let value = response["data"]
            switch request {
            case .remote:
                guard case .array = value else { throw HarborError(code: "tvdb-response") }
            case .series(let id):
                guard value["id"].integer == id else { throw HarborError(code: "tvdb-response") }
            case .episodes:
                guard case .array = value["episodes"] else { throw HarborError(code: "tvdb-response") }
            }
            return value
        }
        pending[request] = task
        defer { pending[request] = nil }
        let value = try await task.value
        if cache.count >= 200, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key { cache[oldest] = nil }
        cache[request] = Cached(value: value, expires: Date().addingTimeInterval(600))
        return value
    }

    func episodes(series: Int, language: String? = nil) async throws -> [TVDBEpisodeMetadata] {
        var result: [TVDBEpisodeMetadata] = [], seen = Set<Int>()
        for page in 0..<20 {
            try Task.checkCancellation()
            let value = try await data(.episodes(series: series, order: "default", language: language, page: page))
            guard case .array(let raw) = value["episodes"] else { throw HarborError(code: "tvdb-response") }
            let rows = raw.compactMap(TVDBEpisodeMetadata.init).filter { seen.insert($0.id).inserted }
            result.append(contentsOf: rows)
            if raw.count < 500 { return result }
            // A repeating page must not loop or silently certify a partial list.
            guard !rows.isEmpty else { throw HarborError(code: "tvdb-response") }
        }
        throw HarborError(code: "tvdb-response")
    }

    func supplement(_ variants: AnimeEpisodeVariants, for media: Media) async -> AnimeEpisodeVariants {
        guard media.episodic else { return variants }
        do {
            var series = variants.tvdbSeriesID
            if series == nil {
                let imdb = media.imdbID ?? media.id
                guard imdb.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil else { return variants }
                let hits = try await data(.remote(imdb))
                let ids = Set(hits.array.compactMap { $0["series"]["id"].integer }.filter { $0 > 0 })
                guard ids.count == 1 else { return variants }
                series = ids.first
            }
            guard let series else { return variants }
            let rows = try await episodes(series: series)
            try Task.checkCancellation()
            return AnimeEpisodeVariants(
                seasons: TVDBEpisodeMetadata.applying(rows, to: variants.seasons, animeIdentity: AnimeService.isAnime(media.id)),
                continuous: TVDBEpisodeMetadata.applying(rows, to: variants.continuous, animeIdentity: AnimeService.isAnime(media.id)), tvdbSeriesID: series, kitsuID: variants.kitsuID)
        } catch { return variants }
    }
}
