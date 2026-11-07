import Foundation

/// Desktop's MyAnimeList lists (`lib/mal/lists.ts`) and their grouping, sorting and filters (`views/library/mal-tab.tsx`).
/// Pure value logic: the parser takes the decoded API page, so the tests need no network.
enum MALListStatus: String, CaseIterable, Hashable, Sendable {
    case watching, completed, onHold = "on_hold", dropped, planToWatch = "plan_to_watch"
}

/// Desktop's `MalAnime`, reduced to the fields the lists show.
struct MALListMedia: Equatable, Sendable {
    let id: Int
    let title: String
    let poster: String?
    let numEpisodes: Int?
    let mediaType: String?

    var isMovie: Bool { mediaType == "movie" }
    /// Desktop's `entryName` in the lists search: the title.
    var searchName: String { title }
}

struct MALListEntry: Equatable, Sendable {
    let status: MALListStatus
    let watched: Int
    let media: MALListMedia
}

/// Desktop's `MAL_RAIL_ORDER` in `views/library/mal-tab.tsx`, with its English titles.
enum MALListSection: CaseIterable, Hashable, Sendable {
    case watching, planning, completed, paused, dropped

    var statuses: [MALListStatus] {
        switch self {
        case .watching: return [.watching]
        case .planning: return [.planToWatch]
        case .completed: return [.completed]
        case .paused: return [.onHold]
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

/// Desktop's `TypeKey` in `views/library/shared.tsx`: all, movies (media_type movie) or shows (everything else).
enum MALListKind: CaseIterable, Hashable, Sendable {
    case all, movie, series

    var title: String {
        switch self {
        case .all: return "All"
        case .movie: return "Movies"
        case .series: return "Shows"
        }
    }

    func includes(_ media: MALListMedia) -> Bool {
        switch self {
        case .all: return true
        case .movie: return media.isMovie
        case .series: return !media.isMovie
        }
    }
}

struct MALListGroup: Equatable, Sendable {
    let section: MALListSection
    let entries: [MALListEntry]
}

enum MALLists {
    /// Desktop's paging in `fetchMalList` has no cap; this stops a server that keeps returning a next page.
    static let pageLimit = 50

    static func firstText(_ values: String?...) -> String? {
        for value in values {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return nil
    }

    // MARK: Parsing

    /// Desktop's `parseNode` for every node of one page. Nodes without a `my_list_status`, or with a status
    /// the lists do not know, are skipped.
    static func parsePage(_ data: JSONValue) -> [MALListEntry] {
        data["data"].array.compactMap { parseNode($0["node"]) }
    }

    static func parseNode(_ node: JSONValue) -> MALListEntry? {
        let listStatus = node["my_list_status"]
        guard let id = node["id"].integer, id > 0,
              let raw = listStatus["status"].string, let status = MALListStatus(rawValue: raw) else { return nil }
        let picture = node["main_picture"]
        let media = MALListMedia(
            id: id,
            title: node["title"].string ?? "",
            poster: firstText(picture["large"].string, picture["medium"].string),
            numEpisodes: node["num_episodes"].integer,
            mediaType: node["media_type"].string
        )
        return MALListEntry(status: status, watched: listStatus["num_episodes_watched"].integer ?? 0, media: media)
    }

    /// The `paging.next` address of a page, which Desktop follows until it is missing.
    static func nextPath(_ data: JSONValue) -> String? {
        firstText(data["paging"]["next"].string)
    }

    /// Desktop's `fetchMalList` dedupe: a title shows once, at the first place the API lists it.
    static func unique(_ entries: [MALListEntry]) -> [MALListEntry] {
        var seen = Set<Int>()
        return entries.filter { seen.insert($0.media.id).inserted }
    }

    // MARK: Lists

    /// Desktop's `mal-tab.tsx` visible list: the type filter and the title search, grouped in `MAL_RAIL_ORDER`.
    /// Within a group the entries keep the order the API returned them in.
    static func groups(_ entries: [MALListEntry], kind: MALListKind, query: String) -> [MALListGroup] {
        let visible = entries.filter { matches($0.media, kind: kind, query: query) }
        return MALListSection.allCases.compactMap { (section: MALListSection) -> MALListGroup? in
            let items = visible.filter { section.statuses.contains($0.status) }
            return items.isEmpty ? nil : MALListGroup(section: section, entries: items)
        }
    }

    static func matches(_ media: MALListMedia, kind: MALListKind, query: String) -> Bool {
        guard kind.includes(media) else { return false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return needle.isEmpty || media.searchName.lowercased().contains(needle)
    }

    /// Count shown on a type pill: the entries that pill would show, whatever the other pills select.
    static func count(_ entries: [MALListEntry], kind: MALListKind, query: String) -> Int {
        entries.filter { matches($0.media, kind: kind, query: query) }.count
    }

    /// Desktop shows `watched / total` on each card. MyAnimeList sends `0` for an unknown total, so a zero total is
    /// left out here, where Desktop would print "5 / 0".
    static func progressLabel(_ entry: MALListEntry) -> String {
        guard let total = entry.media.numEpisodes, total > 0 else { return String(entry.watched) }
        return "\(entry.watched) / \(total)"
    }

    /// Desktop's `malAnimeToMeta`: the Harbor title that opens the detail screen. Nil when the title is blank.
    static func harborMedia(_ item: MALListMedia) -> Media? {
        guard let title = firstText(item.title) else { return nil }
        var media = Media(id: "mal:\(item.id)", type: item.isMovie ? "movie" : "series", name: title)
        media.poster = item.poster
        return media
    }
}

/// The MyAnimeList list request of this screen, copied from Desktop's `fetchMalList`, with fewer fields.
enum MALListsService {
    static let listPath = "/users/@me/animelist?fields=my_list_status,num_episodes,main_picture,media_type&nsfw=true&limit=1000"

    /// Follows `paging.next` until the list ends. A 401 refreshes the token once and repeats the page, as `MALSync` does.
    static func fetchAll(token: String, client: MALClient,
                         refresh: @escaping @MainActor @Sendable () async -> String?) async throws -> [MALListEntry] {
        var entries: [MALListEntry] = []
        var path: String? = listPath
        var current = token
        var pages = 0
        while let next = path, pages < MALLists.pageLimit {
            pages += 1
            var data: JSONValue = .null
            do {
                data = try await client.request(next, token: current)
            } catch let error as MALAPIError where error.status == 401 {
                guard let renewed = await refresh() else { throw error }
                current = renewed
                data = try await client.request(next, token: current)
            }
            entries += MALLists.parsePage(data)
            let following = MALLists.nextPath(data)
            // A server that repeats the same next address would loop forever: stop at the first repeat.
            path = following == next ? nil : following
        }
        return MALLists.unique(entries)
    }
}
