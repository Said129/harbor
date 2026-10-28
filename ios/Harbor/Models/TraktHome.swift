import Foundation

enum TraktHomeEndpoint: Sendable {
    case recommendations(TraktLibraryTarget.Kind), upcoming(String)
    var path: String {
        switch self {
        case .recommendations(let kind): "/recommendations/\(kind == .movie ? "movies" : "shows")?limit=40&ignore_collected=true"
        case .upcoming(let day): "/calendars/my/shows/\(day)/14"
        }
    }
    var valid: Bool {
        switch self {
        case .recommendations: true
        case .upcoming(let day): day.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
        }
    }
    static func utcDay(_ date: Date) -> String { String(ISO8601DateFormatter().string(from: date).prefix(10)) }
}

/// Raw, ordered Trakt items are retained for Desktop's 24-item View All pager.
/// Only upcoming shows are deduplicated; personalized rows are not deduplicated
/// against recommendations, custom lists, or the public discovery catalogs.
struct TraktHomeFeed: Sendable {
    static let pageSize = 24
    let id: String
    let title: String
    let kind: String
    let items: [TraktLibraryItem]
    func slice(_ page: Int) -> [TraktLibraryItem] {
        guard page > 0, page <= (items.count + Self.pageSize - 1) / Self.pageSize else { return [] }
        let start = (page - 1) * Self.pageSize
        return Array(items[start..<min(start + Self.pageSize, items.count)])
    }
    static func build(watchlist: JSONValue, upcoming: JSONValue, movies: JSONValue, shows: JSONValue) throws -> [Self] {
        let watchlist = try TraktLibraryItem.watchlist(watchlist)
        var seen = Set<String>()
        let upcoming = try rows(upcoming).compactMap { row -> TraktLibraryItem? in
            guard case .object = row["show"] else { return nil }
            let item = item(row["show"], type: .show)
            let key = item.ids.json["imdb"].string ?? item.ids.json["tmdb"].integer.map { "tmdb:\($0)" }
            guard let key, seen.insert(key).inserted else { return nil }; return item
        }
        return [
            .init(id: "trakt-watchlist", title: "Your Trakt Watchlist", kind: watchlist.first?.type == .show ? "series" : "movie", items: watchlist),
            .init(id: "trakt-upcoming", title: "Up Next on Trakt", kind: "series", items: upcoming),
            .init(id: "trakt-recs-movies", title: "Trakt Recommends: Movies", kind: "movie", items: try rows(movies).map { item($0, type: .movie) }),
            .init(id: "trakt-recs-shows", title: "Trakt Recommends: Series", kind: "series", items: try rows(shows).map { item($0, type: .show) })
        ]
    }
    private static func rows(_ value: JSONValue) throws -> [JSONValue] {
        guard case .array(let rows) = value, rows.count <= 20_000 else { throw HarborError(code: "trakt-response") }; return rows
    }
    private static func item(_ value: JSONValue, type: TraktLibraryTarget.Kind) -> TraktLibraryItem {
        .init(type: type, title: value["title"].string ?? "", year: value["year"].integer, ids: .init(value["ids"]))
    }
}
