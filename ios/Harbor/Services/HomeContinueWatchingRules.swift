import Foundation

/// Desktop's Home Continue Watching pass (`home.tsx` `continueWatching`): one card per title name and type, where the
/// most recently watched copy wins, and a 100-card cap. Root-wide dismissals are applied by `LibraryModel`.
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

    /// Desktop's second Home pass: one card per resolved anime franchise root. Cards are visited most recently watched
    /// first, and a later card from the same root is removed. Cards without a root are never removed, and the result
    /// keeps the order of `ordered`.
    static func onePerFranchise<Item>(_ ordered: [Item], root: (Item) -> String?, watched: (Item) -> Double) -> [Item] {
        let byRecency = ordered.indices.sorted { (first: Int, second: Int) -> Bool in
            let firstWatched = watched(ordered[first])
            let secondWatched = watched(ordered[second])
            if firstWatched != secondWatched { return firstWatched > secondWatched }
            return first < second
        }
        var seenRoots = Set<String>()
        var removed = Set<Int>()
        for index in byRecency {
            guard let franchise = root(ordered[index]) else { continue }
            if !seenRoots.insert(franchise).inserted { removed.insert(index) }
        }
        return ordered.indices.filter { !removed.contains($0) }.map { ordered[$0] }
    }
}
