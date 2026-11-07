import Foundation

/// Desktop's AniList lists (`lib/anilist/lists.ts`), their grouping and filters (`views/library/anilist-tab.tsx`),
/// and the recommended rail (`lib/anilist/recommendations.ts`, `lib/use-anilist-anime-rails.ts`).
/// Pure value logic: the parsers take the GraphQL `data` object, so the tests need no network.
enum AniListListStatus: String, CaseIterable, Hashable, Sendable {
    case current = "CURRENT", planning = "PLANNING", completed = "COMPLETED", dropped = "DROPPED", paused = "PAUSED", repeating = "REPEATING"
}

/// Desktop's `AnilistMedia`, reduced to the fields the lists and the recommended rail use.
struct AniListListMedia: Equatable, Sendable {
    let id: Int
    let idMal: Int?
    let romaji: String?
    let english: String?
    let userPreferred: String?
    let format: String?
    let episodes: Int?
    let poster: String?
    let background: String?
    let description: String?
    let seasonYear: Int?
    let averageScore: Int?

    var isMovie: Bool { format == "MOVIE" }
    /// Desktop's `entryName` in the lists search: userPreferred, then english, then romaji.
    var searchName: String { AniListLists.firstText(userPreferred, english, romaji) ?? "" }
    /// Desktop's `anilistMediaToMeta` title: english, then userPreferred, then romaji.
    var metaTitle: String? { AniListLists.firstText(english, userPreferred, romaji) }
    /// Desktop's `anilistMediaToMeta` id: `mal:N` when MyAnimeList knows the title, otherwise `anilist:N`.
    var metaID: String { idMal.map { "mal:\($0)" } ?? "anilist:\(id)" }
}

struct AniListListEntry: Equatable, Sendable {
    let status: AniListListStatus
    let progress: Int
    let media: AniListListMedia
}

/// Desktop's `RAIL_ORDER` (`lib/use-anilist-anime-rails.ts`) with its English titles.
enum AniListListSection: CaseIterable, Hashable, Sendable {
    case watching, planning, completed, paused, dropped

    var statuses: [AniListListStatus] {
        switch self {
        case .watching: return [.current, .repeating]
        case .planning: return [.planning]
        case .completed: return [.completed]
        case .paused: return [.paused]
        case .dropped: return [.dropped]
        }
    }

    var title: String {
        switch self {
        case .watching: return "Watching"
        case .planning: return "Plan to Watch"
        case .completed: return "Completed"
        case .paused: return "On Hold"
        case .dropped: return "Dropped"
        }
    }
}

/// Desktop's `TypeKey` in `views/library/shared.tsx`: all, movies (format MOVIE) or shows (everything else).
enum AniListListKind: CaseIterable, Hashable, Sendable {
    case all, movie, series

    var title: String {
        switch self {
        case .all: return "All"
        case .movie: return "Movies"
        case .series: return "Shows"
        }
    }

    func includes(_ media: AniListListMedia) -> Bool {
        switch self {
        case .all: return true
        case .movie: return media.isMovie
        case .series: return !media.isMovie
        }
    }
}

struct AniListListGroup: Equatable, Sendable {
    let section: AniListListSection
    let entries: [AniListListEntry]
}

enum AniListLists {
    /// Desktop's `SEED_STATUSES`: completed titles first, then the ones being watched.
    static let seedStatuses: [AniListListStatus] = [.completed, .current, .repeating]
    /// Desktop sends at most 40 seed ids (`fetchAnilistRecommendations`).
    static let seedLimit = 40
    /// Desktop's `MIN_RECS`: the rail appears only with at least this many titles.
    static let recommendationMinimum = 4
    /// Desktop's `recs.slice(0, 40)`.
    static let recommendationLimit = 40

    static func firstText(_ values: String?...) -> String? {
        for value in values {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }

    // MARK: Lists

    /// Desktop's `buildGroups`: custom lists and groups without a known status are left out, a title shows once
    /// (the first group that has it wins), and statuses keep the order in which they first appear.
    static func parseCollection(_ data: JSONValue) -> [AniListListEntry] {
        var order: [AniListListStatus] = []
        var buckets: [AniListListStatus: [AniListListEntry]] = [:]
        var seen = Set<Int>()
        for group in data["MediaListCollection"]["lists"].array {
            guard group["isCustomList"] != .bool(true),
                  let groupStatus = AniListListStatus(rawValue: group["status"].string ?? "") else { continue }
            if buckets[groupStatus] == nil {
                order.append(groupStatus)
                buckets[groupStatus] = []
            }
            for raw in group["entries"].array {
                guard let media = parseMedia(raw["media"]), seen.insert(media.id).inserted else { continue }
                let status = AniListListStatus(rawValue: raw["status"].string ?? "") ?? groupStatus
                let entry = AniListListEntry(status: status, progress: raw["progress"].integer ?? 0, media: media)
                buckets[groupStatus, default: []].append(entry)
            }
        }
        return order.flatMap { buckets[$0] ?? [] }
    }

    static func parseMedia(_ value: JSONValue) -> AniListListMedia? {
        guard let id = value["id"].integer, id > 0 else { return nil }
        let title = value["title"]
        let cover = value["coverImage"]
        return AniListListMedia(
            id: id,
            idMal: value["idMal"].integer,
            romaji: title["romaji"].string,
            english: title["english"].string,
            userPreferred: title["userPreferred"].string,
            format: value["format"].string,
            episodes: value["episodes"].integer,
            poster: firstText(cover["large"].string, cover["extraLarge"].string),
            background: value["bannerImage"].string,
            description: value["description"].string.map { plainText($0) },
            seasonYear: value["seasonYear"].integer,
            averageScore: value["averageScore"].integer
        )
    }

    /// Desktop's `stripHtml` (`lib/anilist/to-meta.ts`).
    static func plainText(_ html: String) -> String {
        let lineBreaks = html.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: [.regularExpression, .caseInsensitive])
        let stripped = lineBreaks.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Desktop's `anilist-tab.tsx` visible list: the type filter and the title search, in the order of `parseCollection`.
    static func groups(_ entries: [AniListListEntry], kind: AniListListKind, query: String) -> [AniListListGroup] {
        let visible = entries.filter { matches($0.media, kind: kind, query: query) }
        return AniListListSection.allCases.compactMap { (section: AniListListSection) -> AniListListGroup? in
            let items = visible.filter { section.statuses.contains($0.status) }
            return items.isEmpty ? nil : AniListListGroup(section: section, entries: items)
        }
    }

    static func matches(_ media: AniListListMedia, kind: AniListListKind, query: String) -> Bool {
        guard kind.includes(media) else { return false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return needle.isEmpty || media.searchName.lowercased().contains(needle)
    }

    static func count(_ entries: [AniListListEntry], kind: AniListListKind, query: String) -> Int {
        entries.filter { matches($0.media, kind: kind, query: query) }.count
    }

    /// Desktop's `progress / episodes` on each card; the total is shown only when AniList knows it.
    static func progressLabel(_ entry: AniListListEntry) -> String {
        guard let total = entry.media.episodes else { return String(entry.progress) }
        return "\(entry.progress) / \(total)"
    }

    /// Desktop's `anilistMediaToMeta`, as the Harbor title that opens the detail screen. Nil when AniList gives no title.
    static func harborMedia(_ item: AniListListMedia) -> Media? {
        guard let title = item.metaTitle else { return nil }
        var media = Media(id: item.metaID, type: item.isMovie ? "movie" : "series", name: title)
        media.poster = item.poster
        media.background = item.background
        media.description = item.description
        media.releaseInfo = item.seasonYear.map { String($0) }
        if let score = item.averageScore {
            media.imdbRating = String(format: "%.1f", Double(score) / 10)
            media.ratingSource = "AniList"
        }
        media.animeFormat = item.format
        return media
    }

    // MARK: Recommendations

    /// Desktop's `use-anilist-anime-rails.ts` seeds: the first 40 ids of completed, then watching, then rewatching titles.
    static func recommendationSeeds(_ entries: [AniListListEntry]) -> [Int] {
        var ids: [Int] = []
        for status in seedStatuses {
            ids += entries.filter { $0.status == status }.map { $0.media.id }
        }
        return Array(ids.prefix(seedLimit))
    }

    /// Desktop excludes every title already on the lists, whatever its status.
    static func excludedIDs(_ entries: [AniListListEntry]) -> Set<Int> {
        Set(entries.map { $0.media.id })
    }

    /// Desktop's `fetchAnilistRecommendations` ranking: each title weighs `max(0, rating) + 1` for every seed that
    /// recommends it; the heavier total comes first and ties keep their first-seen order.
    static func rankedRecommendations(_ data: JSONValue, excluding excluded: Set<Int>) -> [AniListListMedia] {
        var order: [Int] = []
        var weights: [Int: Int] = [:]
        var media: [Int: AniListListMedia] = [:]
        for source in data["Page"]["media"].array {
            for node in source["recommendations"]["nodes"].array {
                guard let rec = parseMedia(node["mediaRecommendation"]), !excluded.contains(rec.id) else { continue }
                let weight = max(0, node["rating"].integer ?? 0) + 1
                if let previous = weights[rec.id] {
                    weights[rec.id] = previous + weight
                } else {
                    order.append(rec.id)
                    weights[rec.id] = weight
                    media[rec.id] = rec
                }
            }
        }
        let ranked = order.enumerated().sorted { (lhs, rhs) -> Bool in
            let left = weights[lhs.element] ?? 0
            let right = weights[rhs.element] ?? 0
            if left != right { return left > right }
            return lhs.offset < rhs.offset
        }
        return ranked.compactMap { media[$0.element] }
    }

    /// Desktop's `buildAnimeRowMetas` plus the rail rule: one title per franchise with cleaned names, no repeated ids,
    /// and nothing at all when fewer than `recommendationMinimum` titles remain.
    static func recommendationRail(_ ranked: [AniListListMedia]) -> [Media] {
        var seen = Set<String>()
        var out: [Media] = []
        for item in AniListFranchise.dedupe(ranked) {
            guard var media = harborMedia(item) else { continue }
            media.name = AniListFranchise.cleanShowName(media.name)
            guard seen.insert(media.id).inserted else { continue }
            out.append(media)
        }
        guard out.count >= recommendationMinimum else { return [] }
        return Array(out.prefix(recommendationLimit))
    }
}

/// Desktop's `lib/anilist/franchise-dedupe.ts`: one representative per franchise, by format rank and then year.
enum AniListFranchise {
    private static let formatRank: [String: Int] = ["TV": 0, "TV_SHORT": 1, "ONA": 2, "OVA": 3, "MOVIE": 4]
    private static let skipFormats: Set<String> = ["MUSIC", "SPECIAL"]

    static func dedupe(_ list: [AniListListMedia]) -> [AniListListMedia] {
        var order: [String] = []
        var groups: [String: [AniListListMedia]] = [:]
        for item in list {
            if let format = item.format, skipFormats.contains(format) { continue }
            let key = franchiseKey(item)
            guard !key.isEmpty else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.compactMap { (key: String) -> AniListListMedia? in
            guard let items = groups[key] else { return nil }
            return representative(items)
        }
    }

    static func franchiseKey(_ item: AniListListMedia) -> String {
        let raw = AniListLists.firstText(item.romaji, item.english, item.userPreferred) ?? ""
        let base = baseTitle(raw)
        return base.isEmpty ? raw.lowercased() : base
    }

    static func baseTitle(_ raw: String) -> String {
        var text = raw.lowercased()
        let steps: [(String, String)] = [
            (":\\s+.*$", " "),
            ("\\b(season|cour|part)\\b.*$", " "),
            ("\\b\\d+(st|nd|rd|th)\\b.*$", " "),
            ("\\bfinal(\\s+season)?\\b.*$", " "),
            ("\\b(the\\s+)?movie\\b.*$", " "),
            ("\\s+(ii|iii|iv|v|vi|vii)\\s*$", " "),
            ("[°'.]+", " "),
            ("[^a-z0-9]+", " "),
            ("\\s+", " ")
        ]
        for (pattern, replacement) in steps {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Desktop's `cleanShowName`: drops season, cour and part suffixes from a title.
    static func cleanShowName(_ name: String) -> String {
        var cut = name
        let patterns = [
            "\\s+(the\\s+)?final\\s+season\\b.*$",
            "\\s+(season|cour)\\s+\\d+.*$",
            "\\s+\\d+(st|nd|rd|th)\\s+season\\b.*$",
            "\\s+part\\s+\\d+\\b.*$"
        ]
        for pattern in patterns {
            cut = cut.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        let trimmed = cut.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? name : trimmed
    }

    private static func representative(_ items: [AniListListMedia]) -> AniListListMedia? {
        let ranked = items.enumerated().sorted { (lhs, rhs) -> Bool in
            let leftRank = formatRank[lhs.element.format ?? ""] ?? 5
            let rightRank = formatRank[rhs.element.format ?? ""] ?? 5
            if leftRank != rightRank { return leftRank < rightRank }
            let leftYear = lhs.element.seasonYear ?? 9999
            let rightYear = rhs.element.seasonYear ?? 9999
            if leftYear != rightYear { return leftYear < rightYear }
            return lhs.offset < rhs.offset
        }
        return ranked.first?.element
    }
}

/// The two AniList requests of this screen, copied from Desktop's `COLLECTION_QUERY` and `RECS_QUERY`.
enum AniListListsService {
    static let collectionQuery = "query ($userId: Int) { MediaListCollection(userId: $userId, type: ANIME) { lists { status isCustomList entries { id status progress score media { id idMal title { romaji english native userPreferred } coverImage { extraLarge large medium } bannerImage format episodes averageScore seasonYear } } } } }"

    static let recommendationsQuery = "query ($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids, type: ANIME) { id recommendations(sort: RATING_DESC, perPage: 6) { nodes { rating mediaRecommendation { id idMal title { romaji english native userPreferred } coverImage { extraLarge large medium } bannerImage format episodes averageScore seasonYear } } } } } }"

    static func collection(userID: Int, token: String, client: AniListClient) async throws -> [AniListListEntry] {
        let data = try await client.request(collectionQuery, variables: ["userId": .integer(Int64(userID))], token: token)
        return AniListLists.parseCollection(data)
    }

    /// Recommendations are sent without the viewer's token, as Desktop's `skipAuth` does.
    static func recommendations(seeds: [Int], excluded: Set<Int>, client: AniListClient) async throws -> [Media] {
        let ids: [JSONValue] = seeds.prefix(AniListLists.seedLimit).map { JSONValue.integer(Int64($0)) }
        guard !ids.isEmpty else { return [] }
        let data = try await client.request(recommendationsQuery, variables: ["ids": .array(ids)], token: nil)
        return AniListLists.recommendationRail(AniListLists.rankedRecommendations(data, excluding: excluded))
    }
}
