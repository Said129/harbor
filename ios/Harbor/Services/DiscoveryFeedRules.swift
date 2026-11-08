import Foundation

/// Desktop's seeded randomness (`src/lib/feed/tags.ts`): the same UTC day and salt give the same order on every run.
enum DiscoveryFeedRandom {
    /// Desktop's `mulberry32`: a seeded generator whose values lie in [0, 1).
    struct Mulberry32 {
        private var state: UInt32
        init(seed: UInt32) { state = seed }
        mutating func next() -> Double {
            state = state &+ 0x6d2b79f5
            var t = state
            t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
    }

    /// Desktop's `dayIndex`: whole days since the Unix epoch, counted in UTC.
    static func dayIndex(_ now: Date) -> Int {
        Int((now.timeIntervalSince1970 * 1_000 / 86_400_000).rounded(.down))
    }

    /// Desktop's `hashStr`: FNV-1a over the UTF-16 code units.
    static func hash(_ text: String) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        for unit in text.utf16 { value = (value ^ UInt32(unit)) &* 16_777_619 }
        return value
    }

    /// Desktop's `mixSeed`: `Math.imul(base, 2654435761) + salt`, as an unsigned 32-bit value.
    static func mixSeed(_ base: Int, _ salt: UInt32) -> UInt32 {
        UInt32(truncatingIfNeeded: base) &* 2_654_435_761 &+ salt
    }

    /// Desktop's `rng(base, salt)` for a named salt.
    static func generator(base: Int, salt: String) -> Mulberry32 {
        Mulberry32(seed: mixSeed(base, hash(salt)))
    }

    /// Desktop's `mulberry32(mixSeed(base, salt))` for a numeric salt.
    static func generator(base: Int, salt: UInt32) -> Mulberry32 {
        Mulberry32(seed: mixSeed(base, salt))
    }
}

/// Desktop's daily row selection helpers (`src/lib/feed/daily-rows.ts`, `daily-rows-select.ts`).
enum DiscoveryDailyRows {
    static let anchorSalt: UInt32 = 90_001
    static let orderSalt: UInt32 = 90_007
    static let trendingAnchor = "trending"
    static let topRatedAnchor = "critically_loved"
    static let awardsAnchor = "award_winning"
    /// Desktop's `ROTATING_ANCHORS`: one of these closes the list each day.
    static let rotatingAnchors = ["documentaries", "hidden_gems_anchor", "cult"]

    /// Desktop's `normalizedAffinity`: the key's weight divided by the largest absolute weight, never below zero.
    static func normalizedAffinity(_ weights: [String: Double], key: String) -> Double {
        let largest = weights.values.map { abs($0) }.max() ?? 0
        guard largest > 0 else { return 0 }
        return max(0, (weights[key] ?? 0) / largest)
    }

    /// Desktop's `weightedPickWithoutReplacement`: each draw removes the chosen value from the pool.
    static func weightedPick<T>(_ values: [T], weight: (T) -> Double, rng: inout DiscoveryFeedRandom.Mulberry32, count: Int) -> [T] {
        var pool = values.map { (value: $0, weight: max(0, weight($0))) }
        var out: [T] = []
        while out.count < count && !pool.isEmpty {
            let total = pool.reduce(0) { $0 + $1.weight }
            var index = 0
            if total <= 0 {
                index = Int(rng.next() * Double(pool.count))
            } else {
                var roll = rng.next() * total
                for position in pool.indices {
                    roll -= pool[position].weight
                    if roll <= 0 { index = position; break }
                }
            }
            out.append(pool[index].value)
            pool.remove(at: index)
        }
        return out
    }

    /// Desktop's `fy` in `orderRows`: a Fisher-Yates shuffle driven by the seeded generator.
    static func shuffle<T>(_ values: [T], rng: inout DiscoveryFeedRandom.Mulberry32) -> [T] {
        var result = values
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, to: 0, by: -1) {
            let other = Int(rng.next() * Double(index + 1))
            result.swapAt(index, other)
        }
        return result
    }

    /// Desktop's `orderRows`. The trending, top-rated and award anchors come first, then the shuffled rows (rows
    /// shown recently after the fresh ones), then the closing anchor picked from `rotatingAnchors` for the day.
    /// Rows are matched by their key's prefix before the colon, as Desktop does.
    static func order<T>(_ rows: [T], key: (T) -> String, base: Int, count: Int, recent: Set<String>) -> [T] {
        let keys = rows.map(key)
        func anchorIndex(_ anchor: String) -> Int? { keys.firstIndex { $0.hasPrefix(anchor + ":") } }
        var anchorRandom = DiscoveryFeedRandom.generator(base: base, salt: anchorSalt)
        let closingAnchor = rotatingAnchors[Int(anchorRandom.next() * Double(rotatingAnchors.count))]
        let trending = anchorIndex(trendingAnchor)
        let topRated = anchorIndex(topRatedAnchor)
        let award = anchorIndex(awardsAnchor)
        let closing = anchorIndex(closingAnchor)
        let pinned = Set([trending, topRated, award, closing].compactMap { $0 })
        let middle = rows.indices.filter { !pinned.contains($0) }
        let fresh = middle.filter { !recent.contains(keys[$0]) }
        let stale = middle.filter { recent.contains(keys[$0]) }
        var orderRandom = DiscoveryFeedRandom.generator(base: base, salt: orderSalt)
        let shuffledFresh = shuffle(fresh, rng: &orderRandom)
        let shuffledStale = shuffle(stale, rng: &orderRandom)
        let bodyTarget = max(0, count - pinned.count)
        let body = Array((shuffledFresh + shuffledStale).prefix(bodyTarget + 2))
        var result: [T] = []
        if let index = trending { result.append(rows[index]) }
        if let index = topRated { result.append(rows[index]) }
        if let index = award { result.append(rows[index]) }
        result += body.map { rows[$0] }
        if let index = closing { result.append(rows[index]) }
        return result
    }
}
