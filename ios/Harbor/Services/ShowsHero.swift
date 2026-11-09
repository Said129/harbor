import Foundation

enum ShowsHero {
    static let slideCount = 6
    static let candidateLimit = 240

    private static let mastCopy: [[(kicker: String, title: String, subtitle: String)]] = [
        [
            ("Morning Lineup", "Easing into series", "Slow-burn worlds and bright chapters worth opening with coffee."),
            ("Good Morning", "Today's openers", "Series to ease into while the day is still quiet."),
            ("Daybreak", "First-light picks", "Worlds to step into before the inbox catches up."),
            ("AM Picks", "Coffee-and-couch", "Half-hours, anthologies, and a few epics for the morning routine."),
            ("Open the Day", "Series with mileage", "Long-running comforts and new chapters worth pressing play on."),
            ("Quiet Hours", "Slow-burn starts", "Stories that reward your attention before the day gets loud."),
            ("This Morning", "Worth catching up on", "What everyone has been quietly binging this week."),
        ],
        [
            ("Afternoon Picks", "Daytime watching", "Easy half-hours and lighter dramas to ride out the afternoon."),
            ("Midday Lineup", "Between meetings", "Episodes you can drop into without losing the thread."),
            ("Afternoon Roll", "Pick up an episode", "Lunch-break comedies and slow-cooker dramas, ready when you are."),
            ("The Long Lunch", "Series to disappear into", "Worlds wide enough for an hour or a whole free afternoon."),
            ("Daylight Watching", "Bright-side series", "Sharp comedies, sunny worlds, and the occasional binge bait."),
            ("Holdover Picks", "Carry it through the day", "Companion series for whatever the afternoon throws at you."),
            ("PM Picks", "Couch hours", "Series for the part of the day that runs on coffee and snacks."),
        ],
        [
            ("Tonight", "Tonight's lineup", "Prestige drama, weekly chapters, and series worth disappearing into."),
            ("Prime Time", "What to watch tonight", "Crowd-pleasers, prestige picks, and the kind of series people text about."),
            ("Sundown", "Evening on the couch", "Drop-in chapters and long arcs for the post-dinner stretch."),
            ("Press Play", "Tonight's marquee", "The series that make the rest of the night disappear."),
            ("Tonight's Slate", "Episodes worth the evening", "What's hot this week, what's prestige forever, what's worth the hours."),
            ("Showtime", "Tonight's main event", "Series for the part of the day you actually look forward to."),
            ("Saved for Now", "Tonight's binge bait", "Pilots that pull you in and finales that earn the season."),
        ],
        [
            ("Late Night", "After-hours picks", "Dark, immersive, and binge-worthy when the house is quiet."),
            ("Past Midnight", "One more episode", "Series for the part of the night that won't let you sleep."),
            ("Witching Hour", "Late-night chapters", "Pull-you-under stories for the quietest part of the day."),
            ("Lights Out", "Headphone series", "Slow, strange, and absorbing. Best with the lights down low."),
            ("Insomnia Lineup", "Worth the lost hour", "Dense plots and rich worlds for when sleep is not happening."),
            ("Late Show", "After the news", "Quiet dramas, sharp thrillers, and series you save for yourself."),
            ("Night Owl", "While the world's asleep", "Series with the patience to match your late-night hours."),
        ],
    ]

    static func requests(now: Date) -> [DiscoveryRail] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let recently = formatter.string(from: now.addingTimeInterval(-90 * 86_400))
        func discover(_ parameters: [String: String]) -> (String, [String: String]) { ("discover/tv", parameters) }
        let plans: [(String, [String: String])] = [
            ("trending/tv/week", [:]), ("tv/popular", [:]), ("tv/on_the_air", [:]), ("tv/top_rated", [:]),
            discover(["vote_average.gte": "8.6", "vote_count.gte": "2000", "sort_by": "vote_average.desc"]),
            discover(["with_genres": "18", "vote_average.gte": "8.2", "vote_count.gte": "1000", "first_air_date.gte": "2018-01-01", "sort_by": "popularity.desc"]),
            discover(["with_genres": "35", "vote_average.gte": "8.0", "vote_count.gte": "700", "sort_by": "vote_average.desc"]),
            discover(["with_genres": "80", "vote_average.gte": "8.0", "vote_count.gte": "600", "sort_by": "vote_count.desc"]),
            discover(["with_genres": "10765", "vote_average.gte": "8.0", "vote_count.gte": "600", "sort_by": "vote_count.desc"]),
            discover(["with_genres": "99", "vote_average.gte": "8.0", "vote_count.gte": "150", "sort_by": "vote_average.desc"]),
            discover(["with_type": "2", "vote_average.gte": "7.8", "vote_count.gte": "300", "sort_by": "vote_count.desc"]),
            discover(["first_air_date.gte": recently, "vote_count.gte": "60", "vote_average.gte": "7.4", "sort_by": "popularity.desc"]),
            discover(["with_origin_country": "GB", "vote_average.gte": "8.0", "vote_count.gte": "300", "sort_by": "vote_average.desc"]),
            discover(["with_origin_country": "KR", "vote_average.gte": "7.8", "vote_count.gte": "120", "sort_by": "popularity.desc"]),
            discover(["with_networks": "49", "vote_count.gte": "250", "sort_by": "vote_average.desc"]),
            discover(["with_networks": "213", "vote_average.gte": "7.8", "vote_count.gte": "400", "sort_by": "vote_average.desc"]),
            discover(["vote_average.gte": "7.8", "vote_count.gte": "500", "first_air_date.lte": "2010-12-31", "sort_by": "vote_count.desc"]),
        ]
        return plans.enumerated().map { index, plan in
            DiscoveryRail(id: "series-hero-\(index)", title: "", kind: "series", path: plan.0, parameters: plan.1, usesRegion: false)
        }
    }

    static func pool(_ sources: [[Media]]) -> [Media] {
        var seen = Set<String>()
        var result: [Media] = []
        for index in 0..<24 {
            for list in sources where list.indices.contains(index) {
                let media = list[index]
                guard let background = media.background, !background.isEmpty, seen.insert(media.id).inserted else { continue }
                result.append(media)
                if result.count == candidateLimit { return result }
            }
        }
        return result
    }

    static func rotationSeed(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let time = schedule(now: now, calendar: calendar)
        return time.day * 4 + time.period
    }

    static func mast(now: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> (kicker: String, title: String, subtitle: String) {
        let time = schedule(now: now, calendar: calendar)
        let variants = mastCopy[time.period]
        return variants[(time.day + time.period * 3) % variants.count]
    }

    private static func schedule(now: Date, calendar: Calendar) -> (day: Int, period: Int) {
        let day = calendar.startOfDay(for: now)
        let jan1 = calendar.date(from: calendar.dateComponents([.year], from: day)) ?? day
        let endOfPreviousYear = calendar.date(byAdding: .day, value: -1, to: jan1) ?? jan1
        // Desktop floors elapsed milliseconds from local midnight on December 31.
        let yearDay = Int((now.timeIntervalSince(endOfPreviousYear) / 86_400).rounded(.down))
        let hour = calendar.component(.hour, from: now)
        let period: Int
        switch hour {
        case 5..<12: period = 0
        case 12..<17: period = 1
        case 17..<22: period = 2
        default: period = 3
        }
        return (yearDay, period)
    }

    static func slides(_ pool: [Media], seed: Int) -> [Media] {
        var shuffled = pool
        var random = DiscoveryFeedRandom.Mulberry32(seed: UInt32(truncatingIfNeeded: seed))
        for index in shuffled.indices.dropFirst().reversed() {
            shuffled.swapAt(index, Int(random.next() * Double(index + 1)))
        }
        return Array(shuffled.prefix(slideCount))
    }

    static func fallback(_ titles: [Media]) -> [Media] {
        Array(pool([titles]).prefix(slideCount))
    }
}

actor ShowsHeroPool {
    static let shared = ShowsHeroPool()
    private struct Cached: Codable {
        let key: String
        let expires: Date
        let titles: [Media]
    }

    private let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("harbor-series-hero-pool.json")
    private var cache: Cached?
    private var restored = false
    private var inflight: [String: Task<[Media], Never>] = [:]

    func slides(configuration: MetadataConfiguration, now: Date) async -> [Media] {
        guard !configuration.tmdbKey.isEmpty else { return [] }
        let key = EBookShelf.hash([configuration.tmdbKey, configuration.language, String(configuration.translateTitles)].joined(separator: "|"))
        if !restored {
            restored = true
            if let cacheURL, let data = try? Data(contentsOf: cacheURL), data.count <= 1024 * 1024 {
                cache = try? JSONDecoder().decode(Cached.self, from: data)
            }
        }
        let titles: [Media]
        if let cache, cache.key == key, cache.expires >= now, cache.titles.count >= ShowsHero.slideCount {
            titles = cache.titles
        } else if let pending = inflight[key] {
            titles = await pending.value
        } else {
            let task = Task { await Self.fetch(configuration: configuration, now: now) }
            inflight[key] = task
            titles = await task.value
            inflight[key] = nil
            if titles.count >= ShowsHero.slideCount {
                let updated = Cached(key: key, expires: now.addingTimeInterval(86_400), titles: titles)
                cache = updated
                if let cacheURL, let data = try? JSONEncoder().encode(updated), data.count <= 1024 * 1024 {
                    try? data.write(to: cacheURL, options: .atomic)
                }
            }
        }
        return ShowsHero.slides(titles, seed: ShowsHero.rotationSeed(now: now))
    }

    private static func fetch(configuration: MetadataConfiguration, now: Date) async -> [Media] {
        let rails = ShowsHero.requests(now: now)
        let service = TMDBService()
        var sources = Array(repeating: [Media](), count: rails.count)
        for offset in stride(from: 0, to: rails.count, by: 4) {
            await withTaskGroup(of: (Int, [Media]).self) { group in
                for index in offset..<min(offset + 4, rails.count) {
                    let rail = rails[index]
                    group.addTask {
                        let items = (try? await service.page(rail, page: 1, configuration: configuration)) ?? []
                        return (index, items)
                    }
                }
                for await (index, items) in group { sources[index] = items }
            }
        }
        return ShowsHero.pool(sources)
    }
}
