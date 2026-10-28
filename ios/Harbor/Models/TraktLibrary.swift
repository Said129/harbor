import Foundation

struct TraktLibraryTarget: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case movie, show }
    let kind: Kind
    let ids: TrackerShowIDs
    init(kind: Kind, ids: TrackerShowIDs) { self.kind = kind; self.ids = ids }
    init?(_ media: Media) {
        guard let resolved = TraktWatchTarget.resolve(.init(mediaID: media.id)), !resolved.ids.json.objectValue.isEmpty else { return nil }
        self.init(kind: media.type == "movie" ? .movie : .show, ids: resolved.ids)
    }
    var body: JSONValue { .object([kind == .movie ? "movies" : "shows": .array([.object(["ids": ids.json])])]) }
    func matches(_ item: TraktLibraryItem) -> Bool {
        kind == item.type && ids.json.objectValue.contains { key, value in item.ids.json[key] == value }
    }
}

struct TraktLibraryItem: Codable, Equatable, Sendable {
    let type: TraktLibraryTarget.Kind
    let title: String
    let year: Int?
    let ids: TrackerShowIDs
    var contextDate: String?
    var historyID: Int?
    var season: Int?
    var episode: Int?
    var target: TraktLibraryTarget { .init(kind: type, ids: ids) }
    var media: Media? {
        let id: String
        if let tmdb = ids.json["tmdb"].integer { id = "tmdb:\(type == .movie ? "movie" : "tv"):\(tmdb)" }
        else if let imdb = ids.json["imdb"].string { id = imdb }
        else { return nil }
        return media(id: id)
    }
    var importMedia: Media? {
        if let imdb = ids.json["imdb"].string { return media(id: imdb) }; return media
    }
    private func media(id: String) -> Media {
        var value = Media(id: id, type: type == .movie ? "movie" : "series", name: title)
        value.releaseInfo = year.map(String.init); value.imdbID = ids.json["imdb"].string; return value
    }
    func record(history: Bool = false) -> LibraryRecord? {
        let media: Media?
        // Desktop historyItemsToDated deduplicates by IMDb, while its watchlist
        // cards prefer TMDB. Keep both routes rather than merging identities.
        if history { media = ids.json["imdb"].string.map { self.media(id: $0) } }
        else { media = self.media }
        guard let media else { return nil }
        var fields = LibraryRecord.new(media)
        fields["external"] = .string("trakt-library")
        if !history { fields["releaseInfo"] = year.map { .string(String($0)) } ?? .null }
        fields["imdb_id"] = ids.json["imdb"]
        if let contextDate { fields["_ctime"] = .string(contextDate); fields["_mtime"] = .string(contextDate) }
        else { fields["_ctime"] = .integer(0); fields["_mtime"] = .integer(0) }
        return .init(raw: .object(fields))
    }
    static func watchlist(_ value: JSONValue) throws -> [Self] {
        guard case .array(let rows) = value, rows.count <= 20_000 else { throw HarborError(code: "trakt-response") }
        return rows.compactMap { row in
            guard let type = row["type"].string.flatMap(TraktLibraryTarget.Kind.init(rawValue:)), case .object = row[type.rawValue] else { return nil }
            let node = row[type.rawValue]
            return .init(type: type, title: node["title"].string ?? "", year: node["year"].integer, ids: .init(node["ids"]), contextDate: row["listed_at"].string)
        }
    }
    static func history(_ value: JSONValue) throws -> [Self] {
        guard case .array(let rows) = value, rows.count <= 20_000 else { throw HarborError(code: "trakt-response") }
        return rows.compactMap { row in
            let type: TraktLibraryTarget.Kind
            if row["type"].string == "movie", case .object = row["movie"] { type = .movie }
            else if row["type"].string == "episode", case .object = row["show"] { type = .show }
            else { return nil }
            let node = row[type.rawValue]
            return .init(type: type, title: node["title"].string ?? "", year: node["year"].integer, ids: .init(node["ids"]),
                contextDate: row["watched_at"].string, historyID: row["id"].integer, season: row["episode"]["season"].integer, episode: row["episode"]["number"].integer)
        }
    }
}

struct TraktLibrarySnapshot: Codable, Equatable, Sendable {
    var watchlist: [TraktLibraryItem] = []
    var history: [TraktLibraryItem] = []
    var watchlistRecords: [LibraryRecord] { watchlist.compactMap { $0.record() } }
    var historyRecords: [LibraryRecord] {
        var seen = Set<String>()
        return history.compactMap { item in guard let record = item.record(history: true), seen.insert(record.id).inserted else { return nil }; return record }
    }
}

struct TraktWatchlistExportPlan: Equatable, Sendable {
    var movies: [JSONValue] = []
    var shows: [JSONValue] = []
    var skippedAnime = 0
    var total = 0
    var exportable: Int { movies.count + shows.count }
    init(_ sources: [JSONValue]) {
        var seen = Set<String>()
        for source in sources {
            guard source["removed"] != .bool(true), source["temp"] != .bool(true), let id = source["id"].string, !id.isEmpty, seen.insert(id).inserted else { continue }
            total += 1
            if ["kitsu:", "mal:", "anilist:", "anidb:"].contains(where: { id.hasPrefix($0) }) { skippedAnime += 1; continue }
            let ids: JSONValue
            if id.range(of: "^tt[0-9]+$", options: .regularExpression) != nil { ids = .object(["imdb": .string(id)]) }
            else {
                let parts = id.split(separator: ":").map(String.init)
                guard parts.count >= 3, parts[0] == "tmdb", let id = Int64(parts[2]), id > 0 else { continue }
                ids = .object(["tmdb": .integer(id)])
            }
            let item = JSONValue.object(["ids": ids])
            if ["series", "tv", "channel"].contains(source["type"].string ?? "") { shows.append(item) } else { movies.append(item) }
        }
    }
    var chunks: [JSONValue] {
        [("movies", movies), ("shows", shows)].flatMap { key, items in
            stride(from: 0, to: items.count, by: 100).map { offset -> JSONValue in .object([key: .array(Array(items[offset..<min(items.count, offset + 100)]))]) }
        }
    }
}

struct TraktWatchlistExportResult: Equatable, Sendable {
    let exportable: Int
    let synced: Int
    let skippedAnime: Int
    var unmatched: Int { max(0, exportable - synced) }
    static func confirmed(_ value: JSONValue) -> Int {
        ["added", "existing"].reduce(0) { sum, group in sum + (value[group]["movies"].integer ?? 0) + (value[group]["shows"].integer ?? 0) }
    }
}

enum TraktLibraryEndpoint: Sendable {
    case watchlist, history, watchedKeys, export(JSONValue), change(TraktLibraryTarget, Bool)
    var path: String {
        switch self {
        case .watchlist: "/sync/watchlist?sort_by=added&sort_how=desc"
        case .history: "/sync/history?limit=200"
        case .watchedKeys: "/sync/history?limit=1000"
        case .export: "/sync/watchlist"
        case .change(_, let saved): saved ? "/sync/watchlist" : "/sync/watchlist/remove"
        }
    }
    var body: JSONValue? { switch self { case .watchlist, .history, .watchedKeys: nil; case .export(let body): body; case .change(let target, _): target.body } }
}
