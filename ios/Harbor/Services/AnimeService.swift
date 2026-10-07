import Foundation

actor AnimeService {
    static let shared = AnimeService()
    private let http = HTTPClient()
    private var cache: [String: (Date, [Media])] = [:]
    private var pending: [String: Task<[Media], Error>] = [:]
    private var nextJikan = Date.distantPast

    static func definitions() -> [DiscoveryRail] {
        [DiscoveryRail(id: "anime-picks", title: "Top Picks for You", kind: "anime", path: "anime:picks"),
         DiscoveryRail(id: "anilist-trending", title: "Trending on AniList", kind: "anime", path: "anilist:TRENDING_DESC"),
         DiscoveryRail(id: "anilist-top100", title: "Top 100 on AniList", kind: "anime", path: "anilist:SCORE_DESC"),
         DiscoveryRail(id: "anime-awards", title: "Award Winning Anime", kind: "anime", path: "anime:awards"),
         DiscoveryRail(id: "anime-airing", title: "Airing Now", kind: "anime", path: "jikan:seasons/now"),
         DiscoveryRail(id: "anime-upcoming", title: "Upcoming Season", kind: "anime", path: "jikan:seasons/upcoming"),
         DiscoveryRail(id: "anime-top-tv", title: "Top Series on MAL", kind: "anime", path: "jikan:top/anime", parameters: ["type": "tv"]),
         DiscoveryRail(id: "anime-top-movies", title: "Top Movies on MAL", kind: "anime", path: "jikan:top/anime", parameters: ["type": "movie"]),
         DiscoveryRail(id: "anime-popular", title: "Most Popular on MAL", kind: "anime", path: "jikan:top/anime", parameters: ["filter": "bypopularity"])]
    }

    func page(_ rail: DiscoveryRail, page: Int) async throws -> [Media] {
        guard (1...100).contains(page) else { return [] }
        let key = rail.id + ":" + String(page)
        if let hit = cache[key], Date().timeIntervalSince(hit.0) < 3_600 { return hit.1 }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await self.fetch(rail, page: page) }
        pending[key] = task
        defer { pending[key] = nil }
        let result = try await task.value
        if cache.count >= 100 { cache.removeValue(forKey: cache.min { $0.value.0 < $1.value.0 }!.key) }
        cache[key] = (Date(), result)
        return result
    }

    private func fetch(_ rail: DiscoveryRail, page: Int) async throws -> [Media] {
        if rail.path.hasPrefix("anilist:") {
            let top = rail.id == "anilist-top100"
            guard page <= (top ? 2 : 1) else { return [] }
            let query = "query($page:Int,$count:Int,$sort:[MediaSort]){Page(page:$page,perPage:$count){media(type:ANIME,isAdult:false,sort:$sort){id idMal title{english userPreferred romaji}coverImage{extraLarge large}bannerImage format averageScore seasonYear description genres status}}}"
            let data = try await http.anilist(query: query, variables: .object(["page": .integer(Int64(page)), "count": .integer(top ? 50 : 40), "sort": .array([.string(String(rail.path.dropFirst(8)))])]))
            guard case .array(let values) = data["Page"]["media"] else { throw HarborError(code: "anime-response") }
            return Self.unique(values.compactMap(Self.anilistMedia))
        }
        if rail.path == "anime:awards" {
            struct Catalog: Decodable { struct Entry: Decodable { let id: String }; let winners: [Entry] }
            guard let url = Bundle.main.url(forResource: "DesktopAnimeAwards", withExtension: "json"),
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)) else { throw HarborError(code: "anime-awards") }
            // Small batches keep the public metadata provider responsive.
            let offset = (page - 1) * 24
            guard offset < catalog.winners.count else { return [] }
            let winners = Array(catalog.winners[offset..<min(offset + 24, catalog.winners.count)])
            var result: [Media] = []
            for start in stride(from: 0, to: winners.count, by: 4) {
                try Task.checkCancellation()
                let entries = winners[start..<min(start + 4, winners.count)]
                let fetched = await withTaskGroup(of: (Int, Media?).self) { group in
                    for (index, entry) in entries.enumerated() {
                        group.addTask { (index, try? await Self.metadata(id: entry.id, kind: "series")) }
                    }
                    var batch: [(Int, Media)] = []
                    for await (index, media) in group { if let media { batch.append((index, media)) } }
                    return batch.sorted { $0.0 < $1.0 }.map(\.1)
                }
                result.append(contentsOf: fetched)
            }
            guard !result.isEmpty else { throw HarborError(code: "anime-awards") }
            return Self.unique(result)
        }
        if rail.path.hasPrefix("jikan:") {
            // Reserve a slot before suspension; concurrent rail requests cannot burst the API.
            let delay = max(0, nextJikan.timeIntervalSinceNow)
            nextJikan = Date().addingTimeInterval(delay + 0.45)
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            var url = URLComponents(string: "https://api.jikan.moe/v4/" + String(rail.path.dropFirst(6)))!
            var params = rail.parameters; params["page"] = String(page); params["sfw"] = "true"
            url.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            let response = try await http.json(url.url!.absoluteString)
            guard case .array(let values) = response["data"] else { throw HarborError(code: "anime-response") }
            return Self.unique(values.compactMap(Self.jikanMedia))
        }
        throw HarborError(code: "anime-catalog")
    }

    func picks(records: [LibraryRecord]) async throws -> [Media] {
        let active = records.compactMap(\.media).filter { Self.isAnime($0.id) }
        let excluded = Set(active.map { Self.nameKey($0.name) })
        let excludedIDs = Set(active.map(\.id))
        let genres = Array(Set(active.flatMap { $0.genres ?? [] })).sorted()
        var candidates: [Media] = []
        for title in ["anime-airing", "anime-popular"] {
            if let rail = Self.definitions().first(where: { $0.id == title }), let items = try? await page(rail, page: 1) { candidates.append(contentsOf: items) }
        }
        guard !candidates.isEmpty else { throw HarborError(code: "anime-picks") }
        return Array(Self.unique(candidates).filter { !excludedIDs.contains($0.id) && !excluded.contains(Self.nameKey($0.name)) }
            .sorted { first, second in
                let a = (first.genres ?? []).filter { genres.contains($0) }.count
                let b = (second.genres ?? []).filter { genres.contains($0) }.count
                return a == b ? (Double(first.imdbRating ?? "") ?? 0) > (Double(second.imdbRating ?? "") ?? 0) : a > b
            }.prefix(24))
    }

    static func isAnime(_ id: String) -> Bool { id.range(of: "^(kitsu|mal|anilist|anidb):[0-9]+$", options: .regularExpression) != nil }
    static func metadata(id: String, kind: String) async throws -> Media {
        guard isAnime(id), let safe = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { throw HarborError(code: "anime-id") }
        for type in [kind == "movie" ? "movie" : "series", kind == "movie" ? "series" : "movie"] {
            let response = try? await HTTPClient().json("https://anime-kitsu.strem.fun/meta/\(type)/\(safe).json")
            if let response, let media = Media.parse(response["meta"], kind: type) { return media }
        }
        throw HarborError(code: "no-metadata")
    }
    private static func nameKey(_ name: String) -> String { name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en")) }
    private static func unique(_ items: [Media]) -> [Media] { var ids = Set<String>(); return items.filter { ids.insert($0.identity).inserted } }
    private static func plain(_ value: String?) -> String? { value?.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'") }
    private static func anilistMedia(_ value: JSONValue) -> Media? {
        guard let id = value["id"].integer, let name = value["title"]["english"].string ?? value["title"]["userPreferred"].string ?? value["title"]["romaji"].string else { return nil }
        var media = Media(id: value["idMal"].integer.map { "mal:\($0)" } ?? "anilist:\(id)", type: value["format"].string == "MOVIE" ? "movie" : "series", name: name)
        media.poster = value["coverImage"]["extraLarge"].string ?? value["coverImage"]["large"].string
        media.background = value["bannerImage"].string; media.description = plain(value["description"].string)
        media.releaseInfo = value["seasonYear"].integer.map(String.init); media.genres = value["genres"].array.compactMap(\.string)
        if let score = value["averageScore"].numericValue, score > 0 { media.imdbRating = String(format: "%.1f", score / 10); media.ratingSource = "AniList" }
        return media
    }
    private static func jikanMedia(_ value: JSONValue) -> Media? {
        guard let id = value["mal_id"].integer, let name = value["title_english"].string ?? value["title"].string else { return nil }
        var media = Media(id: "mal:\(id)", type: value["type"].string == "Movie" ? "movie" : "series", name: name)
        media.poster = value["images"]["webp"]["large_image_url"].string ?? value["images"]["jpg"]["large_image_url"].string
        media.description = plain(value["synopsis"].string); media.releaseInfo = value["year"].integer.map(String.init)
        media.genres = value["genres"].array.compactMap { $0["name"].string }
        if let score = value["score"].numericValue, score > 0 { media.imdbRating = String(format: "%.1f", score); media.ratingSource = "MAL" }
        return media
    }
}
