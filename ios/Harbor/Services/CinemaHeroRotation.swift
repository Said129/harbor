import Foundation

/// Desktop's cinema hero timing (`cinema-hero.tsx` `ROTATE_MS`): the slide moves on its own, in order, and wraps around.
enum CinemaHeroRotation {
    static let interval: Duration = .seconds(11)

    static func canAdvance(count: Int, visible: Bool, foreground: Bool, interacting: Bool) -> Bool {
        count > 1 && visible && foreground && !interacting
    }

    static func next(after index: Int, count: Int) -> Int {
        count > 0 ? (index + 1) % count : 0
    }
}

/// Desktop's `rotateDaily` (`movie-specs.ts`): the same day-based pick order, so the hero changes once a day.
enum DailyHeroRotation {
    static let movieSlideCount = 5

    struct RecentMovies: Sendable {
        private var ids = Set<String>()
        private var titles = Set<String>()

        init(_ history: [String: StreamPlaybackEntry]) {
            for (key, entry) in history {
                if let id = key.split(separator: "|", maxSplits: 1).first { ids.insert(String(id)) }
                for title in [entry.parsedTitle, entry.title].compactMap({ $0 }) {
                    let normalized = Self.titleKey(title)
                    if !normalized.isEmpty { titles.insert(normalized) }
                }
            }
        }

        func contains(_ media: Media) -> Bool {
            ids.contains(media.id) || titles.contains(Self.titleKey(media.name))
        }

        private static func titleKey(_ title: String) -> String {
            title.lowercased().replacingOccurrences(of: #"\([0-9]{4}\)"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
        }
    }

    static func movies(_ lists: [[Media]], recent: RecentMovies, day: Int) -> [Media] {
        var ids = Set<String>()
        let pool = lists.joined().filter { $0.background?.isEmpty == false && ids.insert($0.id).inserted }
        let unseen = pool.filter { !recent.contains($0) }
        let base = unseen.count >= movieSlideCount ? unseen : pool
        return pick(base, count: movieSlideCount, day: day)
    }

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
