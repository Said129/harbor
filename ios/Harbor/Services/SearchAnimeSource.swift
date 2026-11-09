import Foundation

/// One neutral row for the merged public anime providers, shown through the same cards and detail navigation as addons.
enum SearchAnimeSource {
    static let rowID = "anime-search"

    static func row(metas: [Media], excluding existing: [Media] = []) -> CatalogRow? {
        let unique = SearchRanking.dropDuplicates(metas, against: existing)
        guard !unique.isEmpty else { return nil }
        // CatalogRails needs a plan for its layout; this disabled placeholder is never fetched or browsed.
        let addon = Addon(manifest: .object(["id": .string("harbor.search.anime"), "name": .string("Anime")]),
                          transportUrl: "", enabled: false)
        let plan = RequestPlan(key: rowID, url: "", title: "Anime", kind: "anime", addon: addon,
                               addonPriority: 0, timeoutMs: 0, catalog: nil)
        return CatalogRow(plan: plan, metas: unique)
    }
}
