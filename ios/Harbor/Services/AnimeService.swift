import Foundation

actor AnimeService {
    static let shared = AnimeService()
    private let http = HTTPClient()
    private struct Cached: Codable { let at: Date; let items: [Media] }
    private var cache: [String: Cached] = [:]
    private var cacheLoaded = false
    private var pending: [String: Task<[Media], Error>] = [:]
    private var nextJikan = Date.distantPast
    private var cacheURL: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("harbor-public-anime-rails.json")
    }
    private static let fallbackAge: TimeInterval = 7 * 24 * 3_600

    static func definitions() -> [DiscoveryRail] {
        [DiscoveryRail(id: "anime-picks", title: "Top Picks for You", kind: "anime", path: "anime:picks"),
         DiscoveryRail(id: "anilist-trending", title: "Trending on AniList", kind: "anime", path: "anilist:TRENDING_DESC"),
         DiscoveryRail(id: "anilist-top100", title: "Top 100 on AniList", kind: "anime", path: "anilist:SCORE_DESC"),
         DiscoveryRail(id: "anime-awards", title: "Award Winning Anime", kind: "anime", path: "anime:awards")]
            + ((try? DesktopAnimeRows.read().rows.map(\.rail)) ?? [])
    }

    static func homeDefinitions() -> [DiscoveryRail] {
        [DiscoveryRail(id: "home-anime-airing", title: DesktopInterfaceText.value("Trending Anime"), kind: "anime", path: "jikan:top/anime", parameters: ["filter": "airing"]),
         DiscoveryRail(id: "home-anime-new", title: DesktopInterfaceText.value("New Anime Releases"), kind: "anime", path: "jikan:anime", parameters: ["order_by": "start_date", "sort": "desc", "status": "airing", "min_score": "6"]),
         DiscoveryRail(id: "home-anime-popular", title: DesktopInterfaceText.value("Popular Anime"), kind: "anime", path: "jikan:top/anime", parameters: ["filter": "bypopularity"]),
         DiscoveryRail(id: "home-anime-upcoming", title: DesktopInterfaceText.value("Upcoming Anime"), kind: "anime", path: "jikan:seasons/upcoming")]
    }

    func homeRows() async -> [DiscoveryRail] {
        let definitions = Self.homeDefinitions()
        return await withTaskGroup(of: (Int, DiscoveryRail?).self) { group in
            for (index, definition) in definitions.enumerated() {
                group.addTask {
                    var titles: [Media] = [], failed = false, seen = Set<String>()
                    for number in 1...3 {
                        guard !Task.isCancelled else { return (index, nil) }
                        do {
                            let page = try await self.page(definition, page: number)
                            titles.append(contentsOf: page.filter { seen.insert($0.identity).inserted })
                        } catch { failed = true }
                    }
                    guard !Task.isCancelled, titles.count >= 6 || !failed else { return (index, nil) }
                    let cleaned: [Media] = titles.count >= 6 ? Array(titles.prefix(60)).map { (media: Media) -> Media in
                        var result = media; result.name = Self.homeFranchiseTitle(media.name); return result
                    } : []
                    return (index, DiscoveryRail(id: String(definition.id.dropFirst(5)), title: definition.title, kind: "anime", path: "home:fixed", metas: cleaned))
                }
            }
            var received: [(Int, DiscoveryRail)] = []
            for await (index, row) in group { if let row { received.append((index, row)) } }
            return received.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private static func homeFranchiseTitle(_ name: String) -> String {
        let patterns = [
            #"(?i)\s*[-:]?\s*(?:1st|2nd|3rd|4th|5th|6th|7th|8th|9th|10th|11th|12th|First|Second|Third|Fourth|Fifth|Sixth|Seventh|Eighth|Ninth|Tenth|Final|Last)\s+(?:Season|Cour|Part)\b.*$"#,
            #"(?i)\s*[-:]?\s*Season\s+\d+\b.*$"#,
            #"(?i)\s+S\d+(?:\s|$).*"#,
            #"(?i)\s*[-:]?\s*(?:Part|Cour|Chapter)\s+\d+\b.*$"#,
            #"\s+(?:II|III|IV|V|VI|VII|VIII|IX|X)\s*$"#,
            #"[\s°'."’˚_:\-]+$"#
        ]
        return patterns.reduce(name) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func page(_ rail: DiscoveryRail, page: Int) async throws -> [Media] {
        guard (1...100).contains(page) else { return [] }
        loadCache()
        let key = rail.id + ":" + String(page)
        if let hit = cache[key], Date().timeIntervalSince(hit.at) < 3_600 { return hit.items }
        if let task = pending[key] { return try await task.value }
        let task = Task { try await self.fetch(rail, page: page) }
        pending[key] = task
        defer { pending[key] = nil }
        do {
            let result = try await task.value
            // Empty pages and failed loads must not replace a working catalog.
            if !result.isEmpty {
                if cache.count >= 100 { cache.removeValue(forKey: cache.min { $0.value.at < $1.value.at }!.key) }
                cache[key] = Cached(at: Date(), items: result)
                persistCache()
            }
            return result
        } catch is CancellationError { throw CancellationError() }
        catch {
            if let hit = cache[key], Date().timeIntervalSince(hit.at) <= Self.fallbackAge { return hit.items }
            throw error
        }
    }

    private func loadCache() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let url = cacheURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 4 * 1_024 * 1_024,
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([String: Cached].self, from: data), entries.count <= 100 else { return }
        let validIDs = Set((Self.definitions() + Self.homeDefinitions()).map(\.id))
        let now = Date()
        cache = entries.filter { key, entry in
            let components = key.split(separator: ":")
            guard components.count == 2, validIDs.contains(String(components[0])), let page = Int(components[1]), (1...100).contains(page),
                  !entry.items.isEmpty, entry.items.count <= 100, now.timeIntervalSince(entry.at) >= -60, now.timeIntervalSince(entry.at) <= Self.fallbackAge else { return false }
            // Earlier AniList caches used MAL aliases, which can identify more
            // than one AniList entry. Reload those public rails with native IDs.
            if String(components[0]).hasPrefix("anilist-"), !entry.items.allSatisfy({ $0.id.hasPrefix("anilist:") }) { return false }
            return entry.items.allSatisfy { Self.isAnime($0.id) && !$0.name.isEmpty }
        }
    }

    private func persistCache() {
        guard let url = cacheURL else { return }
        // Only provider rails are persisted. Personalized recommendations and
        // account history never enter this shared public cache.
        let validIDs = Set((Self.definitions() + Self.homeDefinitions()).map(\.id))
        let entries = cache.filter { validIDs.contains(String($0.key.split(separator: ":").first ?? "")) && Date().timeIntervalSince($0.value.at) <= Self.fallbackAge }
        guard let data = try? JSONEncoder().encode(entries), data.count <= 4 * 1_024 * 1_024 else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fetch(_ rail: DiscoveryRail, page: Int) async throws -> [Media] {
        if rail.path.hasPrefix("desktop-anime:") {
            let definitions = try DesktopAnimeRows.read()
            guard let row = definitions.rows.first(where: { $0.id == rail.id && rail.path == "desktop-anime:" + $0.key }) else { throw HarborError(code: "anime-row-identity") }
            if row.plans.count == 1 {
                // Preserve the already working direct MAL transport for supported rankings/seasons.
                if let direct = try? await MALPublicCatalog.page(rail, page: page, http: http) { return direct }
                try Task.checkCancellation()
            }
            var raw: [JSONValue] = []
            for plan in row.plans {
                let query = try plan.request(page: page)
                raw += try await fetchJikan(path: query.path, parameters: query.parameters)
            }
            return Self.unique(try definitions.filtered(raw, for: row).compactMap(Self.jikanMedia))
        }
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
            do { return try await MALPublicCatalog.page(rail, page: page, http: http) }
            catch is CancellationError { throw CancellationError() }
            catch {
                // Both transports read MAL. Retain Jikan when client-auth is unavailable.
                try Task.checkCancellation()
            }
            var params = rail.parameters; params["page"] = String(page); params["sfw"] = "true"
            let values = try await fetchJikan(path: String(rail.path.dropFirst(6)), parameters: params)
            return Self.unique(values.compactMap(Self.jikanMedia))
        }
        throw HarborError(code: "anime-catalog")
    }
    private func fetchJikan(path: String, parameters: [String: String]) async throws -> [JSONValue] {
        // Reserve before suspension so simultaneous genre/era rows respect provider limits.
        let delay = max(0, nextJikan.timeIntervalSinceNow)
        nextJikan = Date().addingTimeInterval(delay + 0.45)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        var url = URLComponents(string: "https://api.jikan.moe/v4/" + path)!
        var params = parameters; params["limit"] = "25"; params["sfw"] = "true"
        url.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let response = try await http.json(url.url!.absoluteString)
        guard case .array(let values) = response["data"], values.count <= 25 else { throw HarborError(code: "anime-response") }
        return values
    }

    func picks(records: [LibraryRecord]) async throws -> [Media] {
        let active = records.compactMap(\.media).filter { Self.isAnime($0.id) }
        let excluded = Set(active.map { Self.nameKey($0.name) })
        let excludedIDs = Set(active.map(\.id))
        let genres = Array(Set(active.flatMap { $0.genres ?? [] })).sorted()
        var candidates: [Media] = []
        for title in ["anime-airing", "anime-popular"] {
            try Task.checkCancellation()
            if let rail = Self.definitions().first(where: { $0.id == title }), let items = try? await page(rail, page: 1) { candidates.append(contentsOf: items) }
        }
        if candidates.isEmpty, let rail = Self.definitions().first(where: { $0.id == "anilist-trending" }) {
            // Keep the actual provider/rating rather than relabeling AniList
            // results as MAL during a Jikan outage.
            candidates = try await page(rail, page: 1)
        }
        try Task.checkCancellation()
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
        if id.hasPrefix("anilist:"), let number = Int64(id.dropFirst(8)) {
            // The metadata addon may not know a newly split AniList entry yet.
            // Keep its catalog identity and resolve only a provider-supplied alias.
            let query = "query($id:Int){Media(id:$id,type:ANIME){idMal}}"
            if let value = try? await HTTPClient().anilist(query: query, variables: .object(["id": .integer(number)])),
               let mal = value["Media"]["idMal"].integer, mal > 0 {
                return try await metadata(id: "mal:\(mal)", kind: kind)
            }
        }
        throw HarborError(code: "no-metadata")
    }
    private static func nameKey(_ name: String) -> String { name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en")) }
    private static func unique(_ items: [Media]) -> [Media] { var ids = Set<String>(); return items.filter { ids.insert($0.identity).inserted } }
    private static func plain(_ value: String?) -> String? { value?.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'") }
    static func anilistMedia(_ value: JSONValue) -> Media? {
        guard let id = value["id"].integer, let name = value["title"]["english"].string ?? value["title"]["userPreferred"].string ?? value["title"]["romaji"].string else { return nil }
        var media = Media(id: "anilist:\(id)", type: value["format"].string == "MOVIE" ? "movie" : "series", name: name)
        media.animeFormat = value["format"].string
        media.poster = value["coverImage"]["extraLarge"].string ?? value["coverImage"]["large"].string
        media.background = value["bannerImage"].string; media.description = plain(value["description"].string)
        media.releaseInfo = value["seasonYear"].integer.map(String.init); media.genres = value["genres"].array.compactMap(\.string)
        if let score = value["averageScore"].numericValue, score > 0 { media.imdbRating = String(format: "%.1f", score / 10); media.ratingSource = "AniList" }
        return media
    }
    private static func jikanMedia(_ value: JSONValue) -> Media? {
        guard let id = value["mal_id"].integer, let name = value["title_english"].string ?? value["title"].string else { return nil }
        var media = Media(id: "mal:\(id)", type: value["type"].string == "Movie" ? "movie" : "series", name: name)
        media.animeFormat = value["type"].string?.uppercased()
        media.poster = value["images"]["webp"]["large_image_url"].string ?? value["images"]["jpg"]["large_image_url"].string
        media.description = plain(value["synopsis"].string); media.releaseInfo = value["year"].integer.map(String.init)
        media.genres = value["genres"].array.compactMap { $0["name"].string }
        if let score = value["score"].numericValue, score > 0 { media.imdbRating = String(format: "%.1f", score); media.ratingSource = "MAL" }
        return media
    }
}
