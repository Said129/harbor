import Foundation

/// Desktop counts complete provider pages and raw results, including duplicates.
/// A duplicate-only page must not hide fresh titles on the following page.
struct DesktopGridPaging: Equatable, Sendable {
    static let maximumPages = 40
    private(set) var page = 0
    private(set) var loaded = 0
    private(set) var finished = false
    var nextPage: Int { page + 1 }
    init(initialCount: Int = 0) {
        loaded = max(0, initialCount); page = loaded == 0 ? 0 : 1
    }
    mutating func received(_ count: Int) {
        guard !finished else { return }
        loaded += max(0, count); page += 1
        finished = count <= 0 || page >= Self.maximumPages
    }
}
