import Foundation

enum TrackerCatalogRequest: Equatable, Sendable {
    case searchShows(String), searchMovies(String), seasons(TrackerShowIDs), tmdbShow(Int), cinemetaSeries(String)
}

/// Public metadata only: no Trakt login is needed for the shared episode resolver.
actor TrackerEpisodeResolver {
    static let shared = TrackerEpisodeResolver()
    typealias Response = @Sendable (TrackerCatalogRequest) async throws -> JSONValue
    private struct Entry: Codable { let at: Date; let result: TrackerResolutionResult }
    private let response: Response
    private let now: @Sendable () -> Date
    private let cacheURL: URL?
    private var cache: [String: Entry] = [:]
    private var pending: [String: Task<TrackerResolutionResult, Never>] = [:]
    private var metaPending: [String: Task<TrackerResolutionResult, Never>] = [:]
    private var tmdbIDs: [Int: TrackerShowIDs] = [:]
    private struct SpecialEntry { let ids: TrackerShowIDs? }
    private var specialMovies: [String: SpecialEntry] = [:]
    private var pendingSpecialMovies: [String: Task<TrackerShowIDs?, Never>] = [:]
    init(response: @escaping Response = { try await HTTPClient().trackerCatalog($0) }, now: @escaping @Sendable () -> Date = { Date() },
         cacheURL: URL? = URL.applicationSupportDirectory.appendingPathComponent("HarborTrackerResolution", isDirectory: true).appendingPathComponent("episodes.json")) {
        self.response = response; self.now = now; self.cacheURL = cacheURL
        if let cacheURL, let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size <= 2 * 1_024 * 1_024, let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data), saved.count <= 400 {
            cache = saved.filter { key, entry in
                key.count == 64 && entry.result.reason != "error" && Self.fresh(entry, now: now())
                    && (entry.result.episode.map { $0.season >= 0 && $0.number > 0 && $0.showIds.parameter != nil } ?? (entry.result.reason == "not-found"))
            }
        }
    }
    private static func fresh(_ entry: Entry, now: Date) -> Bool {
        let age = now.timeIntervalSince(entry.at)
        return age >= 0 && age < (entry.result.episode == nil ? 600 : 7 * 24 * 60 * 60)
    }
    func resolve(metaID: String, season: Int, number: Int) async -> TrackerResolutionResult {
        guard season >= 0, season <= 100_000, number > 0, number <= 1_000_000, metaID.utf8.count <= 1_024, !Task.isCancelled else { return .error }
        let key = "\(metaID)|\(season)|\(number)"
        if let task = metaPending[key] { return await task.value }
        let task = Task { [self] in
            guard let identity = try? await hydrate(metaID: metaID, season: season, number: number) else { return TrackerResolutionResult.error }
            return await resolve(identity)
        }
        metaPending[key] = task
        let result = await task.value; metaPending[key] = nil; return result
    }
    func resolve(_ identity: TrackerEpisodeIdentity) async -> TrackerResolutionResult {
        guard !Task.isCancelled, identity.season >= 0, identity.season <= 100_000, identity.number > 0,
              !identity.showTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, identity.key.utf8.count <= 8_192 else { return .error }
        let key = EBookShelf.hash(identity.key)
        if let entry = cache[key], Self.fresh(entry, now: now()) { return entry.result }
        cache[key] = nil
        if let task = pending[key] { return await task.value }
        let task = Task { await self.perform(identity) }; pending[key] = task
        let result = await task.value; pending[key] = nil
        if result.episode != nil || result.reason == "not-found" {
            cache[key] = Entry(at: now(), result: result)
            if cache.count > 400 {
                for key in cache.sorted(by: { $0.value.at < $1.value.at }).prefix(cache.count - 400).map(\.key) { cache[key] = nil }
            }
            persist()
        }
        return result
    }
    func specialMovie(metaID: String, season: Int, number: Int) async -> TrackerShowIDs? {
        guard season >= 0, season <= 100_000, number > 0, number <= 1_000_000, metaID.utf8.count <= 1_024,
              !Task.isCancelled, let identity = try? await hydrate(metaID: metaID, season: season, number: number) else { return nil }
        let key = [TrackerEpisodeMatch.normalize(identity.showTitle), identity.showYear.map(String.init) ?? "", TrackerEpisodeMatch.normalize(identity.name)].joined(separator: "|")
        if let cached = specialMovies[key] { return cached.ids }
        if let pending = pendingSpecialMovies[key] { return await pending.value }
        let task = Task<TrackerShowIDs?, Never> {
            do {
                let raw = try await self.response(.searchMovies(identity.name ?? ""))
                var seen = Set<String>()
                let candidates = raw.array.compactMap { row -> (TrackerShowIDs, JSONValue)? in
                    let movie = row["movie"], ids = TrackerShowIDs(movie["ids"])
                    guard movie != .null, let id = ids.parameter, seen.insert(id).inserted else { return nil }
                    return (ids, movie)
                }
                let result = candidates.first { TrackerEpisodeMatch.movieMatches(identity, title: $0.1["title"].string, year: $0.1["year"].integer) }?.0
                if self.specialMovies.count >= 200 { self.specialMovies.removeAll() }
                self.specialMovies[key] = SpecialEntry(ids: result); return result
            } catch { return nil }
        }
        pendingSpecialMovies[key] = task
        let result = await task.value; pendingSpecialMovies[key] = nil; return result
    }
    private func persist() {
        guard let cacheURL else { return }
        do {
            let data = try JSONEncoder().encode(cache); guard data.count <= 2 * 1_024 * 1_024 else { return }
            let root = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var directory = root, values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        } catch { /* A disposable metadata cache must not interrupt playback. */ }
    }
    private func hydrate(metaID: String, season: Int, number: Int) async throws -> TrackerEpisodeIdentity? {
        let parts = metaID.split(separator: ":").map(String.init)
        let imdb: String
        if let first = parts.first, first.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { imdb = first }
        else if parts.count >= 3, parts[0] == "tmdb", ["tv", "movie"].contains(parts[1]), let id = Int(parts[2]), id > 0 {
            let ids: TrackerShowIDs?
            if let cached = tmdbIDs[id] { ids = cached }
            else {
                let rows = try await response(.tmdbShow(id))
                ids = rows.array.lazy.map { TrackerShowIDs($0["show"]["ids"]) }.first { $0.json["imdb"].string != nil || $0.json["trakt"].integer != nil }
                if let ids { if tmdbIDs.count >= 400 { tmdbIDs.removeAll() }; tmdbIDs[id] = ids }
            }
            guard let value = ids?.json["imdb"].string else { return nil }; imdb = value
        } else { return nil }
        // Force Cinemeta as the source of episode ids even when an installed
        // addon supplies the visible details with a different season ordering.
        let raw = try await response(.cinemetaSeries(imdb)), series = raw["meta"]
        guard let title = series["name"].string, !title.isEmpty else { return nil }
        let video = series["videos"].array.first { ($0["season"].integer ?? 0) == season && ($0["episode"].integer ?? $0["number"].integer) == number } ?? .null
        let release = series["releaseInfo"].string ?? ""
        let yearRange = release.range(of: "[0-9]{4}", options: .regularExpression)
        let episodeIMDb = video["imdb_id"].string.flatMap { $0.range(of: "^tt[0-9]+$", options: .regularExpression) != nil ? $0 : nil }
        let name: String?, airDate: String?
        if let value = video["name"].string { name = value } else { name = video["title"].string }
        if let value = video["released"].string { airDate = value } else { airDate = video["firstAired"].string }
        return .init(showTitle: title, showYear: yearRange.flatMap { Int(release[$0]) }, season: season, number: number,
            name: name, airDate: airDate,
            episodeTvdbId: video["tvdb_id"].integer, episodeImdbId: episodeIMDb)
    }
    private func perform(_ identity: TrackerEpisodeIdentity) async -> TrackerResolutionResult {
        do {
            let raw = try await response(.searchShows(identity.showTitle))
            var candidates: [TrackerShowCandidate] = [], seen = Set<String>()
            for row in raw.array {
                let show = row["show"], ids = TrackerShowIDs(show["ids"])
                guard let key = ids.parameter, seen.insert(key).inserted else { continue }
                candidates.append(.init(showIds: ids, title: show["title"].string ?? "", year: show["year"].integer))
                if candidates.count == 5 { break }
            }
            if candidates.isEmpty { return .notFound }
            var evaluated = false
            var fallback: TrackerResolvedEpisode?
            for candidate in candidates {
                let raw = try await response(.seasons(candidate.showIds))
                let seasons = raw.array.compactMap { row -> TrackerSeasonListing? in
                    guard let season = row["number"].integer, season >= 0 else { return nil }
                    return .init(number: season, episodes: row["episodes"].array.compactMap { episode in
                        guard let number = episode["number"].integer, number > 0 else { return nil }
                        return .init(number: number, title: episode["title"].string,
                            airDate: episode["first_aired"].string ?? episode["released"].string,
                            tvdbId: episode["ids"]["tvdb"].integer, imdbId: episode["ids"]["imdb"].string)
                    })
                }
                if seasons.isEmpty { continue }
                if TrackerEpisodeMatch.comparable(identity, seasons) { evaluated = true }
                if let exact = TrackerEpisodeMatch.exact(identity, seasons) {
                    return .found(.init(showIds: candidate.showIds, season: exact.season, number: exact.number))
                }
                if fallback == nil, TrackerEpisodeMatch.normalize(candidate.title) == TrackerEpisodeMatch.normalize(identity.showTitle),
                   identity.showYear == nil || candidate.year == identity.showYear, let hit = TrackerEpisodeMatch.find(identity, seasons) {
                    fallback = .init(showIds: candidate.showIds, season: hit.season, number: hit.number)
                }
            }
            if let fallback { return .found(fallback) }; return evaluated ? .notFound : .error
        } catch { return .error }
    }
}
