import Foundation

// Build once on the cache actor. SwiftUI reads immutable values instead of
// parsing and sorting the whole cloud library on each view update.
struct LibrarySnapshot: Sendable {
    let records: [JSONValue]
    let items: [LibraryRecord]
    let continuing: [LibraryRecord]

    init(_ records: [JSONValue]) {
        self.records = records
        items = records.map { LibraryRecord(raw: $0) }
            .filter { !$0.id.isEmpty && $0.media != nil }
            .sorted { $0.activityTimestamp == $1.activityTimestamp ? $0.id < $1.id : $0.activityTimestamp > $1.activityTimestamp }
        var display = LibraryDisplay(); display.filter = .continuing
        continuing = LibraryListing.select(items.filter(\.continuing), display: display, query: "")
    }
}

// The same immutable formatters serve library and episode dates. The lock
// keeps Foundation's reference types confined across cache/network actors.
final class ISO8601DateParser: @unchecked Sendable {
    static let shared = ISO8601DateParser()
    private let lock = NSLock()
    private let fractional = ISO8601DateFormatter()
    private let whole = ISO8601DateFormatter()

    private init() { fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds] }

    func date(_ value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return fractional.date(from: value) ?? whole.date(from: value)
    }
}
