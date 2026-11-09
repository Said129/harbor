import Foundation

/// Desktop's TMDB movies and series in `searchAll` (`src/lib/search.ts`), as search rows. The rows come after the
/// addon rows and leave out the titles those rows already show. Without a TMDB key there is no request and no row.
enum SearchTMDBSource {
    static func load(query: String, configuration: MetadataConfiguration) async -> CustomListSearchResults.Matches {
        (try? await TMDBService().searchWatchableMatches(query, configuration: configuration)) ?? .init()
    }

    static func rows(for titles: [Media], addonRows: [CatalogRow]) -> [CatalogRow] {
        let fresh = SearchRanking.dropDuplicates(titles, against: addonRows.flatMap(\.metas))
        return [
            row(key: "tmdb-search-movie", kind: "movie", metas: fresh.filter { $0.type == "movie" }),
            row(key: "tmdb-search-series", kind: "series", metas: fresh.filter { $0.type == "series" }),
        ].filter { !$0.metas.isEmpty }
    }

    static func destination(for match: Media, addonRows: [CatalogRow]) -> Media {
        let keys = Set(SearchRanking.identityKeys(for: match))
        return addonRows.lazy.flatMap(\.metas).first { media in
            media.type == match.type && (media.id == match.id || SearchRanking.identityKeys(for: media).contains(where: keys.contains))
        } ?? match
    }

    private static func row(key: String, kind: String, metas: [Media]) -> CatalogRow {
        let addon = Addon(manifest: .object(["id": .string("tmdb"), "name": .string("TMDB")]), transportUrl: "https://api.themoviedb.org/3", enabled: true)
        let plan = RequestPlan(key: key, url: "https://api.themoviedb.org/3/search/multi", title: "TMDB", kind: kind, addon: addon, addonPriority: 0, timeoutMs: 15_000, catalog: nil)
        return CatalogRow(plan: plan, metas: metas)
    }
}
