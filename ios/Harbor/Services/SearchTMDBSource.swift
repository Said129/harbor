import Foundation

/// Desktop's TMDB movies and series in `searchAll` (`src/lib/search.ts`), as search rows. The rows come after the
/// addon rows and leave out the titles those rows already show. Without a TMDB key there is no request and no row.
enum SearchTMDBSource {
    static func rows(query: String, addonRows: [CatalogRow], configuration: MetadataConfiguration) async -> [CatalogRow] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !configuration.tmdbKey.isEmpty else { return [] }
        let found = (try? await TMDBService().searchWatchables(text, configuration: configuration)) ?? []
        let fresh = SearchRanking.dropDuplicates(found, against: addonRows.flatMap { $0.metas })
        return [
            row(key: "tmdb-search-movie", kind: "movie", metas: fresh.filter { $0.type == "movie" }),
            row(key: "tmdb-search-series", kind: "series", metas: fresh.filter { $0.type == "series" }),
        ].filter { !$0.metas.isEmpty }
    }

    private static func row(key: String, kind: String, metas: [Media]) -> CatalogRow {
        let addon = Addon(manifest: .object(["id": .string("tmdb"), "name": .string("TMDB")]), transportUrl: "https://api.themoviedb.org/3", enabled: true)
        let plan = RequestPlan(key: key, url: "https://api.themoviedb.org/3/search/multi", title: "TMDB", kind: kind, addon: addon, addonPriority: 0, timeoutMs: 15_000, catalog: nil)
        return CatalogRow(plan: plan, metas: metas)
    }
}
