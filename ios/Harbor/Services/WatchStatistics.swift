import Foundation

/// Desktop's Wrapped aggregation (`src/lib/wrapped/aggregate.ts` and `archetype.ts`), as a pure value type.
/// The inputs are plain watch events, so the computation can be tested without the library or the UI.
struct WatchStatistics: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case movie, series, anime }

    /// Desktop's `trakt` source; `local` is the on-device history and gets Desktop's estimate note.
    enum Source: Equatable, Sendable { case trakt, local }

    struct Event: Equatable, Sendable {
        let id: String
        let title: String
        let kind: Kind
        let watchedAt: Date
        let poster: String?
    }

    struct TopTitle: Equatable, Sendable {
        let id: String
        let title: String
        let kind: Kind
        let count: Int
        let poster: String?
    }

    struct DayCount: Equatable, Sendable {
        let day: Date
        let count: Int
    }

    struct Split: Equatable, Sendable {
        let movies: Int
        let series: Int
        let anime: Int
    }

    /// Desktop's archetype ids, in the order `deriveArchetype` checks them.
    enum Archetype: Equatable, Sendable {
        case anime
        case binger(Int)
        case filmBuff
        case seriesSlayer
        case explorer
        case wellRounded

        /// English Desktop strings. The view passes them through `DesktopInterfaceText`.
        var label: String {
            switch self {
            case .anime: return "The Anime Devotee"
            case .binger: return "The Binger"
            case .filmBuff: return "The Film Buff"
            case .seriesSlayer: return "The Series Slayer"
            case .explorer: return "The Explorer"
            case .wellRounded: return "The Well-Rounded"
            }
        }

        /// Desktop's blurb. `{n}` is the binge size for `.binger` (a template literal on Desktop).
        var blurb: String {
            switch self {
            case .anime: return "Over half your year was anime. Respect the grind."
            case .binger: return "You once tore through {n} in a single day."
            case .filmBuff: return "Movies are your natural habitat."
            case .seriesSlayer: return "You live one episode at a time."
            case .explorer: return "You cast a wide net across everything."
            case .wellRounded: return "A little of everything, all year long."
            }
        }

        var blurbVariables: [String: String] {
            if case .binger(let count) = self { return ["n": String(count)] }
            return [:]
        }
    }

    let source: Source
    let year: Int?
    let totalTitles: Int
    let totalPlays: Int
    let estimatedHours: Int
    /// Days with at least one play, in chronological order (Desktop's heatmap source).
    let days: [DayCount]
    let topTitles: [TopTitle]
    let split: Split
    let firstPlay: Event?
    let lastPlay: Event?
    let longestBinge: DayCount?
    let archetype: Archetype

    /// Desktop's estimates: a movie is 115 minutes, an episode 42.
    static let movieMinutes = 115.0
    static let episodeMinutes = 42.0
    static let topTitleLimit = 20

    /// Desktop's `aggregateWrapped`. `year` limits the events to one calendar year when set.
    static func make(events: [Event], source: Source, year: Int?, calendar: Calendar) -> WatchStatistics {
        let inYear = events.filter { event in
            guard let year else { return true }
            return calendar.component(.year, from: event.watchedAt) == year
        }
        // Desktop sorts by time, and a stable sort keeps equal timestamps in input order.
        let ordered = inYear.enumerated().sorted { lhs, rhs in
            if lhs.element.watchedAt == rhs.element.watchedAt { return lhs.offset < rhs.offset }
            return lhs.element.watchedAt < rhs.element.watchedAt
        }.map(\.element)

        var titleOrder: [String] = []
        var titles: [String: TopTitle] = [:]
        var dayOrder: [Date] = []
        var dayTotals: [Date: Int] = [:]
        var movies = 0
        var series = 0
        var anime = 0
        var hours = 0.0
        for event in ordered {
            if let existing = titles[event.id] {
                titles[event.id] = TopTitle(id: existing.id, title: existing.title, kind: existing.kind, count: existing.count + 1, poster: existing.poster)
            } else {
                titleOrder.append(event.id)
                titles[event.id] = TopTitle(id: event.id, title: event.title, kind: event.kind, count: 1, poster: event.poster)
            }
            let day = calendar.startOfDay(for: event.watchedAt)
            if dayTotals[day] == nil { dayOrder.append(day) }
            dayTotals[day, default: 0] += 1
            switch event.kind {
            case .movie:
                movies += 1
                hours += movieMinutes / 60
            case .series:
                series += 1
                hours += episodeMinutes / 60
            case .anime:
                anime += 1
                hours += episodeMinutes / 60
            }
        }

        let days = dayOrder.map { DayCount(day: $0, count: dayTotals[$0] ?? 0) }
        // Desktop uses a strict comparison, so a tie keeps the earliest day.
        var longest: DayCount?
        for day in days where day.count > (longest?.count ?? 0) {
            longest = day
        }

        let ranked = titleOrder.enumerated().sorted { lhs, rhs in
            let left = titles[lhs.element]?.count ?? 0
            let right = titles[rhs.element]?.count ?? 0
            if left == right { return lhs.offset < rhs.offset }
            return left > right
        }
        let topTitles = ranked.prefix(topTitleLimit).compactMap { titles[$0.element] }
        let split = Split(movies: movies, series: series, anime: anime)

        return WatchStatistics(
            source: source,
            year: year,
            totalTitles: titles.count,
            totalPlays: ordered.count,
            estimatedHours: Int(hours.rounded()),
            days: days,
            topTitles: topTitles,
            split: split,
            firstPlay: ordered.first,
            lastPlay: ordered.last,
            longestBinge: longest,
            archetype: archetype(split: split, longestBinge: longest?.count ?? 0, totalTitles: titles.count)
        )
    }

    /// Desktop's year view: the given calendar year, or all time when that year has no plays.
    static func resolved(events: [Event], source: Source, year: Int, calendar: Calendar) -> WatchStatistics {
        let current = make(events: events, source: source, year: year, calendar: calendar)
        guard current.totalPlays == 0, !events.isEmpty else { return current }
        return make(events: events, source: source, year: nil, calendar: calendar)
    }

    /// Desktop's `deriveArchetype`. The share checks use the total, or 1 when there are no plays.
    static func archetype(split: Split, longestBinge: Int, totalTitles: Int) -> Archetype {
        let total = Double(max(split.movies + split.series + split.anime, 1))
        if Double(split.anime) / total >= 0.5 { return .anime }
        if longestBinge >= 8 { return .binger(longestBinge) }
        if Double(split.movies) / total >= 0.6 { return .filmBuff }
        if Double(split.series) / total >= 0.6 { return .seriesSlayer }
        if totalTitles >= 60 { return .explorer }
        return .wellRounded
    }
}
