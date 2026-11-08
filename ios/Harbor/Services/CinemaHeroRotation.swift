import Foundation

/// Desktop's cinema hero timing (`cinema-hero.tsx` `ROTATE_MS`): the slide moves on its own, in order, and wraps around.
enum CinemaHeroRotation {
    static let interval: Duration = .seconds(11)

    static func next(after index: Int, count: Int) -> Int {
        count > 0 ? (index + 1) % count : 0
    }
}

/// Desktop's `rotateDaily` (`movie-specs.ts`): the same day-based pick order, so the hero changes once a day.
/// The recently-played exclusion is not ported because the iOS app has no playback-history store with titles.
enum DailyHeroRotation {
    static func currentDay(now: Date = Date()) -> Int {
        Int(now.timeIntervalSince1970 / 86_400)
    }

    static func pick<T>(_ pool: [T], count: Int, day: Int) -> [T] {
        guard !pool.isEmpty else { return [] }
        var result: [T] = []
        var used = Set<Int>()
        while result.count < count && used.count < pool.count {
            var index = (day * 13 + result.count * 17) % pool.count
            while used.contains(index) { index = (index + 1) % pool.count }
            used.insert(index)
            result.append(pool[index])
        }
        return result
    }
}
