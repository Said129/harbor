import Foundation

/// Desktop's movie mood rails (`src/lib/feed/moods.ts`, `pickMoodSpecs`): an active seasonal rail first, then a
/// time-of-day and daily-seeded pick from a fixed pool. Pure: the date and calendar are passed in.
enum MoodRails {
    struct Rail: Equatable, Sendable {
        let id: String
        /// Desktop's title. A time-of-day rail is "label · name", the same text Desktop builds.
        let title: String
        let parameters: [String: String]
    }

    private struct Mood {
        let id: String
        let name: String
        let parameters: [String: String]
    }

    private struct Seasonal {
        let id: String
        let title: String
        let relatedPoolID: String?
        let parameters: [String: String]
    }

    private enum Bucket: Int, CaseIterable {
        case morning, afternoon, evening, late

        var label: String {
            switch self {
            case .morning: "This Morning"
            case .afternoon: "This Afternoon"
            case .evening: "Tonight"
            case .late: "Late Night"
            }
        }
    }

    private static let pool: [Mood] = [
        Mood(id: "comfort", name: "Comfort Watch", parameters: ["with_genres": "10751,35,16", "vote_average.gte": "7.2", "vote_count.gte": "1200", "sort_by": "popularity.desc"]),
        Mood(id: "mind-benders", name: "Mind Benders", parameters: ["with_genres": "878,9648,53", "vote_average.gte": "7.4", "vote_count.gte": "1500", "sort_by": "vote_average.desc"]),
        Mood(id: "after-dark", name: "After Dark", parameters: ["with_genres": "27", "vote_average.gte": "6.6", "vote_count.gte": "400", "sort_by": "popularity.desc"]),
        Mood(id: "date-night", name: "Date Night", parameters: ["with_genres": "10749,35", "vote_average.gte": "7.0", "vote_count.gte": "700", "sort_by": "vote_average.desc"]),
        Mood(id: "adrenaline", name: "Adrenaline Rush", parameters: ["with_genres": "28,53", "vote_average.gte": "6.9", "vote_count.gte": "1200", "sort_by": "popularity.desc"]),
        Mood(id: "tearjerker", name: "Bring the Tissues", parameters: ["with_genres": "18,10749", "vote_average.gte": "7.6", "vote_count.gte": "1200", "sort_by": "vote_average.desc"]),
        Mood(id: "feel-good", name: "Feel-Good Hits", parameters: ["with_genres": "35,10751", "vote_average.gte": "7.0", "vote_count.gte": "1000", "sort_by": "popularity.desc"]),
        Mood(id: "laugh", name: "Laugh Out Loud", parameters: ["with_genres": "35", "vote_average.gte": "6.8", "vote_count.gte": "1200", "sort_by": "popularity.desc"]),
        Mood(id: "heist", name: "Heists & Cons", parameters: ["with_genres": "80,53", "vote_average.gte": "7.0", "vote_count.gte": "800", "sort_by": "vote_average.desc"]),
        Mood(id: "space", name: "Into the Stars", parameters: ["with_genres": "878", "vote_average.gte": "7.0", "vote_count.gte": "1500", "sort_by": "vote_average.desc"]),
        Mood(id: "fantasy", name: "Sword & Sorcery", parameters: ["with_genres": "14,12", "vote_average.gte": "7.0", "vote_count.gte": "1200", "sort_by": "popularity.desc"]),
        Mood(id: "true-crime", name: "True Crime Files", parameters: ["with_genres": "80,99", "vote_average.gte": "7.2", "vote_count.gte": "150", "sort_by": "vote_average.desc"]),
        Mood(id: "slow-burn", name: "Slow-Burn Dramas", parameters: ["with_genres": "18", "vote_average.gte": "7.7", "vote_count.gte": "1500", "sort_by": "vote_average.desc"]),
        Mood(id: "neo-noir", name: "Neo-Noir", parameters: ["with_genres": "80,9648", "vote_average.gte": "7.3", "vote_count.gte": "700", "sort_by": "vote_average.desc"]),
        Mood(id: "coming-of-age", name: "Coming of Age", parameters: ["with_genres": "18,35", "vote_average.gte": "7.3", "vote_count.gte": "600", "sort_by": "vote_average.desc"]),
        Mood(id: "epic-adventure", name: "Epic Adventures", parameters: ["with_genres": "12,28", "vote_average.gte": "7.2", "vote_count.gte": "1500", "sort_by": "popularity.desc"]),
        Mood(id: "war-stories", name: "War Stories", parameters: ["with_genres": "10752,18", "vote_average.gte": "7.4", "vote_count.gte": "800", "sort_by": "vote_average.desc"]),
        Mood(id: "westerns", name: "Saddle Up", parameters: ["with_genres": "37", "vote_average.gte": "7.0", "vote_count.gte": "300", "sort_by": "vote_average.desc"]),
        Mood(id: "animation-night", name: "Animation Night", parameters: ["with_genres": "16", "vote_average.gte": "7.4", "vote_count.gte": "800", "sort_by": "vote_average.desc"]),
        Mood(id: "musicals", name: "Turn It Up", parameters: ["with_genres": "10402", "vote_average.gte": "7.0", "vote_count.gte": "200", "sort_by": "vote_average.desc"]),
        Mood(id: "history-buff", name: "History Buff", parameters: ["with_genres": "36,18", "vote_average.gte": "7.4", "vote_count.gte": "600", "sort_by": "vote_average.desc"]),
        Mood(id: "mystery-box", name: "Whodunit", parameters: ["with_genres": "9648,53", "vote_average.gte": "7.2", "vote_count.gte": "800", "sort_by": "vote_average.desc"]),
        Mood(id: "visually-stunning", name: "Eye Candy", parameters: ["with_genres": "12,14,878", "vote_average.gte": "7.3", "vote_count.gte": "2000", "sort_by": "popularity.desc"]),
        Mood(id: "cult-classics", name: "Cult Classics", parameters: ["primary_release_date.lte": "2005-12-31", "vote_average.gte": "7.5", "vote_count.gte": "600", "sort_by": "vote_count.desc"]),
    ]

    private static let timePreferences: [Bucket: [String]] = [
        .morning: ["feel-good", "comfort", "laugh", "animation-night", "coming-of-age"],
        .afternoon: ["epic-adventure", "fantasy", "space", "westerns", "history-buff"],
        .evening: ["date-night", "neo-noir", "heist", "slow-burn", "mystery-box", "visually-stunning"],
        .late: ["after-dark", "mind-benders", "true-crime", "adrenaline", "war-stories"],
    ]

    /// The first seasonal rail active on the date, in Desktop's order. Month is zero-based, as in Desktop.
    private static func seasonalRail(year: Int, month: Int, day: Int) -> Seasonal? {
        if (month == 11 && day >= 27) || (month == 0 && day <= 4) {
            return Seasonal(id: "new-year", title: "New Year, New Stories", relatedPoolID: "feel-good",
                            parameters: ["with_genres": "35,12", "vote_average.gte": "7.0", "vote_count.gte": "1500", "sort_by": "popularity.desc"])
        }
        if month == 1 && day <= 15 {
            return Seasonal(id: "valentine", title: "Be My Valentine", relatedPoolID: "date-night",
                            parameters: ["with_genres": "10749", "vote_average.gte": "7.0", "vote_count.gte": "800", "sort_by": "vote_average.desc"])
        }
        if month == 9 {
            return Seasonal(id: "spooky", title: "Spooky Season", relatedPoolID: "after-dark",
                            parameters: ["with_genres": "27", "vote_average.gte": "6.4", "vote_count.gte": "300", "sort_by": "popularity.desc"])
        }
        if month == 11 && day <= 26 {
            return Seasonal(id: "holiday", title: "Holiday Warmth", relatedPoolID: "comfort",
                            parameters: ["with_genres": "10751,35", "vote_average.gte": "6.8", "vote_count.gte": "600", "sort_by": "popularity.desc"])
        }
        if month >= 5 && month <= 7 {
            return Seasonal(id: "summer", title: "Summer Blockbusters", relatedPoolID: "epic-adventure",
                            parameters: ["with_genres": "28,12,878", "vote_average.gte": "6.8", "vote_count.gte": "3000", "sort_by": "popularity.desc"])
        }
        if (month == 0 && day >= 5) || (month == 1 && day >= 16) || (month == 2 && day <= 20) {
            return Seasonal(id: "awards", title: "Awards Contenders", relatedPoolID: "slow-burn",
                            parameters: ["primary_release_date.gte": "\(year - 2)-01-01", "vote_average.gte": "7.3", "vote_count.gte": "800", "sort_by": "vote_average.desc"])
        }
        if month == 8 || month == 10 {
            return Seasonal(id: "autumn", title: "Cozy Autumn Nights", relatedPoolID: "slow-burn",
                            parameters: ["with_genres": "18,9648", "vote_average.gte": "7.4", "vote_count.gte": "800", "sort_by": "vote_average.desc"])
        }
        if month == 3 || month == 4 || (month == 2 && day >= 21) {
            return Seasonal(id: "spring", title: "Spring Awakening", relatedPoolID: "feel-good",
                            parameters: ["with_genres": "35,12,10751", "vote_average.gte": "7.0", "vote_count.gte": "800", "sort_by": "popularity.desc"])
        }
        return nil
    }

    /// Desktop's `dailySeed`: year * 10000 + month * 100 + day, with a one-based month.
    static func dailySeed(year: Int, month: Int, day: Int) -> Int {
        year * 10_000 + month * 100 + day
    }

    /// Desktop's `rotate`: the array starting at `by` modulo its length.
    static func rotate<T>(_ values: [T], by: Int) -> [T] {
        guard !values.isEmpty else { return values }
        let k = ((by % values.count) + values.count) % values.count
        return Array(values[k...]) + Array(values[..<k])
    }

    /// Desktop's `pickMoodSpecs`: up to `count` rails for the date's time of day, with the seasonal rail first when one is active.
    static func pick(now: Date = Date(), calendar: Calendar = .current, count: Int = 6) -> [Rail] {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let year = parts.year ?? 1970, month = (parts.month ?? 1) - 1, day = parts.day ?? 1, hour = parts.hour ?? 0
        let bucket: Bucket = hour < 11 ? .morning : hour < 17 ? .afternoon : hour < 22 ? .evening : .late
        let seed = dailySeed(year: year, month: month + 1, day: day)
        let bucketIndex = bucket.rawValue

        var out: [Rail] = []
        var used = Set<String>()
        if let active = seasonalRail(year: year, month: month, day: day) {
            out.append(Rail(id: "mood-" + active.id, title: active.title, parameters: active.parameters))
            used.insert(active.id)
            if let related = active.relatedPoolID { used.insert(related) }
        }

        let order = rotate(timePreferences[bucket] ?? [], by: seed) + rotate(pool.map(\.id), by: seed + bucketIndex * 31)
        for id in order {
            if out.count >= count { break }
            if used.contains(id) { continue }
            guard let mood = pool.first(where: { $0.id == id }) else { continue }
            used.insert(id)
            out.append(Rail(id: "mood-" + id, title: bucket.label + " · " + mood.name, parameters: mood.parameters))
        }
        return Array(out.prefix(count))
    }
}
