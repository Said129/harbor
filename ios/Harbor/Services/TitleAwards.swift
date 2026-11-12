import Foundation

/// Desktop's `AwardType` (`src/lib/providers/wikidata.ts`).
enum TitleAwardCeremony: String, CaseIterable, Sendable {
    case oscar
    case emmy
    case goldenGlobe = "golden_globe"
    case bafta
    case baftaTV = "bafta_tv"
    case sag
    case criticsChoice = "critics_choice"
    case cannes
    case venice
    case berlin
    case annie
    case spirit
    case saturn
    case cesar
    case goya
    case blueDragon = "blue_dragon"
    case baeksang
    case bifa
    case other

    /// Desktop's `TYPE_ORDER` in `src/components/awards-block.tsx`, without `other`, which the detail page never shows.
    static let displayOrder: [TitleAwardCeremony] = [
        .oscar, .emmy, .bafta, .baftaTV, .goldenGlobe, .sag, .criticsChoice, .cannes, .venice, .berlin,
        .cesar, .goya, .blueDragon, .baeksang, .bifa, .spirit, .annie, .saturn,
    ]
}

/// One Wikidata award statement for a title, after Desktop's row merging and collapsing.
struct TitleAward: Equatable, Sendable {
    let ceremony: TitleAwardCeremony
    let awardName: String
    let category: String?
    let recipients: [String]
    let year: Int?
    let won: Bool
    let workTitle: String?
    let workIMDb: String?

    func replacingYear(_ year: Int) -> TitleAward {
        TitleAward(ceremony: ceremony, awardName: awardName, category: category, recipients: recipients, year: year, won: won, workTitle: workTitle, workIMDb: workIMDb)
    }
}

/// Desktop's `fetchAwards` result: `complete` is false when either SPARQL request failed, and Desktop then does not keep it.
struct TitleAwardsLoad: Equatable, Sendable {
    let entries: [TitleAward]
    let complete: Bool
}

/// One ceremony's rows on the detail page, as Desktop's `AwardGroup` splits them.
struct TitleAwardCeremonyGroup: Equatable, Sendable {
    let ceremony: TitleAwardCeremony
    /// Won rows that name a category, newest first (Desktop sorts by year, descending).
    let wins: [TitleAward]
    /// Nominated rows that name a category, newest first.
    let nominations: [TitleAward]
    /// Counts include rows without a category, as Desktop's totals do.
    let winCount: Int
    let nominationCount: Int
    let years: [Int]
}

/// Desktop's SPARQL text and row handling from `src/lib/providers/wikidata.ts`.
enum TitleAwardParser {
    static func isTitleID(_ value: String) -> Bool {
        value.range(of: #"^tt[0-9]{1,12}$"#, options: .regularExpression) != nil
    }

    /// A person (`nm`) id: Desktop's `fetchAwards` sends it through the same query, since the query matches any IMDb id.
    static func isPersonID(_ value: String) -> Bool {
        value.range(of: #"^nm[0-9]{1,12}$"#, options: .regularExpression) != nil
    }

    /// Desktop interpolates the IMDb id into the query; here only a well formed title id is accepted, or a person id when
    /// `allowsPerson` is set by the person page.
    static func query(imdbID: String, nominations: Bool, allowsPerson: Bool = false) -> String? {
        guard isTitleID(imdbID) || (allowsPerson && isPersonID(imdbID)) else { return nil }
        return (nominations ? titleAwardNominationQuery : titleAwardWinQuery).replacingOccurrences(of: "IMDB_ID", with: imdbID)
    }

    /// The same URL as Desktop's `runQuery`: `encodeURIComponent` on the query, then `format=json`.
    static func requestURL(query: String) -> URL? {
        guard var parts = URLComponents(string: "https://query.wikidata.org/sparql") else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        parts.percentEncodedQuery = "query=" + encoded + "&format=json"
        return parts.url
    }

    /// Desktop's `parseRows`. Returns nil when the body is not JSON, which Desktop treats as a failed request.
    static func rows(from data: Data, won: Bool) -> [TitleAward]? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        var order: [String] = []
        var buckets: [String: TitleAwardRowBucket] = [:]
        for row in json["results"]["bindings"].array {
            guard let awardName = text(row, "awardLabel") else { continue }
            let category = prettyCategory(awardName, provided: text(row, "categoryLabel"))
            let recipient = text(row, "recipientLabel")
            let year = text(row, "date").flatMap(yearOf)
            let workTitle = text(row, "workLabel").flatMap { $0.hasPrefix("http") ? nil : $0 }
            let workIMDb = text(row, "workImdb")
            let yearText = year.map { String($0) } ?? ""
            let resultText = won ? "won" : "nominated"
            let identity = workIMDb ?? workTitle ?? ""
            let key = [awardName, category ?? "", yearText, resultText, identity].joined(separator: "|")
            if var bucket = buckets[key] {
                if let workTitle, bucket.workTitle == nil { bucket.workTitle = workTitle }
                if let workIMDb, bucket.workIMDb == nil { bucket.workIMDb = workIMDb }
                if let recipient, !bucket.recipients.contains(recipient) { bucket.recipients.append(recipient) }
                buckets[key] = bucket
            } else {
                order.append(key)
                var bucket = TitleAwardRowBucket(awardName: awardName, category: category, year: year, won: won, workTitle: workTitle, workIMDb: workIMDb)
                if let recipient { bucket.recipients.append(recipient) }
                buckets[key] = bucket
            }
        }
        return order.compactMap { buckets[$0]?.finished() }.filter { !isAggregate($0) }
    }

    /// Desktop's `dropGenericDuplicates` followed by `collapseAwards`, for the movie or series kind.
    static func assemble(wins: [TitleAward], nominations: [TitleAward], isSeries: Bool) -> [TitleAward] {
        collapse(dropGenericDuplicates(wins + nominations), isSeries: isSeries)
    }

    /// Desktop's `classify`, in the same order of checks.
    static func ceremony(for awardName: String) -> TitleAwardCeremony {
        let n = awardName.lowercased()
        if n.contains("academy award") || n.contains("oscar") { return .oscar }
        if n.contains("primetime emmy") || n.contains("emmy") { return .emmy }
        if n.contains("golden globe") { return .goldenGlobe }
        if n.contains("bafta tv") || n.contains("bafta television") || n.contains("british academy television") { return .baftaTV }
        if n.contains("bafta") || n.contains("british academy") { return .bafta }
        if n.contains("annie award") { return .annie }
        if n.contains("british independent film") { return .bifa }
        if n.contains("independent spirit") { return .spirit }
        if n.contains("saturn award") { return .saturn }
        if n.contains("césar award") || n.contains("cesar award") { return .cesar }
        if n.contains("goya award") { return .goya }
        if n.contains("blue dragon") { return .blueDragon }
        if n.contains("baeksang") { return .baeksang }
        if n.contains("screen actors guild") || n.contains("sag award") { return .sag }
        if n.contains("critics' choice") || n.contains("critics choice") { return .criticsChoice }
        if n.contains("palme") || n.contains("cannes") { return .cannes }
        if n.contains("golden lion") || n.contains("venice") { return .venice }
        if n.contains("golden bear") || n.contains("berlin") { return .berlin }
        return .other
    }

    /// Desktop's `awardSummary` grouping, sorted as on the detail page: each ceremony in `displayOrder`, with the
    /// won and nominated rows split, won rows newest first, and rows without a category kept only in the counts.
    static func groups(_ entries: [TitleAward]) -> [TitleAwardCeremonyGroup] {
        TitleAwardCeremony.displayOrder.compactMap { (ceremony: TitleAwardCeremony) -> TitleAwardCeremonyGroup? in
            let mine = entries.filter { $0.ceremony == ceremony }
            guard !mine.isEmpty else { return nil }
            let wins = newestFirst(mine.filter { $0.won && $0.category != nil })
            let nominations = newestFirst(mine.filter { !$0.won && $0.category != nil })
            return TitleAwardCeremonyGroup(
                ceremony: ceremony,
                wins: wins,
                nominations: nominations,
                winCount: mine.filter { $0.won }.count,
                nominationCount: mine.filter { !$0.won }.count,
                years: Array(Set(mine.compactMap { $0.year })).sorted()
            )
        }
    }

    // MARK: - Private helpers

    private static let categoryPrefixes = [
        "Academy Award for ",
        "Primetime Creative Arts Emmy Award for ",
        "Primetime Emmy Award for ",
        "Creative Arts Emmy Award for ",
        "Daytime Emmy Award for ",
        "International Emmy Award for ",
        "Golden Globe Award for ",
        "British Academy Film Award for ",
        "BAFTA TV Award for ",
        "BAFTA Television Award for ",
        "BAFTA Award for ",
        "Screen Actors Guild Award for ",
        "Critics' Choice Movie Award for ",
        "Critics' Choice Television Award for ",
        "Critics' Choice Documentary Award for ",
        "Critics' Choice Real TV Award for ",
        "Critics' Choice Super Award for ",
        "Critics' Choice Award for ",
        "Annie Award for ",
        "Independent Spirit Award for ",
        "Saturn Award for ",
    ]

    /// Desktop's `AGGREGATE_NAMES`: bodies whose own row is not a title award.
    private static let aggregateNames: Set<String> = [
        "golden globe awards", "academy awards", "bafta awards", "primetime emmy awards", "creative arts emmy awards",
        "international emmy awards", "emmy awards", "screen actors guild awards", "critics' choice awards", "tony awards",
        "grammy awards", "cannes film festival", "venice film festival", "berlin international film festival", "saturn awards",
    ]

    private static func text(_ row: JSONValue, _ key: String) -> String? {
        guard let value = row[key]["value"].string, !value.isEmpty else { return nil }
        return value
    }

    /// Desktop reads the year with `new Date(date).getFullYear()`. The literal's own year is used here, so a viewer
    /// west of UTC does not see a 1 January release shown as the previous year.
    private static func yearOf(_ date: String) -> Int? {
        let literal = date.hasPrefix("+") ? String(date.dropFirst()) : date
        let digits = String(literal.prefix(4))
        guard digits.count == 4, let year = Int(digits) else { return nil }
        return year
    }

    private static func prettyCategory(_ awardName: String, provided: String?) -> String? {
        if let provided { return provided }
        for prefix in categoryPrefixes where awardName.hasPrefix(prefix) {
            let rest = String(awardName.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return rest.isEmpty ? nil : rest
        }
        return awardName
    }

    private static func isAggregate(_ entry: TitleAward) -> Bool {
        let name = entry.awardName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = entry.awardName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBodyName = trimmed.range(of: #"\bawards$"#, options: [.regularExpression, .caseInsensitive]) != nil || aggregateNames.contains(name)
        guard isBodyName else { return false }
        let category = entry.category?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return category.isEmpty || category == name
    }

    private static func slot(_ entry: TitleAward) -> String {
        let year = entry.year.map { String($0) } ?? ""
        let category = entry.category ?? ""
        return [entry.awardName, category, year, entry.won ? "won" : "nominated"].joined(separator: "|")
    }

    private static func hasWork(_ entry: TitleAward) -> Bool {
        entry.workIMDb != nil || entry.workTitle != nil
    }

    private static func dropGenericDuplicates(_ entries: [TitleAward]) -> [TitleAward] {
        var withWork = Set<String>()
        for entry in entries where hasWork(entry) { withWork.insert(slot(entry)) }
        return entries.filter { hasWork($0) || !withWork.contains(slot($0)) }
    }

    private static func collapseKey(_ entry: TitleAward, isSeries: Bool) -> String {
        let base = entry.awardName.lowercased() + "|" + (entry.category ?? "").lowercased()
        guard isSeries else { return base }
        return base + "|" + (entry.year.map { String($0) } ?? "")
    }

    private static func score(_ entry: TitleAward) -> Int {
        (entry.won ? 1_000 : 0) + entry.recipients.count
    }

    private static func collapse(_ entries: [TitleAward], isSeries: Bool) -> [TitleAward] {
        var best: [String: TitleAward] = [:]
        var order: [String] = []
        for entry in entries {
            let key = collapseKey(entry, isSeries: isSeries)
            guard let previous = best[key] else {
                best[key] = entry
                order.append(key)
                continue
            }
            let entryWins = score(entry) > score(previous)
            let winner = entryWins ? entry : previous
            let loser = entryWins ? previous : entry
            let year = max(winner.year ?? 0, loser.year ?? 0)
            best[key] = TitleAward(
                ceremony: winner.ceremony,
                awardName: winner.awardName,
                category: winner.category,
                recipients: winner.recipients.isEmpty ? loser.recipients : winner.recipients,
                year: year == 0 ? nil : year,
                won: winner.won,
                workTitle: winner.workTitle ?? loser.workTitle,
                workIMDb: winner.workIMDb ?? loser.workIMDb
            )
        }
        let collapsed = order.compactMap { best[$0] }
        guard !isSeries else { return collapsed }
        // For a film, every row of one ceremony shares the ceremony's latest year.
        var ceremonyYear: [TitleAwardCeremony: Int] = [:]
        for entry in collapsed {
            guard let year = entry.year else { continue }
            if let current = ceremonyYear[entry.ceremony], current >= year { continue }
            ceremonyYear[entry.ceremony] = year
        }
        return collapsed.map { (entry: TitleAward) -> TitleAward in
            guard let year = ceremonyYear[entry.ceremony], entry.year != year else { return entry }
            return entry.replacingYear(year)
        }
    }

    private static func newestFirst(_ list: [TitleAward]) -> [TitleAward] {
        list.enumerated().sorted { a, b -> Bool in
            let yearA = a.element.year ?? 0
            let yearB = b.element.year ?? 0
            if yearA != yearB { return yearA > yearB }
            return a.offset < b.offset
        }.map { $0.element }
    }
}

private struct TitleAwardRowBucket {
    let awardName: String
    let category: String?
    let year: Int?
    let won: Bool
    var workTitle: String?
    var workIMDb: String?
    var recipients: [String] = []

    func finished() -> TitleAward {
        TitleAward(ceremony: TitleAwardParser.ceremony(for: awardName), awardName: awardName, category: category, recipients: recipients, year: year, won: won, workTitle: workTitle, workIMDb: workIMDb)
    }
}

/// Desktop's `runQuery` result: a status and the body, so the caller can apply Desktop's `res.ok` rule.
struct TitleAwardsReply: Sendable {
    let status: Int
    let data: Data
}

protocol TitleAwardsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> TitleAwardsReply
}

struct TitleAwardsHTTPTransport: TitleAwardsTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> TitleAwardsReply {
        guard request.url?.scheme == "https", request.url?.host == "query.wikidata.org" else { throw URLError(.badURL) }
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard data.count <= 8 * 1_024 * 1_024 else { throw URLError(.dataLengthExceedsMaximum) }
        return TitleAwardsReply(status: http.statusCode, data: data)
    }
}

/// Desktop's `fetchAwards`: both SPARQL requests run together, and a failed one leaves its side out and marks the load incomplete.
struct TitleAwardsClient: Sendable {
    let transport: any TitleAwardsTransport

    func load(imdbID: String, isSeries: Bool, allowsPerson: Bool = false) async -> TitleAwardsLoad {
        guard TitleAwardParser.isTitleID(imdbID) || (allowsPerson && TitleAwardParser.isPersonID(imdbID)) else { return TitleAwardsLoad(entries: [], complete: false) }
        async let winsBody = body(TitleAwardParser.query(imdbID: imdbID, nominations: false, allowsPerson: allowsPerson))
        async let nominationsBody = body(TitleAwardParser.query(imdbID: imdbID, nominations: true, allowsPerson: allowsPerson))
        let winsData = await winsBody
        let nominationsData = await nominationsBody
        let wins = winsData.flatMap { TitleAwardParser.rows(from: $0, won: true) } ?? []
        let nominations = nominationsData.flatMap { TitleAwardParser.rows(from: $0, won: false) } ?? []
        let entries = TitleAwardParser.assemble(wins: wins, nominations: nominations, isSeries: isSeries)
        return TitleAwardsLoad(entries: entries, complete: winsData != nil && nominationsData != nil)
    }

    private func body(_ query: String?) async -> Data? {
        guard let query, let url = TitleAwardParser.requestURL(query: query) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        guard let reply = try? await transport.send(request), (200..<300).contains(reply.status) else { return nil }
        guard (try? JSONDecoder().decode(JSONValue.self, from: reply.data)) != nil else { return nil }
        return reply.data
    }
}

/// Desktop's `QUERY` in `src/lib/providers/wikidata.ts`: awards won by the title, with `IMDB_ID` replaced by the id.
private let titleAwardWinQuery = """
SELECT DISTINCT ?award ?awardLabel ?category ?categoryLabel ?recipient ?recipientLabel ?date ?work ?workLabel ?workImdb WHERE {
  ?film wdt:P345 "IMDB_ID".
  {
    ?film p:P166 ?statement.
    ?statement ps:P166 ?award.
    OPTIONAL { ?statement pq:P585 ?date. }
    OPTIONAL { ?statement pq:P642 ?category. }
    OPTIONAL { ?statement pq:P1686 ?work. OPTIONAL { ?work wdt:P345 ?workImdb. } }
  }
  UNION
  {
    ?recipient p:P166 ?statement.
    ?statement pq:P1686 ?film.
    ?statement ps:P166 ?award.
    OPTIONAL { ?statement pq:P585 ?date. }
    OPTIONAL { ?statement pq:P642 ?category. }
    BIND(?film AS ?work)
    OPTIONAL { ?film wdt:P345 ?workImdb. }
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul". }
}
LIMIT 400
"""

/// Desktop's `NOMINATION_QUERY` (`src/lib/providers/wikidata.ts`), which uses the nominated-for property P1411.
private let titleAwardNominationQuery = """
SELECT DISTINCT ?award ?awardLabel ?category ?categoryLabel ?recipient ?recipientLabel ?date ?work ?workLabel ?workImdb WHERE {
  ?film wdt:P345 "IMDB_ID".
  {
    ?film p:P1411 ?statement.
    ?statement ps:P1411 ?award.
    OPTIONAL { ?statement pq:P585 ?date. }
    OPTIONAL { ?statement pq:P642 ?category. }
    OPTIONAL { ?statement pq:P1686 ?work. OPTIONAL { ?work wdt:P345 ?workImdb. } }
  }
  UNION
  {
    ?recipient p:P1411 ?statement.
    ?statement pq:P1686 ?film.
    ?statement ps:P1411 ?award.
    OPTIONAL { ?statement pq:P585 ?date. }
    OPTIONAL { ?statement pq:P642 ?category. }
    BIND(?film AS ?work)
    OPTIONAL { ?film wdt:P345 ?workImdb. }
  }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul". }
}
LIMIT 400
"""
