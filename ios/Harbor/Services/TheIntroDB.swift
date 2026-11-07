import Foundation

/// The network call behind TheIntroDB: the JSON at a URL, sent with the profile's key as `X-API-Key` when there is one.
/// A failed call throws a `HarborError` whose code is `http-<status>` for an HTTP failure, or `network`.
protocol TheIntroDBTransport: Sendable {
    func json(_ url: URL, apiKey: String) async throws -> JSONValue
}

struct TheIntroDBHTTPTransport: TheIntroDBTransport {
    func json(_ url: URL, apiKey: String) async throws -> JSONValue {
        try await HTTPClient().json(url.absoluteString, timeout: 15, headers: apiKey.isEmpty ? [:] : ["X-API-Key": apiKey])
    }
}

/// Desktop's TheIntroDB request rules (`lib/skip-intro/theintrodb.ts`) as pure functions.
enum TheIntroDBRules {
    static let base = "https://api.theintrodb.org/v2/media"

    /// The query of one lookup: a TMDB id for `tmdb:movie:` and `tmdb:tv:`, an IMDb id for `tt`, then season and episode.
    /// Nil when the id is neither, so Desktop's rule of asking nothing for other ids holds.
    static func query(metaID: String, season: Int?, episode: Int?) -> String? {
        var items: [URLQueryItem] = []
        if metaID.range(of: "^tt[0-9]+$", options: .regularExpression) != nil {
            items.append(URLQueryItem(name: "imdb_id", value: metaID))
        } else if metaID.hasPrefix("tmdb:tv:") || metaID.hasPrefix("tmdb:movie:"), let number = Int(metaID.split(separator: ":").last ?? ""), number > 0 {
            items.append(URLQueryItem(name: "tmdb_id", value: String(number)))
        } else {
            return nil
        }
        if let season, let episode, season >= 0, episode > 0 {
            items.append(URLQueryItem(name: "season", value: String(season)))
            items.append(URLQueryItem(name: "episode", value: String(episode)))
        }
        var parts = URLComponents()
        parts.queryItems = items
        return parts.percentEncodedQuery
    }

    static func url(query: String) -> URL? {
        URL(string: base + "?" + query)
    }
}

/// Desktop's TheIntroDB cache and failure rules, as an actor. A key change forgets every answer and the cooldown, as
/// Desktop's `setTheIntroDbApiKey` does. An answer is kept for the session. A 404 is kept as a miss. Any other HTTP
/// failure stops every request for ten minutes. A network error is not kept, so the next call asks again.
actor TheIntroDBClient {
    static let shared = TheIntroDBClient(transport: TheIntroDBHTTPTransport())
    static let failureCooldown: TimeInterval = 10 * 60

    private let transport: any TheIntroDBTransport
    private let clock: @Sendable () -> Date
    private var apiKey = ""
    private var epoch = 0
    private var answers: [String: JSONValue] = [:]
    private var misses: Set<String> = []
    private var coolingUntil = Date.distantPast

    init(transport: any TheIntroDBTransport, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.clock = clock
    }

    /// The skip segments TheIntroDB gives for one title and episode. Empty when there is no answer.
    func segments(metaID: String, season: Int?, episode: Int?, duration: Double, apiKey key: String) async -> [SkipSegment] {
        guard let query = TheIntroDBRules.query(metaID: metaID, season: season, episode: episode),
              let json = await answer(query: query, apiKey: key) else { return [] }
        return SkipIntroService.parseIntroDB(json, duration: duration)
    }

    /// Desktop's `fetchRaw`: the answer for one query, from the cache when it is there.
    private func answer(query: String, apiKey key: String) async -> JSONValue? {
        if key != apiKey {
            apiKey = key; epoch += 1; answers = [:]; misses = []; coolingUntil = .distantPast
        }
        if let hit = answers[query] { return hit }
        if misses.contains(query) || clock() < coolingUntil { return nil }
        guard let url = TheIntroDBRules.url(query: query) else { return nil }
        let generation = epoch
        do {
            let json = try await transport.json(url, apiKey: key)
            if generation == epoch { answers[query] = json }
            return json
        } catch let error as HarborError where error.code == "http-404" {
            if generation == epoch { misses.insert(query) }
        } catch let error as HarborError where error.code.hasPrefix("http-") {
            if generation == epoch { coolingUntil = clock().addingTimeInterval(Self.failureCooldown) }
        } catch {
            // A network failure is not kept: Desktop logs it and asks again on the next call.
        }
        return nil
    }
}
