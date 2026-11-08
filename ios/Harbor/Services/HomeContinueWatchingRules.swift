import Foundation

/// Desktop's Home Continue Watching pass (`home.tsx` `continueWatching`): one card per title name and type, where the
/// most recently watched copy wins, and a 100-card cap. Franchise-root removal is not ported here.
enum HomeContinueWatchingRules {
    /// Desktop's `byId.size >= 100` cutoff.
    static let maximumCards = 100

    /// Desktop's `franchiseDedupKey` without the franchise-suffix strip: lowercase letters and digits only.
    static func nameKey(_ name: String?) -> String? {
        var key = ""
        for scalar in (name ?? "").lowercased().unicodeScalars where (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
            key.unicodeScalars.append(scalar)
        }
        return key.isEmpty ? nil : key
    }

    /// Desktop's `lastWatchedOf`: `state.lastWatched` when it is a real time, otherwise `_mtime`.
    static func lastWatched(_ record: LibraryRecord) -> Double {
        if let watched = record.lastWatchedTimestamp, watched > 0 { return watched }
        return record.modifiedTimestamp ?? 0
    }

    /// Desktop's name pass. `ordered` must already be in Continue Watching order; the result keeps that order.
    static func cards(_ ordered: [LibraryRecord]) -> [LibraryRecord] {
        var byID: [String: LibraryRecord] = [:]
        var byName: [String: LibraryRecord] = [:]
        for record in ordered {
            if byID[record.id] != nil { continue }
            if let name = nameKey(record.media?.name) {
                let key = (record.media?.type ?? "") + ":" + name
                if let held = byName[key] {
                    if lastWatched(record) > lastWatched(held) {
                        byID[held.id] = nil
                        byName[key] = record
                        byID[record.id] = record
                    }
                    continue
                }
                byName[key] = record
            }
            byID[record.id] = record
            if byID.count >= maximumCards { break }
        }
        var emitted = Set<String>()
        return ordered.filter { byID[$0.id] != nil && emitted.insert($0.id).inserted }
    }
}
