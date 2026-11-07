import Foundation

/// Desktop's `parseEpisodeSpan` result (`src/lib/episode-span.ts`).
struct LocalEpisodeSpan: Equatable, Sendable {
    let season: Int
    let episode: Int
    let episodeEnd: Int
}

/// Desktop's `parseFilename` result (`src/lib/local-library.ts`), without any TMDB lookup.
struct LocalParsedFilename: Equatable, Sendable {
    let title: String
    let year: Int?
    let isShow: Bool
    let season: Int?
    let episode: Int?
    let episodeEnd: Int?
    let resolution: String?

    /// `S01E02`, or `S01E02\u{2013}E03` for a two-episode file, as Desktop's `episodeSpanLabel` formats it.
    var episodeLabel: String? {
        guard let season = season, let episode = episode else { return nil }
        let start = "S" + Self.twoDigits(season) + "E" + Self.twoDigits(episode)
        guard let episodeEnd = episodeEnd, episodeEnd > episode else { return start }
        return start + "\u{2013}E" + Self.twoDigits(episodeEnd)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0" + String(value) : String(value)
    }
}

/// One file in the local library. The bookmark is the only way back to the file: Harbor never copies it.
struct LocalLibraryRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let filename: String
    let bookmark: Data
    let size: Int64?
    let addedAt: Date
    /// Name of the folder the person picked, or nil for an individually picked file.
    let folder: String?
    /// Path inside the picked folder, or the filename for an individually picked file.
    let relativePath: String

    var parsed: LocalParsedFilename { LocalFilenameParser.parse(filename) }

    func withBookmark(_ data: Data) -> LocalLibraryRecord {
        LocalLibraryRecord(id: id, filename: filename, bookmark: data, size: size, addedAt: addedAt, folder: folder, relativePath: relativePath)
    }
}

/// Keys for the local-library preferences. Each one is listed in `ProfileSettingsStore.keys`, so it is kept per profile.
enum LocalLibraryPreferences {
    /// Desktop's `localMinFileSizeMb` (`src/lib/settings/defaults.ts`, default 50).
    static let minimumSizeKey = "localMinFileSizeMb"
    static let defaultMinimumSizeMB = 50
    /// Desktop's `localEpisodeSortDesc` (default false).
    static let episodeSortKey = "localEpisodeSortDesc"
    /// No Desktop key: Desktop keeps the sort in session filters (`local-tab.tsx`, defaults `added` and `desc`).
    static let sortKey = "localLibrary.sort"
    static let sortDescendingKey = "localLibrary.sortDescending"
}

enum LocalLibrarySortKey: String, CaseIterable, Identifiable, Sendable {
    case added, title, year
    var id: String { rawValue }
    /// Desktop's `SortMenu` labels (`src/views/library/local-tab/toolbar.tsx`).
    var desktopTitle: String {
        switch self {
        case .added: return "Date added"
        case .title: return "Title"
        case .year: return "Year"
        }
    }
}

struct LocalLibraryMovie: Identifiable, Sendable {
    let key: String
    let title: String
    let year: Int?
    /// Every file for this movie, best first. Desktop collapses versions the same way (`groupLocal`).
    let versions: [LocalLibraryRecord]
    var id: String { key }
    var added: Date { versions.map(\.addedAt).max() ?? Date.distantPast }
}

struct LocalLibrarySeason: Identifiable, Sendable {
    let number: Int
    let episodes: [LocalLibraryRecord]
    var id: Int { number }
}

struct LocalLibraryShow: Identifiable, Sendable {
    let key: String
    let title: String
    let year: Int?
    let seasons: [LocalLibrarySeason]
    var id: String { key }
    var added: Date {
        var newest = Date.distantPast
        for season in seasons {
            for episode in season.episodes where episode.addedAt > newest { newest = episode.addedAt }
        }
        return newest
    }
}

enum LocalLibraryGroup: Identifiable, Sendable {
    case movie(LocalLibraryMovie)
    case show(LocalLibraryShow)

    var id: String {
        switch self {
        case .movie(let movie): return "movie-" + movie.key
        case .show(let show): return "show-" + show.key
        }
    }

    var title: String {
        switch self {
        case .movie(let movie): return movie.title
        case .show(let show): return show.title
        }
    }

    var year: Int? {
        switch self {
        case .movie(let movie): return movie.year
        case .show(let show): return show.year
        }
    }

    var added: Date {
        switch self {
        case .movie(let movie): return movie.added
        case .show(let show): return show.added
        }
    }
}

enum LocalFilenameParser {
    /// Desktop's `VIDEO_EXTS` (`src-tauri/src/local_lib.rs`).
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "mov", "avi", "wmv", "webm", "ts", "m2ts", "mpg", "mpeg", "flv", "ogv"]

    static func isVideo(_ filename: String) -> Bool {
        videoExtensions.contains((filename as NSString).pathExtension.lowercased())
    }

    /// Desktop strips only a video extension before parsing; any other name is parsed whole.
    static func stem(_ filename: String) -> String {
        let name = filename as NSString
        guard videoExtensions.contains(name.pathExtension.lowercased()) else { return filename }
        return name.deletingPathExtension
    }

    /// Desktop's `parseEpisodeSpan`: only explicit, same-season notation counts.
    static func episodeSpan(_ text: String) -> LocalEpisodeSpan? {
        if firstMatch(crossSeasonPattern, in: text) != nil { return nil }
        for pattern in rangePatterns {
            guard let match = firstMatch(pattern, in: text) else { continue }
            guard let season = match.number(1), let episode = match.number(2), let end = match.number(3) else { return nil }
            guard season > 0, episode > 0, end == episode + 1 else { return nil }
            return LocalEpisodeSpan(season: season, episode: episode, episodeEnd: end)
        }
        for pattern in singlePatterns {
            guard let match = firstMatch(pattern, in: text), let season = match.number(1), let episode = match.number(2) else { continue }
            if season > 0 && episode > 0 {
                return LocalEpisodeSpan(season: season, episode: episode, episodeEnd: episode)
            }
        }
        return nil
    }

    /// Desktop's `parseFilename`.
    static func parse(_ filename: String) -> LocalParsedFilename {
        let stem = stem(filename)
        let span = episodeSpan(stem)
        let tv = firstMatch(tvPattern, in: stem)
        let extras: RegexMatch? = (span == nil && tv == nil) ? firstMatch(extrasPattern, in: stem) : nil
        var season: Int?
        var episode: Int?
        if let extras = extras {
            season = 0
            episode = extras.number(1)
        } else if let span = span {
            season = span.season
            episode = span.episode
        } else if let tv = tv {
            season = tv.number(1) ?? tv.number(3) ?? tv.number(5)
            episode = tv.number(2) ?? tv.number(4) ?? tv.number(6)
        }
        let yearMatch = firstMatch(yearPattern, in: stem)
        let resolution = firstMatch(resolutionPattern, in: stem)?.string(1)?.lowercased()
        var title = stem
        if let tv = tv { title = prefix(title, upTo: tv.start) }
        if let extras = extras { title = prefix(title, upTo: extras.start) }
        if let yearMatch = yearMatch, yearMatch.start < title.utf16.count {
            title = prefix(title, upTo: yearMatch.start)
        }
        title = cleanTitle(title)
        if title.isEmpty { title = stem }
        let isShow = span != nil || tv != nil || extras != nil
        return LocalParsedFilename(
            title: title,
            year: yearMatch?.number(1),
            isShow: isShow,
            season: season,
            episode: episode,
            episodeEnd: span?.episodeEnd ?? episode,
            resolution: resolution
        )
    }

    // MARK: - Patterns (Desktop's regexes, compiled once; all case-insensitive)

    private static let crossSeasonPattern = compile(#"(?:^|[^a-z0-9])s\d{1,3}[ ._-]*e\d{1,4}\s*-\s*s\d{1,3}[ ._-]*e\d{1,4}(?!\d)"#)
    private static let rangePatterns: [NSRegularExpression?] = [
        compile(#"(?:^|[^a-z0-9])s(\d{1,3})[ ._-]*e(\d{1,4})[ ._-]*e(\d{1,4})(?!\d)"#),
        compile(#"(?:^|[^a-z0-9])s(\d{1,3})[ ._-]*e(\d{1,4})\s*-\s*e(\d{1,4})(?!\d)"#),
        compile(#"(?:^|[^a-z0-9])s(\d{1,3})[ ._-]*e(\d{1,4})\s*-\s*(\d{1,4})(?!\d)"#),
        compile(#"(?:^|[^a-z0-9])(\d{1,3})x(\d{1,4})\s*-\s*(\d{1,4})(?!\d)"#),
    ]
    private static let singlePatterns: [NSRegularExpression?] = [
        compile(#"(?:^|[^a-z0-9])s(\d{1,3})[ ._-]*e(\d{1,4})(?!\d)"#),
        compile(#"(?:^|[^a-z0-9])(\d{1,3})x(\d{1,4})(?!\d)"#),
        compile(#"(?:^|[^a-z0-9])season[ ._-]*(\d{1,3})[ ._-]*(?:episode|ep)[ ._-]*(\d{1,4})(?!\d)"#),
    ]
    private static let tvPattern = compile(#"\bs(\d{1,2})[\s._-]*e(\d{1,3})(?!\d)|\b(\d{1,2})x(\d{1,3})(?!\d)|\bseason[\s._-]*(\d{1,2})[\s._-]*(?:episode|ep)[\s._-]*(\d{1,3})(?!\d)"#)
    private static let extrasPattern = compile(#"(?:^|[\s._-])s(\d{1,2})[\s._-]*(?:extras?|bonus)(?:[\s._-]|$)"#)
    private static let yearPattern = compile(#"\b(19\d{2}|20\d{2})\b"#)
    private static let resolutionPattern = compile(#"\b(2160p|1080p|720p|480p|4k|uhd)\b"#)
    private static let noisePattern = compile(#"\b("# + noiseWords.joined(separator: "|") + #")\b"#)
    /// Desktop's `NOISE` list, in the same order (alternation order matters, e.g. `hdr` before `hdr10`).
    private static let noiseWords = [
        "1080p", "720p", "2160p", "4k", "uhd", "hdr", "hdr10", "dv", "bluray", "bdrip", "brrip", "webrip", "web-dl", "webdl",
        "hdtv", "dvdrip", "remux", "x264", "x265", "h264", "h265", "hevc", "av1", "10bit", "atmos", "ddp", "dts", "ac3", "aac",
        "yify", "yts", "rarbg", "fgt", "evo", "psa",
    ]
    private static let separatorsPattern = compile(#"[._]+"#)
    private static let bracketGroupPattern = compile(#"(?:\[|\(|\{).*?(?:\]|\)|\})"#)
    private static let bracketCharPattern = compile(#"(?:\[|\]|\(|\)|\{|\})"#)
    private static let trailingSeparatorPattern = compile("[\\s\\-\u{2013}\u{2014}_]+$")
    private static let leadingSeparatorPattern = compile("^[\\s\\-\u{2013}\u{2014}_]+")
    private static let whitespacePattern = compile(#"\s+"#)

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: - Helpers

    private struct RegexMatch {
        let text: NSString
        let result: NSTextCheckingResult
        var start: Int { result.range.location }
        func string(_ index: Int) -> String? {
            guard index < result.numberOfRanges else { return nil }
            let range = result.range(at: index)
            guard range.location != NSNotFound else { return nil }
            return text.substring(with: range)
        }
        func number(_ index: Int) -> Int? {
            string(index).flatMap { Int($0) }
        }
    }

    private static func firstMatch(_ regex: NSRegularExpression?, in text: String) -> RegexMatch? {
        guard let regex = regex else { return nil }
        let source = text as NSString
        guard let result = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: source.length)) else { return nil }
        return RegexMatch(text: source, result: result)
    }

    private static func replacing(_ text: String, _ regex: NSRegularExpression?, with template: String) -> String {
        guard let regex = regex else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func prefix(_ text: String, upTo offset: Int) -> String {
        let source = text as NSString
        guard offset >= 0, offset <= source.length else { return text }
        return source.substring(to: offset)
    }

    /// Desktop's cleanup chain, applied in the same order.
    private static func cleanTitle(_ raw: String) -> String {
        var value = replacing(raw, separatorsPattern, with: " ")
        value = replacing(value, noisePattern, with: " ")
        value = collapse(value)
        value = replacing(value, bracketGroupPattern, with: "")
        value = replacing(value, bracketCharPattern, with: " ")
        value = replacing(value, trailingSeparatorPattern, with: "")
        value = replacing(value, leadingSeparatorPattern, with: "")
        return collapse(value)
    }

    private static func collapse(_ text: String) -> String {
        replacing(text, whitespacePattern, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LocalLibraryGrouping {
    /// Desktop's `groupLocal`: movies collapse into one row per title and year, shows group by title.
    static func groups(_ records: [LocalLibraryRecord]) -> [LocalLibraryGroup] {
        var movies: [String: [LocalLibraryRecord]] = [:]
        var shows: [String: [LocalLibraryRecord]] = [:]
        for record in records {
            let parsed = record.parsed
            if parsed.isShow {
                shows[showKey(parsed.title), default: []].append(record)
            } else {
                movies[movieKey(parsed.title, year: parsed.year), default: []].append(record)
            }
        }
        var out: [LocalLibraryGroup] = []
        for (key, items) in movies {
            guard let first = items.first else { continue }
            let parsed = first.parsed
            out.append(.movie(LocalLibraryMovie(key: key, title: parsed.title, year: parsed.year, versions: sortVersions(items))))
        }
        for (key, items) in shows {
            guard let first = items.first else { continue }
            let year = items.compactMap { $0.parsed.year }.first
            out.append(.show(LocalLibraryShow(key: key, title: first.parsed.title, year: year, seasons: seasons(items))))
        }
        return out.sorted { $0.id < $1.id }
    }

    /// Desktop's `sortGroups`: nil years and nil values always sort last, whatever the direction.
    static func arranged(_ groups: [LocalLibraryGroup], sort: LocalLibrarySortKey, descending: Bool, episodesDescending: Bool) -> [LocalLibraryGroup] {
        let ordered = groups.sorted { isOrderedBefore($0, $1, sort: sort, descending: descending) }
        guard episodesDescending else { return ordered }
        return ordered.map { reversedEpisodes($0) }
    }

    /// Best version first: resolution, then size, then filename.
    static func sortVersions(_ records: [LocalLibraryRecord]) -> [LocalLibraryRecord] {
        records.sorted { lhs, rhs in
            let left = resolutionRank(lhs.parsed.resolution), right = resolutionRank(rhs.parsed.resolution)
            if left != right { return left > right }
            let leftSize = lhs.size ?? 0, rightSize = rhs.size ?? 0
            if leftSize != rightSize { return leftSize > rightSize }
            return lhs.filename < rhs.filename
        }
    }

    static func resolutionRank(_ value: String?) -> Int {
        switch value ?? "" {
        case "2160p", "4k", "uhd": return 4
        case "1080p": return 3
        case "720p": return 2
        case "480p": return 1
        default: return 0
        }
    }

    static func movieKey(_ title: String, year: Int?) -> String {
        let yearPart: String = year.map { String($0) } ?? "?"
        let base: String = "movie:" + normalized(title)
        return base + ":" + yearPart
    }

    static func showKey(_ title: String) -> String {
        "show:" + normalized(title)
    }

    /// Letters and digits only, case and diacritics folded, so `Spider-Man` and `spider man` match.
    static func normalized(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(folded.filter { $0.isLetter || $0.isNumber })
    }

    private static func seasons(_ items: [LocalLibraryRecord]) -> [LocalLibrarySeason] {
        let bySeason = Dictionary(grouping: items) { $0.parsed.season ?? 0 }
        return bySeason.keys.sorted().map { (number: Int) -> LocalLibrarySeason in
            let episodes = (bySeason[number] ?? []).sorted { lhs, rhs in
                let left = lhs.parsed.episode ?? 0, right = rhs.parsed.episode ?? 0
                if left != right { return left < right }
                return lhs.filename < rhs.filename
            }
            return LocalLibrarySeason(number: number, episodes: episodes)
        }
    }

    private static func isOrderedBefore(_ lhs: LocalLibraryGroup, _ rhs: LocalLibraryGroup, sort: LocalLibrarySortKey, descending: Bool) -> Bool {
        switch sort {
        case .title:
            let order = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if order != .orderedSame { return descending ? order == .orderedDescending : order == .orderedAscending }
        case .added:
            if lhs.added != rhs.added { return descending ? lhs.added > rhs.added : lhs.added < rhs.added }
        case .year:
            if let left = lhs.year, let right = rhs.year, left != right { return descending ? left > right : left < right }
            if (lhs.year == nil) != (rhs.year == nil) { return rhs.year == nil }
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func reversedEpisodes(_ group: LocalLibraryGroup) -> LocalLibraryGroup {
        guard case .show(let show) = group else { return group }
        let seasons = show.seasons.reversed().map { (season: LocalLibrarySeason) -> LocalLibrarySeason in
            LocalLibrarySeason(number: season.number, episodes: Array(season.episodes.reversed()))
        }
        return .show(LocalLibraryShow(key: show.key, title: show.title, year: show.year, seasons: seasons))
    }
}

enum LocalLibraryFilter {
    /// Desktop's `minSizeMb` scan filter. Files whose size is unknown are kept.
    static func atLeast(_ records: [LocalLibraryRecord], megabytes: Int) -> [LocalLibraryRecord] {
        let minimum = Int64(max(0, megabytes)) * 1_048_576
        return records.filter { record in
            guard let size = record.size else { return true }
            return size >= minimum
        }
    }
}
