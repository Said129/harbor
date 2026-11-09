import Foundation

// Desktop's subtitle search providers that take no key or the person's own key:
// `src/lib/subtitles/providers/wyzie.ts`, `providers/opensubtitles-v3.ts`,
// `autosync/sub-source-subdl.ts` and `autosync/sub-source-subsource.ts`.
// Requests and parsing are pure. The network goes through `SubtitleProviderTransport`.
// Not ported: Jimaku (Desktop has no provider for it), Podnapisi and Gestdown (autosync only, with no
// setting), the direct OpenSubtitles REST API (auto-sync only), and addon subtitles (`SubtitleAddonService`).

enum SubtitleProviderID: String, CaseIterable, Sendable {
    case opensubtitles, wyzie, subdl, subsource

    var displayName: String {
        switch self {
        case .opensubtitles: "OpenSubtitles"
        case .wyzie: "Wyzie"
        case .subdl: "SUBDL"
        case .subsource: "Subsource"
        }
    }

    /// Desktop's `subProvidersEnabled` defaults (`settings/defaults.ts:290-295`).
    var enabledByDefault: Bool { self == .opensubtitles }

    /// SUBDL and Subsource return nothing without the person's key (`sub-source-subdl.ts:362-363`, `sub-source-subsource.ts:344`).
    var requiresKey: Bool { self == .subdl || self == .subsource }

    /// The title shown beside a candidate: the provider name, then the release, as addon results are titled.
    func listTitle(release: String?) -> String {
        let parts = [displayName, release].compactMap { $0 }.filter { !$0.isEmpty }
        return String(parts.joined(separator: " \u{00B7} ").prefix(240))
    }
}

/// What the player is looking for. Field names follow Desktop's `SubSearchQuery`.
struct SubtitleProviderQuery: Equatable, Sendable {
    var imdbID: String?
    var tmdbID: String?
    var title: String?
    var year: Int?
    var series = false
    var season: Int?
    var episode: Int?
    /// Harbor language codes, as `SubtitleLanguages.normalize` returns them.
    var languages: [String] = []
    var filename: String?

    /// Desktop's `isSeries`: an explicit series request, or a season and an episode.
    var isSeries: Bool { series || (season != nil && episode != nil) }
}

/// The keys the person saved for the providers that need one. Empty means not set.
struct SubtitleProviderKeys: Equatable, Sendable {
    var subdl = ""
    var subsource = ""
}

/// One search result, including provider match evidence and the information needed to prepare its download.
struct SubtitleProviderCandidate: Sendable {
    var subtitle: PlaybackSource.Subtitle
    var provider: SubtitleProviderID
    /// The result title used by Desktop's duplicate key. The displayed mobile title may add the provider name.
    var searchTitle: String? = nil
    /// Lower-case Desktop format (`srt`, `vtt`, `ass`, `ssa`, `sub`, `zip`), or nil when unknown.
    var format: String? = nil
    /// A zip archive. The player checks the downloaded bytes before extracting a playable entry.
    var archive = false
    /// The download requires an exact-origin Subsource request with the profile's key.
    var requiresKey = false
    var hearingImpaired = false
    var forced = false
    var foreignOnly = false
    var machineTranslated = false
    var fromTrusted = false
    var release: String? = nil
    var author: String? = nil
    var downloads = 0
    var ratingScore: Double? = nil
    var ratingTotal: Int? = nil
    var fps: Double? = nil
    /// Desktop's provider match: "exact", "high", "medium" or "low". Nil when Desktop reports no evidence.
    var matchConfidence: String? = nil
    var matchScore: Double? = nil
    var idConfirmed = false
    var episodeConfirmed = false
    var season: Int? = nil
    var episode: Int? = nil
}

// MARK: Transport

struct SubtitleProviderReply: Sendable {
    let status: Int
    let data: Data
}

protocol SubtitleProviderTransport: Sendable {
    func send(_ request: URLRequest) async throws -> SubtitleProviderReply
}

enum SubtitleProviderError: Error, Equatable, Sendable {
    case status(Int)
    case insecureURL
    case tooLarge
}

/// Refuses redirects, so a key sent in a header never follows a redirect to another host (Desktop's `redirect: "error"`).
private final class SubtitleProviderRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct SubtitleProviderURLTransport: SubtitleProviderTransport {
    private static let limit = 8 * 1_024 * 1_024
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: SubtitleProviderRedirectPolicy(), delegateQueue: nil)
    }()

    func send(_ request: URLRequest) async throws -> SubtitleProviderReply {
        guard request.url?.scheme == "https" else { throw SubtitleProviderError.insecureURL }
        let (data, response) = try await Self.session.data(for: request)
        guard data.count <= Self.limit else { throw SubtitleProviderError.tooLarge }
        return SubtitleProviderReply(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }
}

enum SubtitleProviderFetch {
    static func fetchData(_ url: URL, headers: [String: String] = [:], transport: any SubtitleProviderTransport) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let reply = try await transport.send(request)
        guard (200..<300).contains(reply.status) else { throw SubtitleProviderError.status(reply.status) }
        return reply.data
    }

    static func fetchJSON(_ url: URL, headers: [String: String] = [:], transport: any SubtitleProviderTransport) async throws -> JSONValue {
        let data = try await fetchData(url, headers: headers, transport: transport)
        return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
    }
}

// MARK: Shared helpers

enum SubtitleProviderJSON {
    static func text(_ value: JSONValue) -> String? {
        let raw: String?
        switch value {
        case .string(let found): raw = found
        case .integer(let found): raw = String(found)
        case .unsigned(let found): raw = String(found)
        default: raw = nil
        }
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func firstText(_ values: [JSONValue]) -> String? {
        for value in values {
            if let found = text(value) { return found }
        }
        return nil
    }

    /// Arrays such as `releaseInfo` are joined with a space; a plain string is returned as it is.
    static func joinedText(_ value: JSONValue, separator: String = " ") -> String? {
        if case .array(let items) = value {
            let parts = items.compactMap { text($0) }
            return parts.isEmpty ? nil : parts.joined(separator: separator)
        }
        return text(value)
    }

    static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .integer(let found): return Double(found)
        case .unsigned(let found): return Double(found)
        case .number(let found): return found.isFinite ? found : nil
        case .string(let found): return Double(found.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    static func int(_ value: JSONValue) -> Int? {
        guard let found = number(value), abs(found) < 1e15 else { return nil }
        return Int(found)
    }

    /// Desktop's provider booleans. Nil when the field is absent, so a fallback can apply.
    static func flag(_ value: JSONValue) -> Bool? {
        switch value {
        case .bool(let found): return found
        case .integer(let found) where found == 0 || found == 1: return found == 1
        case .unsigned(let found) where found == 0 || found == 1: return found == 1
        case .number(let found) where found == 0 || found == 1: return found == 1
        case .string(let found):
            let lowered = found.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "yes", "1"].contains(lowered) { return true }
            if ["false", "no", "0"].contains(lowered) { return false }
            return nil
        default: return nil
        }
    }

    static func firstFlag(_ values: [JSONValue]) -> Bool? {
        for value in values {
            if let found = flag(value) { return found }
        }
        return nil
    }
}

enum SubtitleProviderIDs {
    /// Desktop's `imdbTt`: "tt" and at least seven digits, from "tt0133093" or "133093".
    static func imdb(_ raw: String?) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if text.lowercased().hasPrefix("tt") { text = String(text.dropFirst(2)) }
        let digits = text.filter { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return "tt" + String(repeating: "0", count: max(0, 7 - digits.count)) + digits
    }

    static func trimmed(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

enum SubtitleProviderURL {
    /// Desktop's `isSafeProviderSubtitleUrl`, as `SubtitleAddonService` applies it: http or https, a host,
    /// no credentials, and no control characters.
    static func safe(_ raw: String) -> String? {
        guard raw.rangeOfCharacter(from: .controlCharacters) == nil,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return raw
    }

    /// Resolves a provider's relative download path against that provider's own base URL.
    static func resolve(_ raw: String, base: String) -> String? {
        guard let baseURL = URL(string: base), let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteString else { return nil }
        return safe(resolved)
    }

    static func url(_ base: String, _ items: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = items
        return components?.url
    }
}

enum SubtitleProviderFormat {
    /// Desktop's `detectFormat`: the hint's words first, then the URL's extension.
    static func detect(_ url: String, hint: String?) -> String? {
        let words = Set((hint ?? "").lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
        if words.contains("zip") { return "zip" }
        if words.contains("vtt") || words.contains("webvtt") { return "vtt" }
        if words.contains("ass") { return "ass" }
        if words.contains("ssa") { return "ssa" }
        if words.contains("srt") || words.contains("subrip") { return "srt" }
        if words.contains("sub") { return "sub" }
        let path = url.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? url
        let ext = path.components(separatedBy: ".").last?.lowercased() ?? ""
        return ["zip", "vtt", "ass", "ssa", "srt", "sub"].contains(ext) ? ext : nil
    }
}

/// Desktop's `classifyProviderSubtitleMetadata`: a provider's own flag wins, and release labels are only a fallback.
enum SubtitleProviderClassification {
    struct Flags: Equatable, Sendable {
        var hearingImpaired: Bool
        var forced: Bool
        var foreignOnly: Bool
        var machineTranslated: Bool
    }

    static func classify(_ metadata: JSONValue, labels: [String?]) -> Flags {
        let descriptor = descriptorOf(labels)
        let hearing = SubtitleProviderJSON.firstFlag([metadata["hearingImpaired"], metadata["hearing_impaired"], metadata["hi"], metadata["sdh"]])
        let forced = SubtitleProviderJSON.firstFlag([metadata["forced"]])
        let foreign = SubtitleProviderJSON.firstFlag([metadata["foreignOnly"], metadata["foreign_only"], metadata["foreignParts"], metadata["foreign_parts"]])
        let machine = SubtitleProviderJSON.firstFlag([metadata["machineTranslated"], metadata["machine_translated"], metadata["aiTranslated"], metadata["ai_translated"]])
        return Flags(
            hearingImpaired: hearing ?? matches(descriptor, #"(?:^| )(?:sdh|hearing impaired|closed captions?)(?: |$)"#),
            forced: forced ?? matches(descriptor, #"(?:^| )(?:forced|foreign parts?)(?: |$)"#),
            foreignOnly: foreign ?? matches(descriptor, #"(?:^| )foreign (?:only|parts?)(?: |$)"#),
            machineTranslated: machine ?? matches(descriptor, #"(?:^| )(?:machine|ai) translat(?:ed|ion)(?: |$)"#)
        )
    }

    private static func descriptorOf(_ labels: [String?]) -> String {
        let joined = labels.compactMap { $0 }.joined(separator: " ").lowercased()
        let cleaned = joined.replacingOccurrences(of: #"[._\-/\\()\[\]]+"#, with: " ", options: .regularExpression)
        return cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: Wyzie (no key, off by default on Desktop)

enum WyzieProvider {
    static let endpoint = "https://sub.wyzie.io/search"

    /// Desktop's `searchWyzie`: an IMDb id, else a TMDB id, else the title.
    static func request(_ query: SubtitleProviderQuery) -> URL? {
        var items: [URLQueryItem] = []
        if let imdb = SubtitleProviderIDs.imdb(query.imdbID) {
            items.append(URLQueryItem(name: "id", value: imdb))
        } else if let tmdb = SubtitleProviderIDs.trimmed(query.tmdbID) {
            items.append(URLQueryItem(name: "id", value: tmdb))
        } else if let title = SubtitleProviderIDs.trimmed(query.title) {
            items.append(URLQueryItem(name: "query", value: title))
        } else {
            return nil
        }
        if let season = query.season { items.append(URLQueryItem(name: "season", value: String(season))) }
        if let episode = query.episode { items.append(URLQueryItem(name: "episode", value: String(episode))) }
        items.append(URLQueryItem(name: "source", value: "all"))
        let codes = query.languages.map { SubtitleLanguages.normalize($0) }.filter { !$0.isEmpty }
        if !codes.isEmpty { items.append(URLQueryItem(name: "language", value: codes.joined(separator: ","))) }
        return SubtitleProviderURL.url(endpoint, items)
    }

    static func parse(_ data: Data) -> [SubtitleProviderCandidate] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        var out: [SubtitleProviderCandidate] = []
        for row in root.array {
            guard let raw = SubtitleProviderJSON.text(row["url"]), let url = SubtitleProviderURL.safe(raw) else { continue }
            var lang = SubtitleLanguages.normalize(SubtitleProviderJSON.text(row["language"]) ?? "")
            if lang.isEmpty { lang = SubtitleLanguages.normalize(SubtitleProviderJSON.text(row["display"]) ?? "") }
            let release = SubtitleProviderJSON.text(row["release"])
            let format = SubtitleProviderJSON.text(row["format"])?.lowercased()
            let hearing = (SubtitleProviderJSON.flag(row["isHearingImpaired"]) ?? false) || (SubtitleProviderJSON.flag(row["hi"]) ?? false)
            let id = SubtitleProviderJSON.text(row["id"]) ?? url
            let subtitle = PlaybackSource.Subtitle(url: url, lang: lang, id: "wyzie:" + id, title: SubtitleProviderID.wyzie.listTitle(release: release))
            var candidate = SubtitleProviderCandidate(subtitle: subtitle, provider: .wyzie)
            candidate.searchTitle = release
            candidate.format = format
            candidate.archive = format == "zip"
            candidate.hearingImpaired = hearing
            candidate.release = release
            candidate.author = SubtitleProviderJSON.firstText([row["author"], row["uploader"]])
            candidate.downloads = SubtitleProviderJSON.int(row["downloads"]) ?? 0
            candidate.fps = SubtitleProviderJSON.number(row["fps"])
            out.append(candidate)
        }
        return out
    }
}

// MARK: OpenSubtitles V3 (Stremio addon, no key; Desktop's built-in "OpenSubtitles" toggle)

enum OpenSubtitlesV3Provider {
    static let base = "https://opensubtitles-v3.strem.io"

    /// Desktop's `scopedIds`: an episode asks for `tt:season:episode`, and a movie or series asks for `tt`.
    static func requests(_ query: SubtitleProviderQuery) -> [URL] {
        guard let imdb = SubtitleProviderIDs.imdb(query.imdbID) else { return [] }
        let target: (type: String, id: String)
        if let season = query.season, let episode = query.episode {
            target = ("series", "\(imdb):\(season):\(episode)")
        } else if let episode = query.episode {
            target = ("series", "\(imdb):1:\(episode)")
        } else {
            target = (query.isSeries ? "series" : "movie", imdb)
        }
        guard let url = URL(string: "\(base)/subtitles/\(target.type)/\(target.id).json") else { return [] }
        return [url]
    }

    static func parse(_ data: Data) -> [SubtitleProviderCandidate] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [] }
        var seen = Set<String>()
        var perLanguage: [String: Int] = [:]
        var out: [SubtitleProviderCandidate] = []
        for row in root["subtitles"].array {
            guard let raw = SubtitleProviderJSON.text(row["url"]), let url = SubtitleProviderURL.safe(raw) else { continue }
            let rawLanguage = SubtitleProviderJSON.text(row["lang"]) ?? ""
            guard seen.insert(rawLanguage + "|" + url).inserted else { continue }
            let lang = SubtitleLanguages.normalize(rawLanguage)
            let ordinal = (perLanguage[lang] ?? 0) + 1
            perLanguage[lang] = ordinal
            let searchTitle = "OpenSubtitles V3 #\(ordinal)"
            let release = SubtitleProviderJSON.text(row["m"])
            let rowID = SubtitleProviderJSON.text(row["id"]) ?? url
            let flags = SubtitleProviderClassification.classify(row, labels: [release, SubtitleProviderJSON.text(row["id"]), url])
            let format = SubtitleProviderJSON.text(row["SubFormat"])?.lowercased()
            let subtitle = PlaybackSource.Subtitle(url: url, lang: lang, id: "os3:" + rowID, title: searchTitle)
            var candidate = SubtitleProviderCandidate(subtitle: subtitle, provider: .opensubtitles)
            candidate.searchTitle = searchTitle
            candidate.format = format
            candidate.archive = format == "zip"
            candidate.hearingImpaired = flags.hearingImpaired
            candidate.forced = flags.forced
            candidate.foreignOnly = flags.foreignOnly
            candidate.machineTranslated = flags.machineTranslated
            candidate.release = release
            candidate.fps = SubtitleProviderJSON.number(row["fps"])
            out.append(candidate)
        }
        return out
    }
}

// MARK: SUBDL (the person's key, sent as the api_key query item)

enum SubDLProvider {
    static let endpoint = "https://api.subdl.com/api/v1/subtitles"
    static let downloadBase = "https://dl.subdl.com/"
    private static let languageOverrides: [String: String] = ["pt-br": "BR", "es-419": "ES", "zh": "ZH"]

    /// Desktop's `subdlLangCode`: a region override, else the primary subtag, in upper case.
    static func languageCode(_ raw: String) -> String {
        let normalized = SubtitleLanguages.normalize(raw)
        if let mapped = languageOverrides[normalized] { return mapped }
        let primary = normalized.split(separator: "-").first.map { String($0) } ?? ""
        return primary.uppercased()
    }

    /// Desktop's `buildSubdlSearchUrl`. Returns nil when there is nothing to search for.
    static func request(_ query: SubtitleProviderQuery, apiKey: String) -> URL? {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "subs_per_page", value: "30"),
            URLQueryItem(name: "comment", value: "1"),
            URLQueryItem(name: "releases", value: "1"),
            URLQueryItem(name: "hi", value: "1"),
            URLQueryItem(name: "unpack", value: "1"),
            URLQueryItem(name: "client", value: "stremio"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        if let filename = SubtitleProviderIDs.trimmed(query.filename) {
            items.append(URLQueryItem(name: "file_name", value: filename))
        }
        if let imdb = SubtitleProviderIDs.imdb(query.imdbID) {
            items.append(URLQueryItem(name: "imdb_id", value: imdb))
        } else if let tmdb = SubtitleProviderIDs.trimmed(query.tmdbID) {
            items.append(URLQueryItem(name: "tmdb_id", value: tmdb))
        } else if let title = SubtitleProviderIDs.trimmed(query.title) {
            items.append(URLQueryItem(name: "film_name", value: title))
        } else if SubtitleProviderIDs.trimmed(query.filename) == nil {
            return nil
        }
        items.append(URLQueryItem(name: "type", value: query.isSeries ? "tv" : "movie"))
        let codes = query.languages.map { languageCode($0) }.filter { !$0.isEmpty }
        if !codes.isEmpty { items.append(URLQueryItem(name: "languages", value: codes.joined(separator: ","))) }
        if let season = query.season { items.append(URLQueryItem(name: "season_number", value: String(season))) }
        if let episode = query.episode { items.append(URLQueryItem(name: "episode_number", value: String(episode))) }
        if let year = query.year { items.append(URLQueryItem(name: "year", value: String(year))) }
        return SubtitleProviderURL.url(endpoint, items)
    }

    static func parse(_ data: Data, query: SubtitleProviderQuery) -> [SubtitleProviderCandidate] {
        guard let root = try? JSONDecoder().decode(JSONValue.self, from: data), root["status"] != .bool(false) else { return [] }
        let idConfirmed = returnedIDConfirmed(root["results"], query: query)
        var out: [SubtitleProviderCandidate] = []
        for row in root["subtitles"].array {
            let files = row["unpack_files"].array.filter { exactEpisode(row, $0, query: query) }
            if files.isEmpty {
                if let made = subdlCandidate(row, file: .null, query: query, idConfirmed: idConfirmed) { out.append(made) }
            } else {
                for file in files {
                    if let made = subdlCandidate(row, file: file, query: query, idConfirmed: idConfirmed) { out.append(made) }
                }
            }
        }
        return out
    }

    private static func returnedIDConfirmed(_ results: JSONValue, query: SubtitleProviderQuery) -> Bool {
        guard let first = results.array.first else { return false }
        if let imdb = SubtitleProviderIDs.imdb(query.imdbID) {
            return SubtitleProviderIDs.imdb(SubtitleProviderJSON.text(first["imdb_id"])) == imdb
        }
        if let tmdb = SubtitleProviderIDs.trimmed(query.tmdbID) {
            return SubtitleProviderJSON.text(first["tmdb_id"]) == tmdb
        }
        return false
    }

    private static func episodeOf(_ row: JSONValue, _ file: JSONValue) -> (season: Int?, episode: Int?) {
        let season = SubtitleProviderJSON.int(file["season"]) ?? SubtitleProviderJSON.int(row["season"])
        let episode = SubtitleProviderJSON.int(file["episode"]) ?? SubtitleProviderJSON.int(row["episode"])
        return (season, episode)
    }

    private static func exactEpisode(_ row: JSONValue, _ file: JSONValue, query: SubtitleProviderQuery) -> Bool {
        guard let wanted = query.episode else { return true }
        let found = episodeOf(row, file)
        guard found.episode == wanted else { return false }
        guard let season = query.season else { return true }
        return found.season == season
    }

    private static func fpsOf(_ row: JSONValue) -> Double? {
        if let explicit = SubtitleProviderJSON.number(row["fps"]) { return explicit }
        let codes: [Int: Double] = [2: 23.976, 6: 23.98, 5: 24, 3: 25, 4: 29.97, 7: 30]
        guard let code = SubtitleProviderJSON.int(row["framerate"]) else { return nil }
        return codes[code]
    }

    private static func subdlCandidate(_ row: JSONValue, file: JSONValue, query: SubtitleProviderQuery, idConfirmed: Bool) -> SubtitleProviderCandidate? {
        guard let raw = SubtitleProviderJSON.firstText([file["url"], row["url"]]),
              let url = SubtitleProviderURL.resolve(raw, base: downloadBase) else { return nil }
        let lang = SubtitleLanguages.normalize(SubtitleProviderJSON.firstText([file["language"], file["lang"], row["language"], row["lang"]]) ?? "")
        let found = episodeOf(row, file)
        let format = SubtitleProviderFormat.detect(url, hint: SubtitleProviderJSON.firstText([file["format"], row["format"]]))
        var release = SubtitleProviderJSON.firstText([file["release_name"], file["name"], row["release_name"]])
        if release == nil { release = SubtitleProviderJSON.joinedText(row["releases"]) }
        if release == nil { release = SubtitleProviderJSON.text(row["name"]) }
        let hearing = (SubtitleProviderJSON.flag(file["hi"]) ?? SubtitleProviderJSON.flag(row["hi"])) ?? false
        let forced = (SubtitleProviderJSON.flag(file["forced"]) ?? SubtitleProviderJSON.flag(row["forced"])) ?? false
        let production = SubtitleProviderJSON.text(row["production_type"]) ?? ""
        let machine = SubtitleProviderJSON.flag(row["machine_translated"]) == true || production == "3" || production == "machine-translated"
        let hasFile = file != .null
        let fullSeason = SubtitleProviderJSON.flag(row["full_season"]) ?? false
        let rating = SubtitleProviderDLRating.of(row["rating"])
        let subtitleID = SubtitleProviderJSON.firstText([file["file_n_id"], file["md5"], row["n_id"]]) ?? raw
        let subtitle = PlaybackSource.Subtitle(url: url, lang: lang, id: "subdl:" + subtitleID, title: SubtitleProviderID.subdl.listTitle(release: release))
        var candidate = SubtitleProviderCandidate(subtitle: subtitle, provider: .subdl)
        candidate.format = format
        candidate.archive = !hasFile && (format == "zip" || fullSeason)
        candidate.hearingImpaired = hearing
        candidate.forced = forced
        candidate.machineTranslated = machine
        candidate.fromTrusted = SubtitleProviderJSON.flag(row["trusted"]) ?? false
        candidate.release = release
        candidate.author = SubtitleProviderJSON.firstText([row["author"], row["uploader"]])
        candidate.downloads = SubtitleProviderJSON.int(row["downloads"]) ?? 0
        candidate.fps = fpsOf(row)
        candidate.ratingScore = rating.score
        candidate.ratingTotal = rating.total
        candidate.season = found.season
        candidate.episode = found.episode
        let confirmedEpisode = query.episode != nil && found.episode == query.episode && (query.season == nil || found.season == query.season)
        candidate.idConfirmed = idConfirmed
        candidate.episodeConfirmed = confirmedEpisode
        if idConfirmed && confirmedEpisode {
            candidate.matchConfidence = "high"
            candidate.matchScore = 0.85
        } else if idConfirmed {
            candidate.matchConfidence = "medium"
            candidate.matchScore = 0.7
        } else if confirmedEpisode {
            candidate.matchConfidence = "low"
            candidate.matchScore = 0.6
        }
        return candidate
    }
}

// MARK: Subsource (the person's key, sent as X-API-Key; downloads are zip archives)

enum SubSourceProvider {
    static let base = "https://api.subsource.net/api/v1"
    private static let languageOverrides: [String: String] = ["fa": "farsi_persian", "pt-br": "brazilian_portuguese", "es-419": "spanish_latin_america"]
    private static let videoExtensions = #"\.(?:mkv|mp4|m4v|avi|mov|ts|m2ts|webm)$"#

    struct ListRequest: Equatable, Sendable {
        let url: URL
        let exactRelease: Bool
    }

    /// Desktop's `subsource` language name: an override, else the English name in lower case with underscores.
    static func languageName(_ raw: String) -> String {
        let normalized = SubtitleLanguages.normalize(raw)
        if let mapped = languageOverrides[normalized] { return mapped }
        let english = Locale(identifier: "en_US").localizedString(forLanguageCode: normalized) ?? normalized
        return english.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    static func movieSearchURL(_ query: SubtitleProviderQuery) -> URL? {
        var items: [URLQueryItem] = []
        if let imdb = SubtitleProviderIDs.imdb(query.imdbID) {
            items.append(URLQueryItem(name: "searchType", value: "imdb"))
            items.append(URLQueryItem(name: "imdb", value: imdb))
        } else if let title = SubtitleProviderIDs.trimmed(query.title) {
            items.append(URLQueryItem(name: "searchType", value: "text"))
            items.append(URLQueryItem(name: "q", value: title))
        } else {
            return nil
        }
        items.append(URLQueryItem(name: "type", value: query.isSeries ? "series" : "movie"))
        if let year = query.year { items.append(URLQueryItem(name: "year", value: String(year))) }
        if let season = query.season { items.append(URLQueryItem(name: "season", value: String(season))) }
        return SubtitleProviderURL.url(base + "/movies/search", items)
    }

    /// The movie Desktop's `chooseMovie` picks from the search envelope, or nil when the envelope failed or nothing matches.
    static func chosenMovie(_ envelope: JSONValue, query: SubtitleProviderQuery) -> JSONValue? {
        guard envelope["success"] != .bool(false) else { return nil }
        return chooseMovie(envelope["data"].array, query: query)
    }

    static func chooseMovie(_ movies: [JSONValue], query: SubtitleProviderQuery) -> JSONValue? {
        let candidates = movies.filter { typeMatches($0, series: query.isSeries) }
        if let imdb = SubtitleProviderIDs.imdb(query.imdbID) {
            return candidates.first(where: { SubtitleProviderIDs.imdb(SubtitleProviderJSON.text($0["imdbId"])) == imdb })
        }
        if let tmdb = SubtitleProviderIDs.trimmed(query.tmdbID) {
            return candidates.first(where: { SubtitleProviderJSON.text($0["tmdbId"]) == tmdb })
        }
        let wanted = normalizedTitle(query.title)
        guard !wanted.isEmpty else { return nil }
        var best: (score: Int, id: Int, movie: JSONValue)?
        for movie in candidates {
            let primary = normalizedTitle(SubtitleProviderJSON.text(movie["title"])) == wanted
            let alternate = normalizedTitle(SubtitleProviderJSON.text(movie["alternateTitle"])) == wanted
            let yearMatches = query.year == nil || SubtitleProviderJSON.int(movie["releaseYear"]) == query.year
            let seasonMatches = query.season == nil || SubtitleProviderJSON.int(movie["season"]) == query.season
            guard primary || alternate, yearMatches, seasonMatches else { continue }
            let score = primary ? 2 : 1
            let id = SubtitleProviderJSON.int(movie["movieId"]) ?? Int.max
            if let current = best, current.score > score || (current.score == score && current.id <= id) { continue }
            best = (score, id, movie)
        }
        return best?.movie
    }

    /// Desktop's `buildSubsourceSubtitleUrl` requests, one per wanted language (or none). With a file name, Desktop
    /// asks first for the exact release and then for everything.
    static func listRequests(movieID: String, query: SubtitleProviderQuery) -> [ListRequest] {
        let release = releaseValue(query.filename)
        var choices: [String?] = query.languages.map { SubtitleLanguages.normalize($0) }.filter { !$0.isEmpty }.map { Optional($0) }
        if choices.isEmpty { choices = [nil] }
        var requests: [ListRequest] = []
        for language in choices {
            if let release = release, let url = listURL(movieID: movieID, language: language, releaseInfo: release) {
                requests.append(ListRequest(url: url, exactRelease: true))
            }
            if let url = listURL(movieID: movieID, language: language, releaseInfo: nil) {
                requests.append(ListRequest(url: url, exactRelease: false))
            }
        }
        return requests
    }

    static func listURL(movieID: String, language: String?, releaseInfo: String?) -> URL? {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "movieId", value: movieID),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "sort", value: "rating"),
        ]
        if let language = language, !language.isEmpty {
            items.append(URLQueryItem(name: "language", value: languageName(language)))
        }
        if let releaseInfo = releaseInfo {
            items.append(URLQueryItem(name: "releaseInfo", value: releaseInfo))
        }
        return SubtitleProviderURL.url(base + "/subtitles", items)
    }

    static func parseSubtitles(_ envelope: JSONValue, movie: JSONValue, query: SubtitleProviderQuery, exactRelease: Bool) -> [SubtitleProviderCandidate] {
        guard envelope["success"] != .bool(false) else { return [] }
        let idConfirmed = movieIDConfirmed(movie, query: query)
        var out: [SubtitleProviderCandidate] = []
        for row in envelope["data"].array {
            guard let subtitleID = SubtitleProviderJSON.text(row["subtitleId"]) else { continue }
            let encodedID = subtitleID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? subtitleID
            guard let url = SubtitleProviderURL.safe(base + "/subtitles/" + encodedID + "/download") else { continue }
            let lang = SubtitleLanguages.normalize(SubtitleProviderJSON.text(row["language"]) ?? "")
            let production = (SubtitleProviderJSON.text(row["productionType"]) ?? "").lowercased()
            let release = SubtitleProviderJSON.joinedText(row["releaseInfo"])
            let subtitle = PlaybackSource.Subtitle(url: url, lang: lang, id: "subsource:" + subtitleID, title: SubtitleProviderID.subsource.listTitle(release: release))
            var candidate = SubtitleProviderCandidate(subtitle: subtitle, provider: .subsource)
            candidate.format = "zip"
            candidate.archive = true
            candidate.requiresKey = true
            candidate.hearingImpaired = SubtitleProviderJSON.flag(row["hearingImpaired"]) ?? false
            candidate.forced = production == "forced"
            candidate.foreignOnly = (SubtitleProviderJSON.flag(row["foreignParts"]) ?? false) || production == "forced"
            candidate.machineTranslated = production == "machine" || production.range(of: #"machine|\bai\b"#, options: .regularExpression) != nil
            candidate.fromTrusted = production == "retail"
            candidate.release = release
            candidate.author = contributorsText(row)
            candidate.downloads = SubtitleProviderJSON.int(row["downloads"]) ?? 0
            candidate.fps = SubtitleProviderJSON.number(row["framerate"])
            let rating = SubtitleProviderDLRating.of(row["rating"])
            candidate.ratingScore = rating.score
            candidate.ratingTotal = rating.total
            candidate.idConfirmed = idConfirmed
            if exactRelease {
                candidate.matchConfidence = "high"
                candidate.matchScore = 0.95
            } else if idConfirmed {
                candidate.matchConfidence = "medium"
                candidate.matchScore = 0.8
            } else {
                candidate.matchConfidence = "low"
                candidate.matchScore = 0.6
            }
            candidate.season = SubtitleProviderJSON.int(movie["season"]) ?? query.season
            out.append(candidate)
        }
        return out
    }

    static func normalizedTitle(_ raw: String?) -> String {
        (raw ?? "").lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Desktop's `releaseSearchValue`: the file name without folders, query string or video extension.
    static func releaseValue(_ filename: String?) -> String? {
        guard let raw = SubtitleProviderIDs.trimmed(filename) else { return nil }
        let withoutQuery = raw.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? raw
        let basename = withoutQuery.components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? withoutQuery
        let stripped = basename.replacingOccurrences(of: videoExtensions, with: "", options: [.regularExpression, .caseInsensitive])
        let value = stripped.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func typeMatches(_ movie: JSONValue, series: Bool) -> Bool {
        guard let type = SubtitleProviderJSON.text(movie["type"])?.lowercased() else { return true }
        return series ? ["series", "tv", "tvseries", "show"].contains(type) : type == "movie"
    }

    private static func movieIDConfirmed(_ movie: JSONValue, query: SubtitleProviderQuery) -> Bool {
        if let imdb = SubtitleProviderIDs.imdb(query.imdbID) {
            return SubtitleProviderIDs.imdb(SubtitleProviderJSON.text(movie["imdbId"])) == imdb
        }
        if let tmdb = SubtitleProviderIDs.trimmed(query.tmdbID) {
            return SubtitleProviderJSON.text(movie["tmdbId"]) == tmdb
        }
        return false
    }

    private static func contributorsText(_ row: JSONValue) -> String? {
        let names = row["contributors"].array.compactMap { SubtitleProviderJSON.text($0["displayname"]) }
        if !names.isEmpty { return names.joined(separator: ", ") }
        return SubtitleProviderJSON.text(row["uploaderId"])
    }
}

/// Rating reader shared by SUBDL and Subsource rows (Desktop's `ratingOf`).
enum SubtitleProviderDLRating {
    static func of(_ value: JSONValue) -> (score: Double?, total: Int?) {
        if let plain = SubtitleProviderJSON.number(value) { return (plain, nil) }
        let good = SubtitleProviderJSON.number(value["good"])
        let bad = SubtitleProviderJSON.number(value["bad"])
        var total = SubtitleProviderJSON.int(value["total"])
        if total == nil, good != nil || bad != nil { total = Int((good ?? 0) + (bad ?? 0)) }
        var score = SubtitleProviderJSON.number(value["score"])
        if score == nil, let good = good, let count = total, count > 0 { score = good / Double(count) }
        return (score, total)
    }
}

// MARK: Search

/// Searches the enabled providers at once. A provider that needs a key the person has not saved, fails,
/// or exceeds its own deadline contributes nothing, without extending another provider's wait.
struct SubtitleProviderService: Sendable {
    let transport: any SubtitleProviderTransport
    let providerTimeout: Duration

    init(transport: any SubtitleProviderTransport = SubtitleProviderURLTransport(), providerTimeout: Duration = .seconds(8)) {
        self.transport = transport
        self.providerTimeout = providerTimeout
    }

    func search(_ query: SubtitleProviderQuery, enabled: Set<SubtitleProviderID>, keys: SubtitleProviderKeys,
                preferredLanguages: [String]? = nil) async -> [SubtitleProviderCandidate] {
        let transport = self.transport
        let providerTimeout = self.providerTimeout
        let batches: [(SubtitleProviderID, [SubtitleProviderCandidate])] = await withTaskGroup(of: (SubtitleProviderID, [SubtitleProviderCandidate]).self, returning: [(SubtitleProviderID, [SubtitleProviderCandidate])].self) { group in
            for provider in SubtitleProviderID.allCases where enabled.contains(provider) {
                group.addTask {
                    let results = await Self.runWithTimeout(provider, query: query, keys: keys, transport: transport, timeout: providerTimeout)
                    return (provider, results)
                }
            }
            var collected: [(SubtitleProviderID, [SubtitleProviderCandidate])] = []
            for await batch in group { collected.append(batch) }
            return collected
        }
        let providerOrder = Dictionary(uniqueKeysWithValues: SubtitleProviderID.allCases.enumerated().map { ($0.element, $0.offset) })
        let ordered = batches.sorted { (providerOrder[$0.0] ?? 0) < (providerOrder[$1.0] ?? 0) }
        return SubtitleSearchRanking.deduplicateAndRank(ordered.flatMap { $0.1 }, preferredLanguages: preferredLanguages ?? query.languages)
    }

    private static func runWithTimeout(_ provider: SubtitleProviderID, query: SubtitleProviderQuery, keys: SubtitleProviderKeys,
                                       transport: any SubtitleProviderTransport, timeout: Duration) async -> [SubtitleProviderCandidate] {
        await withTaskGroup(of: [SubtitleProviderCandidate]?.self, returning: [SubtitleProviderCandidate].self) { group in
            group.addTask {
                let results = await Self.run(provider, query: query, keys: keys, transport: transport)
                return results as [SubtitleProviderCandidate]?
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            guard let first = await group.next() else {
                group.cancelAll()
                return []
            }
            group.cancelAll()
            return first ?? []
        }
    }

    private static func run(_ provider: SubtitleProviderID, query: SubtitleProviderQuery, keys: SubtitleProviderKeys, transport: any SubtitleProviderTransport) async -> [SubtitleProviderCandidate] {
        do {
            switch provider {
            case .wyzie:
                guard let url = WyzieProvider.request(query) else { return [] }
                let data = try await SubtitleProviderFetch.fetchData(url, transport: transport)
                return WyzieProvider.parse(data)
            case .opensubtitles:
                var out: [SubtitleProviderCandidate] = []
                for url in OpenSubtitlesV3Provider.requests(query) {
                    let data = try await SubtitleProviderFetch.fetchData(url, transport: transport)
                    out += OpenSubtitlesV3Provider.parse(data)
                }
                return out
            case .subdl:
                guard let key = SubtitleProviderIDs.trimmed(keys.subdl), let url = SubDLProvider.request(query, apiKey: key) else { return [] }
                let data = try await SubtitleProviderFetch.fetchData(url, transport: transport)
                return SubDLProvider.parse(data, query: query)
            case .subsource:
                return try await subsource(query, key: SubtitleProviderIDs.trimmed(keys.subsource), transport: transport)
            }
        } catch {
            return []
        }
    }

    private static func subsource(_ query: SubtitleProviderQuery, key: String?, transport: any SubtitleProviderTransport) async throws -> [SubtitleProviderCandidate] {
        guard let key = key, let searchURL = SubSourceProvider.movieSearchURL(query) else { return [] }
        let headers = ["X-API-Key": key]
        let envelope = try await SubtitleProviderFetch.fetchJSON(searchURL, headers: headers, transport: transport)
        guard let movie = SubSourceProvider.chosenMovie(envelope, query: query),
              let movieID = SubtitleProviderJSON.text(movie["movieId"]) else { return [] }
        let requests = SubSourceProvider.listRequests(movieID: movieID, query: query)
        return await withTaskGroup(of: (Int, [SubtitleProviderCandidate]).self, returning: [SubtitleProviderCandidate].self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    guard let listEnvelope = try? await SubtitleProviderFetch.fetchJSON(request.url, headers: headers, transport: transport) else { return (index, []) }
                    return (index, SubSourceProvider.parseSubtitles(listEnvelope, movie: movie, query: query, exactRelease: request.exactRelease))
                }
            }
            var batches: [(Int, [SubtitleProviderCandidate])] = []
            for await batch in group { batches.append(batch) }
            return batches.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        }
    }
}

/// Reads the provider toggles that `SubtitleProvidersSettingsView` writes. Absent values fall back to Desktop's defaults.
enum SubtitleProviderPreferences {
    /// The `@AppStorage` key for a provider's toggle. The settings view uses the same literal.
    static func storageKey(_ provider: SubtitleProviderID) -> String {
        "subtitleProvider." + provider.rawValue + ".enabled"
    }

    static func isEnabled(_ provider: SubtitleProviderID, defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: storageKey(provider)) as? Bool) ?? provider.enabledByDefault
    }

    static func addonsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: "subtitleProvider.addons.enabled") as? Bool ?? true
    }

    static func enabledProviders(defaults: UserDefaults = .standard) -> Set<SubtitleProviderID> {
        Set(SubtitleProviderID.allCases.filter { isEnabled($0, defaults: defaults) })
    }
}
