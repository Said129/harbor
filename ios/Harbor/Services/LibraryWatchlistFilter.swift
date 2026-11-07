import Foundation

/// Desktop's watchlist rule (`filterLibrary` in watchlist mode, watchlist-tab.tsx).
/// Bookmarked-only on: only saved titles (`bookmarked`). Off: also entries Stremio auto-added
/// when you pressed play (temp) that have not been started yet. Removed records never show.
enum LibraryWatchlistFilter {
    static func includes(_ record: LibraryRecord, bookmarkedOnly: Bool) -> Bool {
        if bookmarkedOnly { return record.bookmarked }
        if record.raw["removed"] == .bool(true) { return false }
        if record.bookmarked { return true }
        return (record.raw["state"]["timeOffset"].numericValue ?? 0) <= 0
    }

    static func filter(_ records: [LibraryRecord], bookmarkedOnly: Bool) -> [LibraryRecord] {
        records.filter { (record: LibraryRecord) -> Bool in
            includes(record, bookmarkedOnly: bookmarkedOnly)
        }
    }
}
