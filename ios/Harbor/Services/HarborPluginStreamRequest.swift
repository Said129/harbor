import Foundation

struct HarborPluginTMDBReference: Codable, Equatable, Sendable {
    let id: Int
    let kind: String
    var json: JSONValue { .object(["id": .integer(Int64(id)), "kind": .string(kind)]) }
}

struct HarborPluginResolvedMetadata: Sendable {
    var tmdb: HarborPluginTMDBReference?
    var title: String?
    var year: Int?
    var nameAttempted = false
}

/// The cache contains public identifiers only. Keys and plugin configuration are never persisted.
actor HarborPluginMetadataResolver {
    static let shared = HarborPluginMetadataResolver()
    typealias FetchTMDB = @Sendable (String, String, String) async throws -> HarborPluginTMDBReference?
    typealias FetchCinemeta = @Sendable (String, String) async throws -> JSONValue
    private struct Entry: Codable { let key: String; let value: HarborPluginTMDBReference }
    private struct Pending { let id: UUID; let task: Task<HarborPluginResolvedMetadata, Never> }
    private let defaults: UserDefaults
    private let fetchTMDB: FetchTMDB
    private let fetchCinemeta: FetchCinemeta
    private let now: @Sendable () -> TimeInterval
    private var cached: [Entry] = []
    private var named: [String: HarborPluginResolvedMetadata] = [:]
    private var misses: [String: TimeInterval] = [:]
    private var pending: [String: Pending] = [:]
    private let cacheKey = "ios.plugins.public-tmdb.v1"

    init(defaultsName: String? = nil, now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        fetchTMDB: @escaping FetchTMDB = { imdb, type, key in try await TMDBService().pluginReference(imdb: imdb, type: type, key: key) },
        fetchCinemeta: @escaping FetchCinemeta = { imdb, type in try await HTTPClient().json("https://v3-cinemeta.strem.io/meta/\(type)/\(imdb).json")["meta"] }) {
        let defaults = defaultsName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.defaults = defaults; self.now = now; self.fetchTMDB = fetchTMDB; self.fetchCinemeta = fetchCinemeta
        if let data = defaults.data(forKey: cacheKey), data.count <= 256 * 1024,
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            var seen = Set<String>()
            cached = Array(entries.filter { $0.value.id > 0 && ["movie", "tv"].contains($0.value.kind) && seen.insert($0.key).inserted }.suffix(500))
        }
    }

    func resolve(imdb: String, type: String, tmdbKey: String, needsName: Bool) async throws -> HarborPluginResolvedMetadata {
        try Task.checkCancellation()
        guard imdb.range(of: "^tt[0-9]+$", options: .regularExpression) != nil, ["movie", "series"].contains(type) else { return .init() }
        let key = imdb + ":" + (type == "series" ? "tv" : "movie")
        let hit = cached.first { $0.key == key }?.value
        let name = named[key]
        let missed = misses[key].map { now() - $0 < 600 } ?? false
        if (hit != nil || missed) && (!needsName || name != nil) { return .init(tmdb: hit, title: name?.title, year: name?.year) }
        // A caller may need a name while another only needs the id. Sharing the full public
        // Cinemeta result lets either caller finish without inheriting the other's cancellation.
        let operation: Pending
        if let running = pending[key] { operation = running }
        else {
            let tmdbFetch = fetchTMDB, metaFetch = fetchCinemeta
            let task = Task {
                var result = HarborPluginResolvedMetadata(tmdb: hit, title: name?.title, year: name?.year)
                if result.tmdb == nil && !missed && !tmdbKey.isEmpty { result.tmdb = try? await tmdbFetch(imdb, type, tmdbKey) }
                // Fetch the name along with a missing public mapping, so concurrent plugins
                // reuse one response even when their request contexts differ.
                if result.tmdb == nil && !missed || needsName && result.title == nil {
                    result.nameAttempted = true
                    if let meta = try? await metaFetch(imdb, type) {
                        if result.tmdb == nil, let id = meta["moviedb_id"].integer, id > 0 {
                            result.tmdb = .init(id: id, kind: type == "series" ? "tv" : "movie")
                        }
                        let title = meta["name"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let title, !title.isEmpty { result.title = title; result.year = HarborPluginStreamRequest.year(meta["releaseInfo"].textValue) }
                    }
                }
                return result
            }
            operation = Pending(id: UUID(), task: task); pending[key] = operation
        }
        let result = await operation.task.value
        if pending[key]?.id == operation.id { pending[key] = nil }
        if let ref = result.tmdb {
            if !cached.contains(where: { $0.key == key }) {
                cached.append(.init(key: key, value: ref)); cached = Array(cached.suffix(500))
                if let data = try? JSONEncoder().encode(cached) { defaults.set(data, forKey: cacheKey) }
            }
            misses[key] = nil
        } else {
            if misses.count >= 500 { misses = misses.filter { now() - $0.value < 600 } }
            if misses.count >= 500 { misses.removeValue(forKey: misses.keys.sorted().first!) }
            misses[key] = now()
        }
        if result.title != nil { if named.count > 500 { named = [:] }; named[key] = result }
        try Task.checkCancellation()
        // An id-only in-flight TMDB lookup may not have needed Cinemeta. A caller needing
        // a title starts/joins one name lookup after that result, without dropping its context.
        if needsName && result.title == nil && !result.nameAttempted {
            return try await resolve(imdb: imdb, type: type, tmdbKey: tmdbKey, needsName: true)
        }
        try Task.checkCancellation(); return result
    }
}

enum HarborPluginStreamRequest {
    static func year(_ value: String?) -> Int? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let range = text.range(of: "^[+-]?[0-9]+", options: .regularExpression),
              let number = Int(text[range]), number != 0, abs(Double(number)) <= 9_007_199_254_740_991 else { return nil }
        return number
    }
    static func tmdb(_ ids: [String], type: String) -> HarborPluginTMDBReference? {
        for id in ids {
            let fields = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard fields.first == "tmdb", fields.count > 1 else { continue }
            let explicit = ["movie", "tv"].contains(fields[1]), index = explicit ? 2 : 1
            guard fields.count > index, let range = fields[index].range(of: "^[0-9]+", options: .regularExpression),
                  let number = Int(fields[index][range]), number >= 0, Double(number) <= 9_007_199_254_740_991 else { continue }
            return .init(id: number, kind: explicit ? fields[1] : type == "series" ? "tv" : "movie")
        }
        return nil
    }
    static func imdb(_ ids: [String]) -> String? {
        for id in ids { if let range = id.range(of: "^tt[0-9]+", options: .regularExpression) { return String(id[range]) } }
        return nil
    }
    static func coordinates(_ id: String) -> (season: Int, episode: Int)? {
        guard id.range(of: "^(?:tt[0-9]+|tmdb:(?:movie:|tv:)?[0-9]+):[0-9]+:[0-9]+$", options: .regularExpression) != nil else { return nil }
        let fields = id.split(separator: ":")
        guard let season = Int(fields[fields.count - 2]), let episode = Int(fields.last!) else { return nil }
        return (season, episode)
    }
    static func build(media: Media, ids: [String], pickedID: String, episode: Episode?,
        tmdbKey: String, resolver: HarborPluginMetadataResolver = .shared) async throws -> JSONValue {
        let type = media.type == "series" || media.type == "anime" ? "series" : "movie"
        let imdbID = episode?.imdbID ?? media.imdbID ?? imdb(ids)
        var ref = tmdb(ids, type: type), title = media.name.trimmingCharacters(in: .whitespacesAndNewlines), releasedYear = year(media.releaseInfo)
        if let imdbID, ref == nil || title.isEmpty {
            let resolved = try await resolver.resolve(imdb: imdbID, type: type, tmdbKey: tmdbKey, needsName: title.isEmpty)
            ref = ref ?? resolved.tmdb
            if title.isEmpty { title = resolved.title ?? ""; releasedYear = releasedYear ?? resolved.year }
        }
        let raw = coordinates(pickedID)
        // Display season/episode and absolute numbering never replace the provider's raw pair.
        return .object(["type": .string(type), "id": .string(pickedID), "ids": .array(ids.map(JSONValue.string)),
            "imdbId": imdbID.map(JSONValue.string) ?? .null, "tmdb": ref?.json ?? .null, "title": .string(title),
            "year": releasedYear.map { .integer(Int64($0)) } ?? .null,
            "season": (episode?.season ?? raw?.season).map { .integer(Int64($0)) } ?? .null,
            "episode": (episode?.episode ?? raw?.episode).map { .integer(Int64($0)) } ?? .null,
            "absoluteEpisode": episode?.absoluteNumber.map { .integer(Int64($0)) } ?? .null, "settings": .object([:])])
    }
}
