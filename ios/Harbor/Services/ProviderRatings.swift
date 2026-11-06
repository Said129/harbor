import Foundation

// MARK: OMDb (Desktop's lib/providers/omdb.ts)

/// The scores OMDb returns for an IMDb id. Awards are not read yet.
struct OmdbScores: Codable, Equatable, Sendable {
    var imdbRating: String?
    var rated: String?
    var imdbVotes: Int?
    var rtCritics: Int?
    var metascore: Int?
    var certifiedFresh = false
    /// Milliseconds since 1970, as on Desktop.
    var fetchedAt: Double
}

enum OmdbOutcome: Equatable, Sendable {
    case scores(OmdbScores)
    /// OMDb answered, but has nothing for this title.
    case miss
    case keyInvalid
    case exhausted
}

enum OmdbParser {
    /// Desktop's `certifiedFresh`: 75 % or more on Rotten Tomatoes with at least this many IMDb votes.
    static let certifiedFreshMinimumVotes = 50_000

    /// The first number in the text ("87%", "82/100").
    static func percent(_ text: String?) -> Int? {
        guard let text, let found = text.range(of: "[0-9]+", options: .regularExpression) else { return nil }
        return Int(text[found])
    }

    static func votes(_ text: String?) -> Int? { text.flatMap { Int($0.replacingOccurrences(of: ",", with: "")) } }

    static func parse(_ json: JSONValue, now: Date = Date()) -> OmdbOutcome {
        if json["Response"].string == "False" {
            let message = json["Error"].string ?? ""
            if message.range(of: "invalid api key|no api key|not activated", options: [.regularExpression, .caseInsensitive]) != nil { return .keyInvalid }
            if message.range(of: "limit|exceeded|daily|reached", options: [.regularExpression, .caseInsensitive]) != nil { return .exhausted }
            return .miss
        }
        let ratings = json["Ratings"].array
        func value(_ source: String) -> String? { ratings.first { $0["Source"].string == source }?["Value"].string }
        let voteCount = votes(json["imdbVotes"].string)
        let critics = percent(value("Rotten Tomatoes"))
        var imdb: String?
        if let text = json["imdbRating"].string, !text.isEmpty, text != "N/A" { imdb = text }
        var rated: String?
        if let text = json["Rated"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
           text.range(of: "^(n/a|not rated|unrated|nr)$", options: [.regularExpression, .caseInsensitive]) == nil { rated = text }
        var fresh = false
        if let critics, let voteCount { fresh = critics >= 75 && voteCount >= certifiedFreshMinimumVotes }
        return .scores(OmdbScores(imdbRating: imdb, rated: rated, imdbVotes: voteCount, rtCritics: critics, metascore: percent(value("Metacritic")),
                                  certifiedFresh: fresh,
                                  fetchedAt: now.timeIntervalSince1970 * 1_000))
    }
}

/// OMDb's free key allows 1,000 requests a day; Desktop counts them and stops when the key is refused.
struct OmdbBudget: Codable, Equatable, Sendable {
    static let dailyLimit = 1_000
    /// Prefetching stops at this share of the day's allowance, leaving the rest for pages the person opens.
    static let prefetchShare = 0.9
    var used = 0
    var limit = OmdbBudget.dailyLimit
    var resetAt: Double = 0
    var exhausted = false
    var keyInvalid = false

    static func nextUTCMidnight(after now: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = calendar.startOfDay(for: now)
        return (calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)).timeIntervalSince1970 * 1_000
    }
    static func fresh(now: Date, keyInvalid: Bool = false) -> OmdbBudget { OmdbBudget(resetAt: nextUTCMidnight(after: now), keyInvalid: keyInvalid) }
    /// A new day starts a new allowance, but a refused key stays refused.
    func current(at now: Date) -> OmdbBudget { now.timeIntervalSince1970 * 1_000 >= resetAt ? .fresh(now: now, keyInvalid: keyInvalid) : self }
    var blocked: Bool { exhausted || keyInvalid }
    var allowsPrefetch: Bool { !blocked && used < Int(Double(limit) * Self.prefetchShare) }
}

enum OmdbResponse: Sendable {
    case json(JSONValue)
    case unauthorized
    case failure
}

actor OmdbService {
    static let shared = OmdbService()
    static let cacheLimit = 1_500
    static let missLimit = 1_000
    static let staleAfter: TimeInterval = 90 * 86_400
    static let missLifetime: TimeInterval = 86_400

    private let defaults: UserDefaults
    private let fetch: @Sendable (URL) async -> OmdbResponse
    private var cache: [String: OmdbScores] = [:]
    private var misses: [String: Double] = [:]
    private var budgetValue = OmdbBudget()
    private var inflight: [String: Task<OmdbScores?, Never>] = [:]
    private var loaded = false

    init(defaults: UserDefaults = .standard, fetch: @escaping @Sendable (URL) async -> OmdbResponse = OmdbService.network) {
        self.defaults = defaults; self.fetch = fetch
    }

    static let network: @Sendable (URL) async -> OmdbResponse = { url in
        do { return .json(try await HTTPClient().json(url.absoluteString, timeout: 15)) }
        catch let error as HarborError { return error.code == "http-401" ? .unauthorized : .failure }
        catch { return .failure }
    }

    static func url(key: String, imdbID: String, type: String?) -> URL? {
        var parts = URLComponents(string: "https://www.omdbapi.com/")
        parts?.queryItems = [URLQueryItem(name: "i", value: imdbID), URLQueryItem(name: "apikey", value: key)] + (type.map { [URLQueryItem(name: "type", value: $0)] } ?? [])
        return parts?.url
    }

    private func load(now: Date) {
        guard !loaded else { return }
        loaded = true
        if let data = defaults.data(forKey: "omdb.cache.v1"), let saved = try? JSONDecoder().decode([String: OmdbScores].self, from: data) { cache = saved }
        if let data = defaults.data(forKey: "omdb.misses.v1"), let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            misses = saved.filter { now.timeIntervalSince1970 * 1_000 - $0.value < Self.missLifetime * 1_000 }
        }
        if let data = defaults.data(forKey: "omdb.budget.v1"), let saved = try? JSONDecoder().decode(OmdbBudget.self, from: data) { budgetValue = saved.current(at: now) }
        else { budgetValue = .fresh(now: now) }
    }

    private func persist() {
        if cache.count > Self.cacheLimit {
            let newest = cache.sorted { $0.value.fetchedAt > $1.value.fetchedAt }.prefix(Self.cacheLimit)
            cache = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        if misses.count > Self.missLimit {
            let newest = misses.sorted { $0.value > $1.value }.prefix(Self.missLimit)
            misses = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: "omdb.cache.v1") }
        if let data = try? JSONEncoder().encode(misses) { defaults.set(data, forKey: "omdb.misses.v1") }
        if let data = try? JSONEncoder().encode(budgetValue) { defaults.set(data, forKey: "omdb.budget.v1") }
    }

    func budget(now: Date = Date()) -> OmdbBudget {
        load(now: now); budgetValue = budgetValue.current(at: now); return budgetValue
    }

    /// Desktop's `resetOmdbBudget`, run when a key is saved: a new allowance and no refusal held against the new key.
    func resetBudget(now: Date = Date()) {
        load(now: now); budgetValue = .fresh(now: now); persist()
    }

    func cached(_ imdbID: String, now: Date = Date()) -> OmdbScores? {
        load(now: now)
        guard let hit = cache[imdbID], now.timeIntervalSince1970 * 1_000 - hit.fetchedAt < Self.staleAfter * 1_000 else { return nil }
        return hit
    }

    /// Cached scores while they are fresh, otherwise one request (shared by callers asking at once).
    func scores(key: String, imdbID: String, type: String? = nil, now: Date = Date()) async -> OmdbScores? {
        let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, imdbID.hasPrefix("tt") else { return nil }
        if let hit = cached(imdbID, now: now) { return hit }
        if let pending = inflight[imdbID] { return await pending.value }
        budgetValue = budget(now: now)
        guard !budgetValue.blocked else { return nil }
        return await request(apiKey, imdbID, type, now: now)
    }

    /// Desktop's `omdbPrefetch`: warms the cache for titles shown elsewhere, without spending the last tenth of the day's allowance.
    func prefetch(key: String, imdbID: String, type: String? = nil, now: Date = Date()) async {
        let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, imdbID.hasPrefix("tt") else { return }
        load(now: now)
        if cache[imdbID] != nil || inflight[imdbID] != nil { return }
        if let missed = misses[imdbID], now.timeIntervalSince1970 * 1_000 - missed < Self.missLifetime * 1_000 { return }
        budgetValue = budget(now: now)
        guard budgetValue.allowsPrefetch else { return }
        _ = await request(apiKey, imdbID, type, now: now)
    }

    private func request(_ key: String, _ imdbID: String, _ type: String?, now: Date) async -> OmdbScores? {
        guard let url = Self.url(key: key, imdbID: imdbID, type: type) else { return nil }
        let task = Task<OmdbScores?, Never> {
            let response = await fetch(url)
            return await finish(response, imdbID: imdbID, now: now)
        }
        inflight[imdbID] = task
        let result = await task.value
        inflight[imdbID] = nil
        return result
    }

    private func finish(_ response: OmdbResponse, imdbID: String, now: Date) -> OmdbScores? {
        switch response {
        case .unauthorized:
            budgetValue.keyInvalid = true; persist(); return nil
        case .failure:
            return nil
        case .json(let json):
            switch OmdbParser.parse(json, now: now) {
            case .keyInvalid:
                budgetValue.keyInvalid = true; persist(); return nil
            case .exhausted:
                budgetValue.exhausted = true; budgetValue.used = budgetValue.limit; budgetValue.keyInvalid = false; persist(); return nil
            case .miss:
                budgetValue.used += 1; misses[imdbID] = now.timeIntervalSince1970 * 1_000; persist(); return nil
            case .scores(let scores):
                budgetValue.used += 1; budgetValue.keyInvalid = false; budgetValue.exhausted = false
                cache[imdbID] = scores; misses[imdbID] = nil; persist(); return scores
            }
        }
    }
}

// MARK: MDBList (Desktop's lib/providers/mdblist.ts)

struct MdblistScores: Equatable, Sendable {
    var score: Double?
    var letterboxd: Double?
    var trakt: Double?
    var metacritic: Double?
    var rtAudience: Double?
    var simkl: Double?
    var isEmpty: Bool { [score, letterboxd, trakt, metacritic, rtAudience, simkl].allSatisfy { $0 == nil } }
}

enum MdblistParser {
    private static func positive(_ values: Double?...) -> Double? { values.compactMap { $0 }.first { $0 > 0 } }

    /// Nil unless the reply carries a `ratings` list, which tells a real answer from an error page.
    static func parse(_ json: JSONValue) -> MdblistScores? {
        guard case .array(let rows) = json["ratings"] else { return nil }
        func number(_ value: JSONValue) -> Double? { value.textValue.flatMap { Double($0) } }
        func value(_ source: String) -> Double? {
            guard let row = rows.first(where: { $0["source"].string == source }), let found = number(row["value"]), found > 0 else { return nil }
            return found
        }
        let simkl = value("simkl")
        return MdblistScores(score: positive(number(json["score_average"]), number(json["scoreaverage"]), number(json["score"])),
                             letterboxd: value("letterboxd"), trakt: value("trakt"), metacritic: value("metacritic"),
                             rtAudience: value("tomatoesaudience") ?? value("audience") ?? value("popcorn"),
                             simkl: simkl.map { $0 > 10 ? $0 / 10 : $0 })
    }
}

actor MdblistService {
    static let shared = MdblistService()
    static let lifetime: TimeInterval = 86_400
    static let retry: TimeInterval = 60
    static let cacheLimit = 256

    private let fetch: @Sendable (URL) async -> JSONValue?
    private var cache: [String: (scores: MdblistScores?, expires: Date)] = [:]
    private var inflight: [String: Task<MdblistScores?, Never>] = [:]

    init(fetch: @escaping @Sendable (URL) async -> JSONValue? = MdblistService.network) { self.fetch = fetch }

    static let network: @Sendable (URL) async -> JSONValue? = { url in try? await HTTPClient().json(url.absoluteString, timeout: 15) }

    static func urls(key: String, imdbID: String, type: String) -> [URL] {
        var modern = URLComponents(string: "https://api.mdblist.com/imdb/\(type)/\(imdbID)")
        modern?.queryItems = [URLQueryItem(name: "apikey", value: key)]
        var legacy = URLComponents(string: "https://mdblist.com/api/")
        legacy?.queryItems = [URLQueryItem(name: "apikey", value: key), URLQueryItem(name: "i", value: imdbID)]
        return [modern?.url, legacy?.url].compactMap { $0 }
    }

    /// Scores for an IMDb id; `type` is "movie" or "show". A failure is remembered for a minute, a result for a day.
    func scores(key: String, imdbID: String, type: String = "movie", now: Date = Date()) async -> MdblistScores? {
        let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, imdbID.hasPrefix("tt") else { return nil }
        // A corrected key must not reuse an earlier failure or pending request.
        let id = [apiKey, type, imdbID].joined(separator: "|")
        if let hit = cache[id] { if now < hit.expires { return hit.scores }; cache[id] = nil }
        if let pending = inflight[id] { return await pending.value }
        let urls = Self.urls(key: apiKey, imdbID: imdbID, type: type)
        let load = self.fetch
        let task = Task<MdblistScores?, Never> {
            for url in urls { if let json = await load(url), let parsed = MdblistParser.parse(json) { return parsed } }
            return nil
        }
        inflight[id] = task
        let result = await task.value
        inflight[id] = nil
        if cache.count >= Self.cacheLimit, let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key { cache[oldest] = nil }
        let useful = result.map { !$0.isEmpty } ?? false
        cache[id] = (result, now.addingTimeInterval(useful ? Self.lifetime : Self.retry))
        return result
    }
}
