import Foundation

/// A person found by a TMDB people search (Desktop `SearchPerson`, lib/search.ts).
struct PersonSearchHit: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    /// TMDB profile path (relative); the photo size is chosen by the view.
    let profile: String?
    let knownFor: String
    let popularity: Double
}

/// One credit of a person (Desktop `PersonCredit`, lib/providers/tmdb/tmdb-people.ts).
struct PersonCreditItem: Hashable, Sendable {
    let id: Int
    /// "movie" or "tv", as TMDB reports it.
    let mediaType: String
    let title: String
    let poster: String?
    let background: String?
    let releaseInfo: String?
    let released: String?
    let imdbRating: String?
    let overview: String
    let character: String?
    let job: String?
    let department: String?
    let popularity: Double
    let voteCount: Int
    let voteAverage: Double
    let episodeCount: Int?
    let order: Int?
}

/// Desktop `PersonDetail`: the person page header plus the sorted cast and crew.
struct PersonProfile: Sendable {
    let id: Int
    let name: String
    let biography: String
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String
    let profilePath: String?
    let cast: [PersonCreditItem]
    let crew: [PersonCreditItem]
}

/// One titled group of the filmography grid, in Desktop's display order.
struct FilmographySection: Identifiable, Hashable, Sendable {
    /// Desktop English title, which may contain `{n}` for the item count.
    let title: String
    let items: [PersonCreditItem]
    var id: String { title }
}

/// TMDB people endpoints for search and the person page. Parsing is pure and takes canned JSON in tests.
struct TMDBPeople: Sendable {
    static let searchLimit = 10
    static let knownForLimit = 12
    static let otherCrewMinimum = 4
    static let otherCrewMaximum = 24
    static let departmentKeys: Set<String> = [
        "Acting", "Art", "Camera", "Costume & Make-Up", "Crew", "Directing",
        "Editing", "Lighting", "Production", "Sound", "Visual Effects", "Writing",
    ]
    private static let creditedJobGroups: [Set<String>] = [
        directorJobs, writerJobs, producerJobs, cinematographyJobs, editingJobs, productionDesignJobs, costumeJobs,
    ]
    private static let directorJobs: Set<String> = ["Director"]
    private static let writerJobs: Set<String> = ["Writer", "Screenplay", "Story", "Teleplay", "Author", "Novel", "Original Story"]
    private static let producerJobs: Set<String> = ["Producer", "Executive Producer"]
    private static let cinematographyJobs: Set<String> = ["Director of Photography", "Cinematography", "Cinematographer"]
    private static let editingJobs: Set<String> = ["Editor", "Editing", "Supervising Editor"]
    private static let productionDesignJobs: Set<String> = ["Production Design", "Production Designer"]
    private static let costumeJobs: Set<String> = ["Costume Design", "Costume Designer"]

    private let http = HTTPClient()

    // MARK: - Network

    /// Desktop's `searchAll` people part: `search/multi`, plus `search/person` for a close name when the query has several words.
    func search(_ query: String, configuration: MetadataConfiguration) async throws -> [PersonSearchHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !configuration.tmdbKey.isEmpty else { return [] }
        var requestConfiguration = configuration
        if !configuration.translateTitles { requestConfiguration.language = "en-US" }
        let multi = try await get("search/multi", parameters: ["query": query, "include_adult": "false"], configuration: requestConfiguration)
        guard case .array = multi["results"] else { throw HarborError(code: "invalid-metadata-response") }
        try Task.checkCancellation()
        var people = Self.people(fromMulti: multi)
        if Self.needsFuzzyFallback(query: query, multi: multi), let token = Self.fuzzyToken(query) {
            var english = configuration
            english.language = "en-US"
            let extra = try? await get("search/person", parameters: ["query": token, "include_adult": "false"], configuration: english)
            people = Self.merging(people, extra: extra ?? .null, query: query)
        }
        try Task.checkCancellation()
        return Self.ranked(people)
    }

    /// Desktop's `tmdbPerson`: the person with `combined_credits`, and the English name when the language has none.
    func person(_ personID: Int, configuration: MetadataConfiguration) async throws -> PersonProfile? {
        guard personID > 0, !configuration.tmdbKey.isEmpty else { return nil }
        let value = try await get("person/\(personID)", parameters: ["append_to_response": "combined_credits,external_ids"], configuration: configuration)
        guard value["id"].integer != nil else { return nil }
        var englishName: String?
        if Self.needsEnglishName(value, language: configuration.language) {
            var english = configuration
            english.language = "en-US"
            let plain = try? await get("person/\(personID)", configuration: english)
            englishName = plain?["name"].string
        }
        return Self.profile(value, englishName: englishName)
    }

    private func get(_ path: String, parameters: [String: String] = [:], configuration: MetadataConfiguration) async throws -> JSONValue {
        guard !configuration.tmdbKey.isEmpty, var url = URLComponents(string: "https://api.themoviedb.org/3/\(path)") else { throw HarborError(code: "metadata-not-configured") }
        url.queryItems = [URLQueryItem(name: "api_key", value: configuration.tmdbKey), URLQueryItem(name: "language", value: configuration.language)] + parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let target = url.string else { throw HarborError(code: "invalid-url") }
        return try await http.json(target, timeout: 15, credentialed: true)
    }

    // MARK: - Search parsing

    /// The person results of a `search/multi` response, in TMDB order (Desktop maps `media_type == "person"`).
    static func people(fromMulti value: JSONValue) -> [PersonSearchHit] {
        value["results"].array.filter { $0["media_type"].string == "person" }.compactMap(personHit)
    }

    static func personHit(_ value: JSONValue) -> PersonSearchHit? {
        guard let id = value["id"].integer, let name = value["name"].string else { return nil }
        let titles = value["known_for"].array.compactMap { item -> String? in
            let title = item["title"].string ?? item["name"].string ?? ""
            return title.isEmpty ? nil : title
        }
        let known = titles.prefix(2).joined(separator: ", ")
        let department = value["known_for_department"].string ?? "Cast"
        return PersonSearchHit(
            id: id,
            name: name,
            profile: value["profile_path"].string,
            knownFor: known.isEmpty ? department : known,
            popularity: value["popularity"].numericValue ?? 0
        )
    }

    /// Desktop's fuzzy condition: at least two words, and either a person was found or no movie or show with a poster was.
    static func needsFuzzyFallback(query: String, multi: JSONValue) -> Bool {
        guard query.split(whereSeparator: { $0.isWhitespace }).count >= 2 else { return false }
        let titlesWithPoster = multi["results"].array.filter { item in
            let type = item["media_type"].string
            return (type == "movie" || type == "tv") && !(item["poster_path"].string ?? "").isEmpty
        }
        return !people(fromMulti: multi).isEmpty || titlesWithPoster.isEmpty
    }

    /// The longest word of at least three characters; the first one wins a tie.
    static func fuzzyToken(_ query: String) -> String? {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init).reduce(nil as String?) { best, word in
            guard word.utf16.count >= 3 else { return best }
            guard let current = best else { return word }
            return word.utf16.count > current.utf16.count ? word : current
        }
    }

    /// Adds the people of a `search/person` response whose name is close to the query and who are not already listed.
    static func merging(_ people: [PersonSearchHit], extra: JSONValue, query: String) -> [PersonSearchHit] {
        var seen = Set(people.map(\.id))
        var output = people
        for item in extra["results"].array {
            guard let hit = personHit(item), !seen.contains(hit.id), nameCloseTo(hit.name, query) else { continue }
            seen.insert(hit.id)
            output.append(hit)
        }
        return output
    }

    /// Desktop's `nameCloseTo`: one contains the other, or the edit distance is at most 20% of the query length (at least 1).
    static func nameCloseTo(_ name: String, _ query: String) -> Bool {
        let candidate = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !wanted.isEmpty else { return false }
        if candidate.contains(wanted) || wanted.contains(candidate) { return true }
        let limit = max(1, Int((Double(wanted.utf16.count) * 0.2).rounded()))
        return editDistance(candidate, wanted) <= limit
    }

    static func editDistance(_ left: String, _ right: String) -> Int {
        let source = Array(left.utf16), target = Array(right.utf16)
        if source.isEmpty { return target.count }
        if target.isEmpty { return source.count }
        var previous = Array(0...target.count)
        for i in 1...source.count {
            var current = [i] + Array(repeating: 0, count: target.count)
            for j in 1...target.count {
                let cost = source[i - 1] == target[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            previous = current
        }
        return previous[target.count]
    }

    /// Desktop's ordering: popularity descending (stable), then the first `searchLimit`.
    static func ranked(_ people: [PersonSearchHit]) -> [PersonSearchHit] {
        let sorted = people.enumerated().sorted { left, right in
            if left.element.popularity != right.element.popularity { return left.element.popularity > right.element.popularity }
            return left.offset < right.offset
        }.map(\.element)
        return Array(sorted.prefix(searchLimit))
    }

    /// The people shown as the photo rail: only those with a profile photo (Desktop `PeopleRow`).
    static func railPeople(_ people: [PersonSearchHit], excluding excluded: Int? = nil) -> [PersonSearchHit] {
        people.filter { $0.profile != nil && $0.id != excluded }
    }

    /// Desktop's `matchPersonForQuery`: the first person, when it has a photo and its name starts or equals the query.
    static func matchPerson(_ people: [PersonSearchHit], query: String) -> PersonSearchHit? {
        guard let first = people.first, first.profile != nil else { return nil }
        let wanted = normalizedName(query)
        let name = normalizedName(first.name)
        guard wanted.count >= 3, !name.isEmpty else { return nil }
        return name == wanted || name.hasPrefix(wanted) || wanted.hasPrefix(name) ? first : nil
    }

    private static func normalizedName(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Person parsing

    /// Desktop's `fetchPerson` naming rule: TMDB falls back to the original-language name, so ask for English.
    static func needsEnglishName(_ value: JSONValue, language: String) -> Bool {
        let base = language.split(separator: "-").first.map { $0.lowercased() } ?? ""
        let name = value["name"].string ?? ""
        let original = value["original_name"].string ?? ""
        return !base.isEmpty && base != "en" && !original.isEmpty && name == original
    }

    static func profile(_ value: JSONValue, englishName: String?) -> PersonProfile? {
        guard let id = value["id"].integer else { return nil }
        let localized = value["name"].string ?? ""
        let name = englishName.flatMap { $0.isEmpty ? nil : $0 } ?? localized
        let cast = stableSorted(dedupe(value["combined_credits"]["cast"].array.compactMap(credit), byMedia: false)) { $0.popularity }
        let crew = stableSorted(value["combined_credits"]["crew"].array.compactMap(credit)) { $0.popularity }
        return PersonProfile(
            id: id,
            name: name,
            biography: value["biography"].string ?? "",
            birthday: nonEmpty(value["birthday"].string),
            deathday: nonEmpty(value["deathday"].string),
            placeOfBirth: nonEmpty(value["place_of_birth"].string),
            knownForDepartment: value["known_for_department"].string ?? "",
            profilePath: value["profile_path"].string,
            cast: cast,
            crew: crew
        )
    }

    static func credit(_ value: JSONValue) -> PersonCreditItem? {
        guard let id = value["id"].integer, let mediaType = value["media_type"].string,
              mediaType == "movie" || mediaType == "tv" else { return nil }
        let released = nonEmpty(value["release_date"].string) ?? nonEmpty(value["first_air_date"].string)
        let average = value["vote_average"].numericValue ?? 0
        return PersonCreditItem(
            id: id,
            mediaType: mediaType,
            title: value["title"].string ?? value["name"].string ?? "",
            poster: photoURL(value["poster_path"].string, size: "w342"),
            background: photoURL(value["backdrop_path"].string, size: "w1280"),
            releaseInfo: released.map { String($0.prefix(4)) },
            released: released,
            imdbRating: average > 0 ? String(format: "%.1f", average) : nil,
            overview: value["overview"].string ?? "",
            character: nonEmpty(value["character"].string),
            job: nonEmpty(value["job"].string),
            department: nonEmpty(value["department"].string),
            popularity: value["popularity"].numericValue ?? 0,
            voteCount: value["vote_count"].integer ?? 0,
            voteAverage: average,
            episodeCount: value["episode_count"].integer,
            order: value["order"].integer
        )
    }

    // MARK: - Filmography rules

    /// Desktop's `dedupe` (by media and job) and `dedupeByMedia`: the higher popularity wins, first position kept.
    static func dedupe(_ credits: [PersonCreditItem], byMedia: Bool) -> [PersonCreditItem] {
        var order: [String] = []
        var best: [String: PersonCreditItem] = [:]
        for credit in credits {
            let key = byMedia ? "\(credit.mediaType):\(credit.id)" : "\(credit.mediaType):\(credit.id):\(credit.job ?? "")"
            if let existing = best[key] {
                if existing.popularity < credit.popularity { best[key] = credit }
            } else {
                best[key] = credit
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    /// Desktop's `isCameoOrGuest`: self-appearances and uncredited or archive roles.
    static func isCameoOrGuest(_ credit: PersonCreditItem) -> Bool {
        let character = (credit.character ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if character.contains("(uncredited)") || character.contains("archive footage") || character.contains("archival footage") { return true }
        let selfWords: Set<String> = ["self", "himself", "herself", "themselves"]
        let selfPrefixes = ["self ", "self -", "himself ", "himself -", "herself ", "herself -"]
        let isSelf = selfWords.contains(character) || selfPrefixes.contains { character.hasPrefix($0) }
        guard isSelf else { return false }
        if credit.mediaType == "tv", (credit.episodeCount ?? 0) >= 8 { return false }
        return true
    }

    /// Desktop's `notableScore`, used to pick the Known For titles.
    static func notableScore(_ credit: PersonCreditItem) -> Double {
        let votes = Double(credit.voteCount)
        let early = (credit.order ?? 99) < 5
        if credit.mediaType == "tv" {
            let episodes = credit.episodeCount ?? 0
            if episodes < 3 { return votes * 0.25 }
            let episodeBoost = min(4.5, 1 + log2(Double(episodes) / 2))
            return votes * episodeBoost * (early ? 1.4 : 1)
        }
        return votes * (early ? 1.25 : 1)
    }

    /// Desktop's Known For pool and order: acting credits, or the crew credits of the person's department; top 12.
    static func knownFor(_ profile: PersonProfile) -> [PersonCreditItem] {
        let department = profile.knownForDepartment
        let pool: [PersonCreditItem]
        if department == "Acting" || department.isEmpty {
            pool = profile.cast.filter { !isCameoOrGuest($0) }
        } else {
            pool = dedupe(profile.crew.filter { $0.department == department }, byMedia: true)
        }
        return Array(stableSorted(pool) { notableScore($0) }.prefix(knownForLimit))
    }

    /// Desktop's `buildFilmography` groups with the default popularity sort, empty groups left out.
    static func filmography(_ profile: PersonProfile) -> [FilmographySection] {
        let crewIn: (Set<String>) -> [PersonCreditItem] = { jobs in
            dedupe(profile.crew.filter { jobs.contains($0.job ?? "") }, byMedia: false)
        }
        let otherAll = dedupe(profile.crew.filter { credit in !creditedJobGroups.contains { $0.contains(credit.job ?? "") } }, byMedia: false)
        let other = otherAll.count > otherCrewMinimum ? Array(otherAll.prefix(otherCrewMaximum)) : []
        let groups: [(String, [PersonCreditItem])] = [
            ("Movies · {n}", profile.cast.filter { $0.mediaType == "movie" }),
            ("TV Shows · {n}", profile.cast.filter { $0.mediaType == "tv" }),
            ("Directing", crewIn(directorJobs)),
            ("Writing", crewIn(writerJobs)),
            ("Producing", crewIn(producerJobs)),
            ("Cinematography", crewIn(cinematographyJobs)),
            ("Editing", crewIn(editingJobs)),
            ("Production Design", crewIn(productionDesignJobs)),
            ("Costume Design", crewIn(costumeJobs)),
            ("Other Work", other),
        ]
        return groups.compactMap { group -> FilmographySection? in
            if group.1.isEmpty { return nil }
            return FilmographySection(title: group.0, items: stableSorted(group.1) { $0.popularity })
        }
    }

    // MARK: - Presentation rules

    /// Desktop's `creditToMeta`, with the Harbor id scheme and `series` for TV, as `makeMedia` does.
    static func media(for credit: PersonCreditItem) -> Media {
        let isMovie = credit.mediaType == "movie"
        var media = Media(id: "tmdb:\(isMovie ? "movie" : "tv"):\(credit.id)", type: isMovie ? "movie" : "series", name: credit.title)
        media.poster = credit.poster
        media.background = credit.background
        media.description = credit.overview
        media.released = credit.released
        media.releaseInfo = credit.releaseInfo
        media.imdbRating = credit.imdbRating
        if credit.imdbRating != nil { media.ratingSource = "TMDB" }
        return media
    }

    /// Desktop's film card caption: the role (character, else job), then the year, joined with a middle dot.
    static func caption(_ credit: PersonCreditItem) -> String {
        let role = (credit.character ?? credit.job ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return [role, credit.releaseInfo ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Age in whole years at the death date, or today's date (Desktop `calcAge`). Dates are `yyyy-MM-dd`.
    static func age(birthday: String, deathday: String?, now: Date, calendar: Calendar = TMDBPeople.utcCalendar) -> Int? {
        guard let born = dateParts(birthday) else { return nil }
        let end: (year: Int, month: Int, day: Int)
        if let deathday = deathday, !deathday.isEmpty {
            guard let died = dateParts(deathday) else { return nil }
            end = died
        } else {
            let today = calendar.dateComponents([.year, .month, .day], from: now)
            guard let year = today.year, let month = today.month, let day = today.day else { return nil }
            end = (year, month, day)
        }
        var years = end.year - born.year
        if end.month < born.month || (end.month == born.month && end.day < born.day) { years -= 1 }
        return years
    }

    /// A `yyyy-MM-dd` date in the user's locale, or the input when it does not parse (Desktop `fmtDate`).
    static func displayDate(_ text: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(secondsFromGMT: 0)
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: String(text.prefix(10))) else { return text }
        let output = DateFormatter()
        output.dateStyle = .long
        output.timeStyle = .none
        output.timeZone = TimeZone(secondsFromGMT: 0)
        return output.string(from: date)
    }

    static func photoURL(_ path: String?, size: String) -> String? {
        guard let path, !path.isEmpty else { return nil }
        return "https://image.tmdb.org/t/p/\(size)\(path)"
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    // MARK: - Helpers

    private static func dateParts(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let parts = String(text.prefix(10)).split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return (year, month, day)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        return text
    }

    /// Descending by score, keeping the input order for ties (JS `sort` is stable).
    private static func stableSorted(_ credits: [PersonCreditItem], by score: (PersonCreditItem) -> Double) -> [PersonCreditItem] {
        credits.enumerated().sorted { left, right in
            let a = score(left.element), b = score(right.element)
            if a != b { return a > b }
            return left.offset < right.offset
        }.map(\.element)
    }
}
