import Foundation

enum DiscoveryDailyEndpoint: Equatable, Sendable {
    case discover
    case trending
    case awards
    case cinemeta(kind: String, genre: String?)
}

struct DiscoveryDailyRow: Identifiable, Sendable {
    let key: String
    let rail: DiscoveryRail
    let endpoint: DiscoveryDailyEndpoint
    let kicker: String?
    let floorRelaxed: [String: String]
    let pageBase: Int
    var id: String { key }
}

/// Native counterpart to Desktop 0.9.132 `selectDailyRows` and its daily catalog.
enum DiscoveryDailyFeed {
    static let rowCount = 14
    private static let standardAnchors: Set<String> = ["trending", "critically_loved", "award_winning"]
    private static let decades: [(label: String, weightKey: String, from: String, to: String)] = [
        ("70s", "1970s", "1970-01-01", "1979-12-31"),
        ("80s", "1980s", "1980-01-01", "1989-12-31"),
        ("90s", "1990s", "1990-01-01", "1999-12-31"),
        ("2000s", "2000s", "2000-01-01", "2009-12-31"),
        ("2010s", "2010s", "2010-01-01", "2019-12-31"),
    ]
    private static let languages: [(code: String, title: String)] = [
        ("fr", "French Cinema"), ("ja", "Japanese Cinema"), ("ko", "Korean Cinema"), ("es", "Spanish-Language"),
        ("it", "Italian Cinema"), ("de", "German Cinema"), ("sv", "Swedish Cinema"), ("da", "Danish Cinema"),
        ("zh", "Chinese Cinema"), ("hi", "Indian Cinema"), ("pt", "Portuguese-Language"), ("ru", "Russian Cinema"),
    ]
    private static let languageCountries: [String: String] = [
        "ja": "JP", "ko": "KR", "fr": "FR", "it": "IT", "de": "DE", "sv": "SE", "da": "DK", "zh": "CN", "hi": "IN", "ru": "RU",
    ]
    private static let countryTitles: [String: String] = [
        "fr": "French", "ja": "Japanese", "ko": "Korean", "es": "Spanish-Language", "it": "Italian", "de": "German",
        "sv": "Swedish", "da": "Danish", "zh": "Chinese", "hi": "Indian", "pt": "Portuguese-Language", "ru": "Russian",
    ]
    private static let movieToTV: [Int: Int] = [
        28: 10759, 12: 10759, 878: 10765, 14: 10765, 10752: 10768, 16: 16, 35: 35, 80: 80, 99: 99,
        18: 18, 10751: 10751, 9648: 9648, 37: 37,
    ]

    static func rows(
        tmdbKey: String,
        affinity: DiscoveryPreferences.Affinity,
        region: String,
        enabledServices: [StreamingServiceDefinition],
        count: Int = rowCount,
        now: Date = Date(),
        recent: Set<String> = []
    ) -> [DiscoveryDailyRow] {
        let base = DiscoveryFeedRandom.dayIndex(now)
        guard !tmdbKey.isEmpty else { return fallbackRows(now: now) }

        var candidates: [DiscoveryDailyRow] = []
        let genres = weightedGenres(affinity: affinity.genres, base: base, salt: "genre", count: 3)
        for name in genres {
            guard let id = genreID(name) else { continue }
            candidates.append(movieRow(key: "top_genre:\(name)", title: "Top Rated {genre}", variables: ["genre": text(name)], floor: DiscoveryGenreRules.movieFloor(genreID: id, floor: ["vote_average.gte": "6.8", "vote_count.gte": "300", "sort_by": "vote_average.desc"]), base: base))
        }

        let since = dateString(now.addingTimeInterval(-540 * 86_400))
        for name in weightedGenres(affinity: affinity.genres, base: mix(base, 2), salt: "genre", count: 2) {
            guard let id = genreID(name) else { continue }
            candidates.append(movieRow(key: "fresh_genre:\(name)", title: "New in {genre}", variables: ["genre": text(name)], floor: DiscoveryGenreRules.movieFloor(genreID: id, floor: ["primary_release_date.gte": since, "vote_count.gte": "80", "vote_average.gte": "6.3", "sort_by": "popularity.desc"]), base: base))
        }

        let hasTaste = !affinity.genres.isEmpty || !affinity.decades.isEmpty || !affinity.languages.isEmpty
        if hasTaste {
            let picked = weightedGenres(affinity: affinity.genres, base: mix(base, 4), salt: "genre", count: 4)
            for index in stride(from: 0, to: min(picked.count - 1, 3), by: 2) where candidates.filter({ $0.key.hasPrefix("genre_blend:") }).count < 2 {
                guard let first = genreID(picked[index]), let second = genreID(picked[index + 1]) else { continue }
                let params = ["with_genres": "\(first),\(second)", "with_runtime.gte": "70", "vote_average.gte": "6.6", "vote_count.gte": "200", "sort_by": "vote_average.desc"]
                candidates.append(movieRow(key: "genre_blend:\(picked[index])_\(picked[index + 1])", title: "{genreA} + {genreB}", variables: ["genreA": text(picked[index]), "genreB": text(picked[index + 1])], floor: params, base: base))
            }
        }

        for decade in weightedDecades(affinity: affinity.decades, base: base, salt: "decade", count: 2) {
            let params = ["primary_release_date.gte": decade.from, "primary_release_date.lte": decade.to, "vote_average.gte": "7.2", "vote_count.gte": "200", "vote_count.lte": "3000", "with_runtime.gte": "70", "sort_by": "vote_average.desc"]
            candidates.append(movieRow(key: "hidden_gem_decade:\(decade.label)", title: "Hidden Gems from the {decade}", variables: ["decade": text(decade.label)], kicker: "Quietly great, {decade}", kickerVariables: ["decade": text(decade.label)], floor: params, base: base))
        }
        for decade in weightedDecades(affinity: affinity.decades, base: mix(base, 7), salt: "decade", count: 1) {
            let params = ["primary_release_date.gte": decade.from, "primary_release_date.lte": decade.to, "vote_average.gte": "7.5", "vote_count.gte": "800", "sort_by": "vote_average.desc"]
            candidates.append(movieRow(key: "best_decade:\(decade.label)", title: "Best of the {decade}", variables: ["decade": text(decade.label)], floor: params, base: base))
        }

        if let language = weightedLanguages(affinity: affinity.languages, base: base, salt: "lang", count: 1).first {
            candidates.append(movieRow(key: "language:\(language.code)", title: language.title, kicker: "Top rated abroad", floor: ["with_original_language": language.code, "vote_average.gte": "7.0", "vote_count.gte": "150", "sort_by": "vote_average.desc"], base: base))
        }
        if let language = weightedLanguages(affinity: affinity.languages, base: mix(base, 11), salt: "lang", count: 2).first(where: { languageCountries[$0.code] != nil }),
           let country = languageCountries[language.code], let adjective = countryTitles[language.code] {
            candidates.append(movieRow(key: "country:\(country)", title: "{country} Films", variables: ["country": text(adjective)], kicker: "From the region", floor: ["with_origin_country": country, "vote_average.gte": "7.0", "vote_count.gte": "120", "sort_by": "vote_average.desc"], base: base))
        }
        if let name = weightedGenres(affinity: affinity.genres, base: mix(base, 3), salt: "genre", count: 1).first {
            var params = ["with_runtime.lte": "90", "with_runtime.gte": "70", "vote_average.gte": "7.0", "vote_count.gte": "250", "sort_by": "vote_average.desc"]
            if let id = genreID(name) { params["with_genres"] = String(id) }
            candidates.append(movieRow(key: "runtime_short:\(name)", title: "A Short Tonight: {genre} Under 90", variables: ["genre": text(name)], floor: params, base: base))
        }

        let tvNames = weightedGenres(affinity: affinity.genres, base: mix(base, 5), salt: "genre", count: 6)
        var usedTV = Set<Int>()
        var tvRows = 0
        for name in tvNames where tvRows < 3 {
            guard let movieID = genreID(name), let tvID = movieToTV[movieID], usedTV.insert(tvID).inserted else { continue }
            let fresh = tvRows == 1
            let params: [String: String] = fresh
                ? ["with_genres": String(tvID), "first_air_date.gte": since, "vote_count.gte": "60", "vote_average.gte": "6.8", "sort_by": "popularity.desc"]
                : ["with_genres": String(tvID), "vote_average.gte": "7.5", "vote_count.gte": "200", "sort_by": "vote_average.desc"]
            let title = fresh ? "New {genre} Series" : "Top Rated {genre} Series"
            let kicker = fresh ? "Fresh on TV" : "Critically acclaimed TV"
            let rail = makeRow(key: "tv_genre:\(fresh ? "new" : "top"):\(name)", title: title, variables: ["genre": text(name)], kicker: kicker, kind: "series", floor: params, base: base)
            candidates.append(rail); tvRows += 1
        }

        if !enabledServices.isEmpty {
            var providerRNG = DiscoveryFeedRandom.generator(base: base, salt: "provider")
            let serviceIndex = min(enabledServices.count - 1, Int(providerRNG.next() * Double(enabledServices.count)))
            let service = enabledServices[serviceIndex]
            let name = weightedGenres(affinity: affinity.genres, base: mix(base, 13), salt: "genre", count: 1).first
            var params = ["with_watch_providers": service.providers, "watch_region": region.isEmpty ? "US" : region, "vote_count.gte": "80", "sort_by": "popularity.desc"]
            if let name, let id = genreID(name) { params["with_genres"] = String(id) }
            candidates.append(movieRow(key: "provider:\(service.key)", title: "On {service}, picked for you", variables: ["service": text(service.name)], floor: params, base: base))
        }

        candidates += anchors(base: base, now: now)
        var keys = Set<String>()
        let unique = candidates.filter { keys.insert($0.key).inserted }
        return DiscoveryDailyRows.order(unique, key: \.key, base: base, count: count, recent: recent)
    }

    static func signature(
        tmdbKey: String,
        tasteRevision: Int,
        region: String,
        enabledServices: [StreamingServiceDefinition],
        preferredLanguages: [String],
        metadataLanguage: String,
        feedLocaleBias: Bool,
        uiLanguage: String,
        translateTitles: Bool,
        owner: String,
        now: Date = Date()
    ) -> String {
        let value = [String(DiscoveryFeedRandom.dayIndex(now)), tmdbKey, String(tasteRevision), region,
                     enabledServices.map(\.key).sorted().joined(separator: ","), preferredLanguages.joined(separator: ","),
                     metadataLanguage, feedLocaleBias ? "1" : "0", uiLanguage, String(translateTitles)].joined(separator: "#")
        return EBookShelf.hash(value + "#" + owner)
    }

    static func localizeFloor(_ floor: [String: String], kind: String, enabled: Bool, localeCodes: Set<String>, region: String) -> [String: String] {
        guard enabled, kind == "movie", !localeCodes.isEmpty, !region.isEmpty,
              floor["with_original_language"] == nil, floor["with_origin_country"] == nil else { return floor }
        var result = floor
        result["region"] = region
        return result
    }

    struct Filter: Sendable {
        let downvotes: [DiscoveryAffinityRules.Downvote]
        let upvoted: Set<String>
        let history: DailyHeroRotation.RecentMovies
        let affinity: DiscoveryPreferences.Affinity
        let locale: DiscoveryAffinityRules.LocaleBias

        func eligible(_ items: [Media]) -> [Media] {
            let filtered = DiscoveryAffinityRules.excludingDownvoted(items.filter { $0.poster?.isEmpty == false }, downvotes: downvotes)
            var seen: [Media] = [], fresh: [Media] = []
            var ids = Set<String>()
            for media in filtered where ids.insert(media.id).inserted {
                if upvoted.contains(media.id) || history.contains(media) { seen.append(media) }
                else { fresh.append(media) }
            }
            return fresh + seen
        }
    }

    static func deduplicatedRows(rows: [DiscoveryDailyRow], loaded: [String: [Media]], featuredIDs: Set<String>, minimum: Int = 16) -> [String: [Media]] {
        let order = rows.map(\.key)
        let priority = [DiscoveryDailyRows.topRatedAnchor, DiscoveryDailyRows.awardsAnchor].compactMap { prefix in
            order.first { $0.hasPrefix(prefix + ":") }
        }
        let claimOrder = priority + order.filter { !priority.contains($0) }
        var seen = featuredIDs
        var output: [String: [Media]] = [:]
        for key in claimOrder {
            guard let raw = loaded[key] else { continue }
            var taken: [Media] = []
            var takenIDs = Set<String>()
            for media in raw where media.poster?.isEmpty == false && !seen.contains(media.id) {
                guard takenIDs.insert(media.id).inserted else { continue }
                taken.append(media); seen.insert(media.id)
            }
            if taken.count < minimum {
                for media in raw where media.poster?.isEmpty == false && taken.count < minimum && !featuredIDs.contains(media.id) {
                    if takenIDs.insert(media.id).inserted { taken.append(media) }
                }
            }
            if taken.count < minimum {
                for media in raw where media.poster?.isEmpty == false && taken.count < minimum {
                    if takenIDs.insert(media.id).inserted { taken.append(media) }
                }
            }
            output[key] = taken
        }
        return output
    }

    static func fetch(_ row: DiscoveryDailyRow, page: Int, configuration: MetadataConfiguration, filter: Filter) async throws -> [Media] {
        switch row.endpoint {
        case .cinemeta(let kind, let genre):
            guard page == 1 else { return [] }
            let segment = genre.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }.map { "/genre=" + $0 } ?? ""
            let response = try await HTTPClient().json("https://v3-cinemeta.strem.io/catalog/\(kind)/top\(segment).json", timeout: 12)
            guard case .array(let metas) = response["metas"] else { throw HarborError(code: "catalog-unavailable") }
            return filter.eligible(metas.compactMap { Media.parse($0, kind: kind) })
        case .awards:
            return []
        case .discover, .trending:
            let number = row.pageBase + page - 1
            let locale = filter.locale
            var rail = row.rail
            if row.endpoint == .discover {
                rail.parameters = localizeFloor(rail.parameters, kind: rail.kind, enabled: locale.penalty > 0,
                                                localeCodes: locale.codes, region: configuration.region)
            }
            let primary = try await TMDBService().page(rail, page: number, configuration: configuration, includeRegion: false)
            var eligible = filter.eligible(primary)
            if row.endpoint == .discover, eligible.count < 8, rail.parameters != row.floorRelaxed {
                try Task.checkCancellation()
                rail.parameters = row.floorRelaxed
                let relaxed = try? await TMDBService().page(rail, page: number, configuration: configuration, includeRegion: false)
                try Task.checkCancellation()
                var ids = Set(eligible.map(\.id))
                eligible += filter.eligible(relaxed ?? []).filter { ids.insert($0.id).inserted }
            }
            return DiscoveryAffinityRules.ranked(eligible, affinity: filter.affinity, locale: locale)
        }
    }

    private static func anchors(base: Int, now: Date) -> [DiscoveryDailyRow] {
        let animation = CustomCalendar.movieGenres.first { $0.0 == "Animation" }?.1 ?? 16
        let documentary = CustomCalendar.movieGenres.first { $0.0 == "Documentary" }?.1 ?? 99
        let recent = ["primary_release_date.gte": dateString(now.addingTimeInterval(-90 * 86_400)), "primary_release_date.lte": dateString(now)]
        return [
            makeRow(key: "trending:_", title: "Trending This Week", kicker: "What people are watching", kind: "movie", path: "trending/movie/week", floor: ["sort_by": "popularity.desc"], endpoint: .trending, base: base),
            awardRow(base: base),
            movieRow(key: "critically_loved:_", title: "Top Rated", kicker: "Critically acclaimed, all time", floor: ["vote_average.gte": "8.0", "vote_count.gte": "1000", "with_runtime.gte": "70", "sort_by": "vote_average.desc"], base: base),
            movieRow(key: "hidden_gems_anchor:_", title: "Highly Rated, Quietly Loved", kicker: "High score, low fanfare", floor: ["vote_average.gte": "7.2", "vote_count.gte": "300", "vote_count.lte": "3500", "with_runtime.gte": "70", "sort_by": "vote_average.desc"], base: base),
            movieRow(key: "cult:_", title: "Cult Classics", kicker: "Beloved, slightly forgotten", floor: ["primary_release_date.lte": "1999-12-31", "vote_average.gte": "7.4", "vote_count.gte": "300", "vote_count.lte": "5000", "sort_by": "vote_average.desc"], base: base),
            movieRow(key: "animated:_", title: "Animated, For Grown-Ups", kicker: "Beyond the kids' shelf", floor: ["with_genres": String(animation), "vote_average.gte": "7.4", "vote_count.gte": "500", "sort_by": "vote_average.desc"], base: base),
            movieRow(key: "documentaries:_", title: "Documentaries Worth Your Night", kicker: "Highly rated, real life", floor: ["with_genres": String(documentary), "vote_average.gte": "7.5", "vote_count.gte": "200", "sort_by": "vote_average.desc"], base: base),
            movieRow(key: "recently_released:_", title: "Recently Released", kicker: "Last 90 days", floor: recent.merging(["vote_count.gte": "50", "with_runtime.gte": "70", "sort_by": "popularity.desc"]) { _, new in new }, base: base),
        ]
    }

    static func awardRow(base: Int) -> DiscoveryDailyRow {
        makeRow(key: "award_winning:_", title: "Award Winning", kicker: "Best Picture winners",
                kind: "movie", endpoint: .awards, base: base)
    }

    private static func fallbackRows(now: Date) -> [DiscoveryDailyRow] {
        let genres = ["Drama", "Comedy", "Action", "Crime", "Sci-Fi", "Thriller", "Horror", "Romance"]
        let picked = fallbackGenrePicks(genres, now: now, count: 5)
        return [
            makeRow(key: "fallback_cinemeta_movies", title: "Top Movies", kind: "movie", endpoint: .cinemeta(kind: "movie", genre: nil)),
            makeRow(key: "fallback_cinemeta_series", title: "Top Series", kind: "series", endpoint: .cinemeta(kind: "series", genre: nil)),
        ] + picked.map { name in
            makeRow(key: "fallback_cinemeta_\(name)", title: "Top {genre}", variables: ["genre": text(name)], kind: "movie", endpoint: .cinemeta(kind: "movie", genre: name))
        }
    }

    private static func fallbackGenrePicks(_ values: [String], now: Date, count: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        let seed = (parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
        var state = UInt32(truncatingIfNeeded: seed) & 0x7fff_ffff
        var result = values
        if result.count > 1 {
            for index in stride(from: result.count - 1, to: 0, by: -1) {
                // The source multiplies JavaScript Numbers before masking. Preserve the Double rounding.
                let product = Double(state) * 1_103_515_245
                state = UInt32(truncatingIfNeeded: UInt64(product + 12_345)) & 0x7fff_ffff
                let other = Int(state % UInt32(index + 1))
                result.swapAt(index, other)
            }
        }
        return Array(result.prefix(min(count, result.count)))
    }

    private static func weightedGenres(affinity: [String: Double], base: Int, salt: String, count: Int) -> [String] {
        var rng = DiscoveryFeedRandom.generator(base: base, salt: salt)
        return DiscoveryGenreRules.weightedGenres(affinity: affinity, rng: &rng, count: count)
    }

    private static func weightedDecades(affinity: [String: Double], base: Int, salt: String, count: Int) -> [(label: String, weightKey: String, from: String, to: String)] {
        var rng = DiscoveryFeedRandom.generator(base: base, salt: salt)
        return DiscoveryDailyRows.weightedPick(decades, weight: { 1 + DiscoveryGenreRules.lambda * DiscoveryDailyRows.normalizedAffinity(affinity, key: $0.weightKey) }, rng: &rng, count: count)
    }

    private static func weightedLanguages(affinity: [String: Double], base: Int, salt: String, count: Int) -> [(code: String, title: String)] {
        var rng = DiscoveryFeedRandom.generator(base: base, salt: salt)
        return DiscoveryDailyRows.weightedPick(languages, weight: { 1 + DiscoveryGenreRules.lambda * DiscoveryDailyRows.normalizedAffinity(affinity, key: $0.code) }, rng: &rng, count: count)
    }

    private static func movieRow(key: String, title: String, variables: [String: String] = [:], kicker: String? = nil, kickerVariables: [String: String] = [:], floor: [String: String], base: Int) -> DiscoveryDailyRow {
        makeRow(key: key, title: title, variables: variables, kicker: kicker, kickerVariables: kickerVariables, kind: "movie", floor: floor, base: base)
    }

    private static func makeRow(key: String, title: String, variables: [String: String] = [:], kicker: String? = nil, kickerVariables: [String: String] = [:], kind: String = "movie", path: String? = nil, floor: [String: String] = [:], endpoint: DiscoveryDailyEndpoint = .discover, base: Int = 0) -> DiscoveryDailyRow {
        let rail = DiscoveryRail(id: key, title: DesktopInterfaceText.value(title, variables: variables), kind: kind, path: path ?? "discover/\(kind == "movie" ? "movie" : "tv")", parameters: floor)
        let relaxed = endpoint == .trending ? floor : DiscoveryGenreRules.relax(floor)
        var paging = DiscoveryFeedRandom.generator(base: base, salt: DiscoveryFeedRandom.hash(key))
        let pageBase = standardAnchors.contains(String(key.split(separator: ":").first ?? "")) ? 1 : 1 + Int(paging.next() * 3)
        let subtitle = kicker.map { DesktopInterfaceText.value($0, variables: kickerVariables) }
        return DiscoveryDailyRow(key: key, rail: rail, endpoint: endpoint, kicker: subtitle, floorRelaxed: relaxed, pageBase: pageBase)
    }

    private static func genreID(_ name: String) -> Int? { CustomCalendar.movieGenres.first { $0.0 == name }?.1 }
    private static func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    private static func mix(_ base: Int, _ salt: UInt32) -> Int { Int(DiscoveryFeedRandom.mixSeed(base, salt)) }
    private static func dateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

@MainActor
enum DiscoveryDailyFeedHistory {
    private struct Entry: Codable { var day: Int; var keys: [String] }
    private static func key(_ owner: String) -> String { "harbor.discover.rows.v1." + EBookShelf.hash(owner) }
    private static func read(_ owner: String) -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key(owner)), let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return Array(entries.suffix(10))
    }
    static func recentKeys(owner: String, base: Int) -> Set<String> {
        Set(read(owner).filter { $0.day != base }.flatMap(\.keys))
    }
    static func record(owner: String, base: Int, row: String) {
        var entries = read(owner)
        if let index = entries.firstIndex(where: { $0.day == base }) {
            guard !entries[index].keys.contains(row) else { return }
            entries[index].keys.append(row)
        } else { entries.append(Entry(day: base, keys: [row])) }
        let trimmed = Array(entries.suffix(10))
        if let data = try? JSONEncoder().encode(trimmed) { UserDefaults.standard.set(data, forKey: key(owner)) }
    }
}
