import Foundation

/// Desktop's inline paging for movie and series rows (`movies.tsx` `loadMore`, `MAX_PER_ROW`, and the `hasMore` rule).
enum CatalogRowPaging {
    /// Desktop's `MAX_PER_ROW`.
    static let maximumRowItems = 30
    /// Desktop's first-page rule: a row whose first page has at least this many titles can load more.
    static let firstPageThreshold = 14

    static func initialHasMore(count: Int) -> Bool {
        count >= firstPageThreshold && count < maximumRowItems
    }

    /// Desktop's `loadMore` guard: a row loads only when it can, is not already loading, and is under the cap.
    static func shouldRequest(hasMore: Bool, loading: Bool, count: Int) -> Bool {
        hasMore && !loading && count < maximumRowItems
    }

    /// Desktop's merge: titles already in the row are skipped, the row is cut at the cap, and it can load more only
    /// while the cap is not reached and the provider returned something (`received` is the raw count).
    static func merge(current: [Media], more: [Media], received: Int) -> (metas: [Media], hasMore: Bool) {
        let known = Set(current.map(\.identity))
        let combined = current + more.filter { !known.contains($0.identity) }
        let reachedCap = combined.count >= maximumRowItems
        return (reachedCap ? Array(combined.prefix(maximumRowItems)) : combined, !reachedCap && received > 0)
    }
}
