import Foundation

enum SimklListStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case watching, plantowatch, completed, hold, dropped
    var id: String { rawValue }
    var label: String {
        switch self { case .watching: "Watching"; case .plantowatch: "Plan to Watch"; case .completed: "Completed"; case .hold: "On Hold"; case .dropped: "Dropped" }
    }
    static func options(for kind: SimklMediaKind) -> [Self] { kind == .movie ? [.plantowatch, .completed, .dropped] : allCases }
}
enum SimklMediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case movie, show, anime
    var id: String { rawValue }
    var bucket: String { self == .movie ? "movies" : self == .show ? "shows" : "anime" }
    var label: String { self == .movie ? "Movies" : self == .show ? "Shows" : "Anime" }
}
struct SimklIdentifiers: Codable, Equatable, Sendable {
    let values: [String: JSONValue]
    init(_ value: JSONValue) {
        var ids: [String: JSONValue] = [:]
        for key in ["simkl", "tmdb", "tvdb", "mal", "kitsu", "anilist", "anidb"] {
            if let raw = value[key].textValue, let number = Int64(raw), number > 0 { ids[key] = .integer(number) }
        }
        if let imdb = value["imdb"].string, imdb.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { ids["imdb"] = .string(imdb) }
        values = ids
    }
    var json: JSONValue { .object(values) }
    func aliases(kind: SimklMediaKind) -> [String] {
        var keys: [String] = []
        if let imdb = values["imdb"]?.string { keys.append(imdb) }
        if let tmdb = values["tmdb"]?.textValue { keys.append("tmdb:\(kind == .movie ? "movie" : "tv"):\(tmdb)") }
        for key in ["mal", "kitsu", "anilist", "anidb", "simkl"] { if let number = values[key]?.textValue { keys.append(key + ":" + number) } }
        return keys
    }
}
struct SimklTarget: Equatable, Sendable {
    let kind: SimklMediaKind
    let ids: SimklIdentifiers
    var listBucket: String { kind == .movie ? "movies" : "shows" }
    var ratingBucket: String { kind.bucket }
    static func direct(_ media: Media) -> Self? {
        let parts = media.id.split(separator: ":").map(String.init)
        let kind: SimklMediaKind = media.type == "movie" ? .movie : .show
        if let imdb = parts.first, imdb.range(of: "^tt[0-9]+$", options: .regularExpression) != nil {
            return Self(kind: kind, ids: .init(.object(["imdb": .string(imdb)])))
        }
        if parts.count >= 3, parts[0] == "tmdb", ["movie", "tv"].contains(parts[1]), let id = Int64(parts[2]), id > 0 {
            return Self(kind: kind, ids: .init(.object(["tmdb": .integer(id)])))
        }
        if parts.count == 2, ["mal", "simkl"].contains(parts[0]), let id = Int64(parts[1]), id > 0 {
            return Self(kind: parts[0] == "simkl" && kind != .movie ? .anime : kind, ids: .init(.object([parts[0]: .integer(id)])))
        }
        return nil
    }
    static func resolve(_ media: Media, mapping: @Sendable (String) async throws -> JSONValue = { try await AnimeFranchiseService.shared.response(.mapping($0)) }) async throws -> Self? {
        if let target = direct(media) { return target }
        guard let identity = AnimePublicIdentity(media.id), ["kitsu", "anilist", "anidb"].contains(identity.provider) else { return nil }
        let mapped = try await mapping(media.id)
        guard mapped["mappings"][identity.mappingKey].textValue == identity.number,
              let mal = mapped["mappings"]["mal_id"].integer, mal > 0 else { return nil }
        return Self(kind: media.type == "movie" ? .movie : .show, ids: .init(.object(["mal": .integer(Int64(mal))])))
    }
}
struct SimklListItem: Codable, Identifiable, Equatable, Sendable {
    let kind: SimklMediaKind
    let ids: SimklIdentifiers
    var title: String
    var year: Int?
    var status: SimklListStatus
    var userRating: Int?
    var addedAt: String?
    var watchedAt: String?
    var watchedEpisodes: Set<String>
    var poster: String?
    var id: String { kind.rawValue + ":" + (ids.values["simkl"]?.textValue ?? ids.aliases(kind: kind).first ?? "") }
    var target: SimklTarget { .init(kind: kind, ids: ids) }
    var media: Media {
        var item = Media(id: ids.aliases(kind: kind).first ?? id, type: kind == .movie ? "movie" : "series", name: title.isEmpty ? "Unknown Title" : title)
        item.poster = poster; item.releaseInfo = year.map(String.init); return item
    }
    static func parse(_ raw: JSONValue, kind: SimklMediaKind, previous: Self? = nil) -> Self? {
        var node = raw[kind == .movie ? "movie" : "show"]
        if kind == .anime { node = [raw["anime"], raw["show"], raw["movie"]].first(where: { !$0.objectValue.isEmpty }) ?? .null }
        let ids = SimklIdentifiers(node["ids"])
        guard ids.values["simkl"] != nil else { return nil }
        var watched = Set<String>()
        for season in raw["seasons"].array {
            guard let s = season["number"].integer, s >= 0 else { continue }
            for episode in season["episodes"].array {
                if let n = episode["number"].integer, n > 0, let timestamp = episode["watched_at"].string, !timestamp.isEmpty { watched.insert("\(s):\(n)") }
            }
        }
        let rating = raw["user_rating"].integer ?? raw["rating"].integer
        var poster = previous?.poster
        if let image = node["poster"].string, image.range(of: "^[A-Za-z0-9_-]{1,256}$", options: .regularExpression) != nil { poster = "https://simkl.in/posters/\(image)_m.jpg" }
        return Self(kind: kind, ids: ids, title: node["title"].string ?? previous?.title ?? "", year: node["year"].integer ?? previous?.year,
            status: raw["status"].string.flatMap(SimklListStatus.init(rawValue:)) ?? .plantowatch,
            userRating: rating.flatMap { (1...10).contains($0) ? $0 : nil } ?? previous?.userRating,
            addedAt: raw["added_to_watchlist_at"].string ?? previous?.addedAt,
            watchedAt: raw["last_watched_at"].string ?? previous?.watchedAt,
            watchedEpisodes: raw["seasons"] == .null ? previous?.watchedEpisodes ?? [] : watched, poster: poster)
    }
}
struct SimklLibrarySnapshot: Codable, Equatable, Sendable {
    var items: [String: SimklListItem] = [:]
    var ratings: [String: Int] = [:]
    var lastSync: String?
    var activities: JSONValue = .null
    mutating func merge(_ response: JSONValue, kind: SimklMediaKind) {
        for raw in response[kind.bucket].array {
            guard let parsed = SimklListItem.parse(raw, kind: kind) else { continue }
            let previous = items[parsed.id] ?? item(for: parsed.target)
            if let item = SimklListItem.parse(raw, kind: kind, previous: previous) {
                if let previous, previous.id != item.id { items[previous.id] = nil }
                items[item.id] = item
            }
        }
    }
    mutating func mergeRatings(_ response: JSONValue) {
        ratings = [:]
        for key in Array(items.keys) { items[key]?.userRating = nil }
        for kind in SimklMediaKind.allCases {
            for raw in response[kind.bucket].array {
                guard let parsed = SimklListItem.parse(raw, kind: kind) else { continue }
                setRating(raw["rating"].integer.flatMap { (1...10).contains($0) ? $0 : nil }, target: parsed.target)
            }
        }
    }
    func rating(for target: SimklTarget) -> Int? {
        if let rating = item(for: target)?.userRating { return rating }
        let prefix = target.kind == .movie ? "movie|" : "series|"
        return target.ids.aliases(kind: target.kind).compactMap { ratings[prefix + $0] }.first
    }
    mutating func setRating(_ rating: Int?, target: SimklTarget) {
        let prefix = target.kind == .movie ? "movie|" : "series|"
        var aliases = Set(target.ids.aliases(kind: target.kind))
        if var item = item(for: target) {
            aliases.formUnion(item.ids.aliases(kind: item.kind)); item.userRating = rating; items[item.id] = item
        }
        for alias in aliases { ratings[prefix + alias] = rating }
    }
    func item(for target: SimklTarget) -> SimklListItem? {
        let candidates = items.values.filter {
            guard ($0.kind == .movie) == (target.kind == .movie) else { return false }
            if let wanted = target.ids.values["simkl"], let actual = $0.ids.values["simkl"], wanted != actual { return false }
            return true
        }.sorted { $0.id < $1.id }
        for key in ["simkl", "mal", "kitsu", "anilist", "anidb", "tmdb", "tvdb", "imdb"] {
            if let value = target.ids.values[key], let item = candidates.first(where: { $0.ids.values[key] == value }) { return item }
        }
        return nil
    }
    static func removalsChanged(_ current: JSONValue, since: String?) -> Bool {
        guard let since else { return false }
        return [current["movies"], current["shows"], current["tv_shows"], current["anime"]].contains { ($0["removed_from_list"].string ?? "") > since }
    }
}
