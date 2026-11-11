import Foundation

/// Catalog definitions and presentation order from Desktop 0.9.132 Shows.
enum ShowsCatalog {
    static let fallbackGenres = ["Drama", "Comedy", "Crime", "Sci-Fi", "Thriller", "Mystery", "Action",
                                 "Animation", "Adventure", "Fantasy", "Documentary", "Romance", "Horror"]
    // Keep the previous iOS identity for each fallback genre when its Desktop position changes.
    private static let savedFallbackGenres = ["Action", "Drama", "Comedy", "Sci-Fi", "Thriller", "Horror", "Romance",
                                              "Animation", "Adventure", "Crime", "Mystery", "Fantasy", "Documentary"]

    static func fallbackKey(for genre: String?) -> String {
        guard let genre else { return "native-series-0" }
        return "native-series-" + (savedFallbackGenres.firstIndex(of: genre).map { String($0 + 1) } ?? genre)
    }

    static func definitions(now: Date) -> [DiscoveryRail] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let today = formatter.string(from: now)
        let fortyFiveDaysAgo = formatter.string(from: now.addingTimeInterval(-45 * 86_400))
        func discover(_ id: String, _ title: String, _ parameters: [String: String]) -> DiscoveryRail {
            DiscoveryRail(id: id, title: DesktopInterfaceText.value(title), kind: "series", path: "discover/tv",
                          parameters: parameters, usesRegion: false)
        }
        func genre(_ id: String, _ title: String, _ genre: String, _ rating: String, _ votes: String, sort: String) -> DiscoveryRail {
            discover(id, title, ["with_genres": genre, "vote_average.gte": rating, "vote_count.gte": votes, "sort_by": sort])
        }
        var rails = [
            DiscoveryRail(id: "tmdb-series-top10", title: DesktopInterfaceText.value("Top 10 Series Today"),
                          kind: "series", path: "trending/tv/week", ranked: true, usesRegion: false),
            DiscoveryRail(id: "tmdb-series-current", title: DesktopInterfaceText.value("On Tonight"),
                          kind: "series", path: "tv/on_the_air", usesRegion: false),
            discover("tmdb-tv-fresh", "Premiered This Month",
                     ["first_air_date.gte": fortyFiveDaysAgo, "first_air_date.lte": today, "vote_count.gte": "20", "sort_by": "popularity.desc"]),
        ]
        for (title, network, votes) in [("From HBO", "49", "200"), ("Netflix Originals", "213", "300"), ("Apple TV+", "2552", "100"),
                                         ("AMC", "174", "200"), ("FX", "88", "200"), ("Disney+ Originals", "2739", "100"), ("Prime Video", "1024", "200")] {
            rails.append(discover("tmdb-tv-network-" + network, title, ["with_networks": network, "vote_count.gte": votes, "sort_by": "popularity.desc"]))
        }
        rails.append(contentsOf: [
            discover("tmdb-tv-limited", "Limited Series & Miniseries",
                     ["with_type": "2", "vote_average.gte": "7.5", "vote_count.gte": "300", "sort_by": "vote_count.desc"]),
            genre("tmdb-series-genre-18", "Prestige Drama", "18", "8.0", "1000", sort: "vote_average.desc"),
            genre("tmdb-series-genre-35", "Comedy Series", "35", "7.6", "500", sort: "popularity.desc"),
            genre("tmdb-series-genre-80", "Crime & Mystery", "80", "7.5", "500", sort: "vote_average.desc"),
            genre("tmdb-series-genre-10765", "Sci-Fi & Fantasy", "10765", "7.5", "500", sort: "popularity.desc"),
            genre("tmdb-series-genre-99", "Documentary Series", "99", "7.5", "100", sort: "vote_average.desc"),
            DiscoveryRail(id: "tmdb-series-rated", title: DesktopInterfaceText.value("All-Time Great Series"),
                          kind: "series", path: "tv/top_rated", usesRegion: false),
            discover("tmdb-series-long-runners", "Iconic Long-Runners",
                     ["first_air_date.lte": "2010-12-31", "vote_average.gte": "7.8", "vote_count.gte": "500", "sort_by": "vote_count.desc"]),
            discover("tmdb-series-korean", "K-Drama",
                     ["with_origin_country": "KR", "vote_average.gte": "7.5", "vote_count.gte": "100", "sort_by": "popularity.desc"]),
            discover("tmdb-series-british", "British Television",
                     ["with_origin_country": "GB", "vote_average.gte": "7.5", "vote_count.gte": "300", "sort_by": "vote_average.desc"]),
        ])
        return rails
    }

    struct Paging {
        private var cursor: DesktopGridPaging
        private(set) var hasMore: Bool
        private var lastPageIDs: [String]
        var nextPage: Int { cursor.nextPage }

        init(firstPage: [Media]) {
            cursor = DesktopGridPaging(initialCount: firstPage.count)
            hasMore = CatalogRowPaging.initialHasMore(count: firstPage.count)
            lastPageIDs = firstPage.map(\.identity)
        }

        mutating func append(_ incoming: [Media], to current: [Media]) -> [Media] {
            var known = Set(current.map(\.identity))
            let fresh = incoming.filter { known.insert($0.identity).inserted }
            let merged = CatalogRowPaging.merge(current: current, more: fresh, received: incoming.count)
            let pageIDs = incoming.map(\.identity)
            cursor.received(incoming.count)
            // A provider returning the preceding page again must not keep
            // the visible tail requesting the same results.
            hasMore = merged.hasMore && !cursor.finished && pageIDs != lastPageIDs
            lastPageIDs = pageIDs
            return merged.metas
        }
    }

    static func visibleFallback(_ rows: [CatalogRow], heroIDs: Set<String>) -> [CatalogRow] {
        rows.compactMap { row in
            guard row.plan.key.hasPrefix("native-series-") else { return row }
            var result = row
            result.metas = row.metas.prefix(30).filter { !heroIDs.contains($0.id) }
            return result.metas.count >= 4 ? result : nil
        }
    }

    static func visible(_ rails: [DiscoveryRail], heroIDs: Set<String>) -> [DiscoveryRail] {
        rails.compactMap { rail in
            var result = rail
            if rail.ranked {
                guard TopTenGate.renders(active: true, count: rail.metas.count) else { return nil }
                result.metas = Array(rail.metas.prefix(TopTenGate.minimumTitles))
            } else {
                result.metas = rail.metas.filter { !heroIDs.contains($0.id) }
                guard result.metas.count >= 4 else { return nil }
            }
            return result
        }
    }
}

/// Desktop 0.9.132 Movies rows (`views/movies.tsx`: `restRows` and `catalogRows`). When the trending list gives ten
/// titles, the Top 10 row takes them and the separate trending row is hidden. Every other row then skips titles that the
/// hero, the Top 10 row or an earlier row already shows, and a row left with fewer than four titles is dropped.
enum MoviesCatalog {
    static let topTenID = "discovery-tmdb-movie-top10"
    static let trendingID = "discovery-tmdb-movie-trending"

    static func visible(_ rails: [PageRail], heroIDs: Set<String>) -> [PageRail] {
        let topTenRail = rails.first(where: { $0.id == topTenID })
        let topTenMetas = Array((topTenRail?.metas ?? []).prefix(TopTenGate.minimumTitles))
        let rendersTopTen = TopTenGate.renders(active: true, count: topTenMetas.count)
        var seen = heroIDs
        if rendersTopTen {
            for media in topTenMetas { seen.insert(media.id) }
        }
        var result: [PageRail] = []
        for rail in rails {
            if rail.id == topTenID {
                if rendersTopTen { result.append(rail.withMetas(topTenMetas)) }
                continue
            }
            if rendersTopTen && rail.id == trendingID { continue }
            var fresh: [Media] = []
            for media in rail.metas where seen.insert(media.id).inserted {
                fresh.append(media)
            }
            if fresh.count >= 4 { result.append(rail.withMetas(fresh)) }
        }
        return result
    }
}

private extension PageRail {
    func withMetas(_ metas: [Media]) -> PageRail {
        switch self {
        case .catalog(var row):
            row.metas = metas
            return .catalog(row)
        case .discovery(var row):
            row.metas = metas
            return .discovery(row)
        default:
            return self
        }
    }
}
