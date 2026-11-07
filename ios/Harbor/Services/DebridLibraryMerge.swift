import Foundation

/// Desktop's debrid library merge (`fetchLibraryStreams` and `matchEntry` in `src/lib/streams/library.ts`,
/// `mergeAndDedupe` in `src/lib/streams/pipeline.ts`). Titles the person already holds on a debrid service
/// are offered as streams of their own. A library stream and an addon stream with the same identity become
/// one entry that lists both contributors.
/// Matching is pure. The listing comes from the caller (`DebridClient.listLibrary` through `Lister`), and
/// the title fields come from a `Parser` the caller supplies. Desktop uses parse-torrent-title for that.
enum DebridLibraryMerge {
    /// Desktop's LibraryQuery: what the title and episode being played are.
    struct Query: Equatable, Sendable {
        enum Kind: String, Sendable { case movie, series }
        var type: Kind
        var title: String
        var year: Int?
        var season: Int?
        var episode: Int?
    }

    /// One library entry of one provider. `files` is empty when the provider listing does not carry files.
    struct Item: Equatable, Sendable {
        var provider: DebridProvider
        var hash: String
        var name: String
        var files: [String] = []
    }

    /// The title fields Desktop reads from parse-torrent-title for one name.
    struct Title: Equatable, Sendable {
        var title: String?
        var year: Int?
        var season: Int?
        var episode: Int?
        var resolution: String?
        var codec: String?
    }

    /// Desktop's MatchInfo.
    struct Match: Equatable, Sendable {
        var fileIndex: Int?
        var parsedTitle: String
        var resolution: String?
        var codec: String?
    }

    typealias Parser = (String) -> Title
    /// One `listLibrary` per provider. Nil when the provider failed, and that provider contributes nothing.
    typealias Lister = @Sendable (DebridProvider) async -> [Item]?

    /// Desktop's fetchLibraryStreams listing step: every configured provider is asked at the same time, and the
    /// results keep the provider order.
    static func listings(providers: [DebridProvider], list: @escaping Lister) async -> [Item] {
        let grouped = await withTaskGroup(of: (Int, [Item]).self) { group -> [[Item]] in
            for (index, provider) in providers.enumerated() {
                group.addTask {
                    let items = await list(provider)
                    return (index, items ?? [])
                }
            }
            var byIndex = [[Item]](repeating: [], count: providers.count)
            for await (index, items) in group { byIndex[index] = items }
            return byIndex
        }
        return grouped.flatMap { $0 }
    }

    /// Desktop's fetchLibraryStreams matching: each entry with a hash that matches the query becomes one stream.
    static func streams(items: [Item], query: Query, parse: Parser) -> [JSONValue] {
        var out: [JSONValue] = []
        for item in items where !item.hash.isEmpty {
            guard let found = match(item, query: query, parse: parse) else { continue }
            out.append(stream(item, found))
        }
        return out
    }

    /// Desktop's matchEntry: the files first, then the entry name, then the positional episode match.
    static func match(_ item: Item, query: Query, parse: Parser) -> Match? {
        for (index, file) in item.files.enumerated() {
            if let found = check(file, query: query, fileIndex: index, parse: parse) { return found }
        }
        if let found = check(item.name, query: query, fileIndex: nil, parse: parse) { return found }
        return positional(item, query: query, parse: parse)
    }

    /// Desktop's checkText.
    static func check(_ text: String, query: Query, fileIndex: Int?, parse: Parser) -> Match? {
        let info = parse(text)
        if query.type == .movie, let expected = query.year, let year = info.year, abs(year - expected) > 1 { return nil }
        if let season = query.season, let found = info.season, found != season { return nil }
        if let episode = query.episode, let found = info.episode, found != episode { return nil }
        if query.type == .series, query.season != nil || query.episode != nil, info.season == nil, info.episode == nil { return nil }
        let wanted = normalize(query.title)
        let candidate = normalize(info.title ?? text)
        if wanted.utf16.count < 2 || candidate.utf16.count < 2 { return nil }
        guard candidate.range(of: wanted) != nil || wanted.range(of: candidate) != nil else { return nil }
        return Match(fileIndex: fileIndex, parsedTitle: info.title ?? text, resolution: info.resolution, codec: info.codec)
    }

    /// Desktop's positionalMatch: a series episode that is the nth video file of a multi-file pack whose
    /// title matches. Only works when the listing carries files.
    static func positional(_ item: Item, query: Query, parse: Parser) -> Match? {
        guard query.type == .series, let episode = query.episode, item.files.count >= 2 else { return nil }
        guard titleMatches(item, query: query, parse: parse) else { return nil }
        let videos = item.files.enumerated().filter { entry in
            matches(videoPattern, entry.element) && !matches(nonEpisodePattern, entry.element)
        }.map { (name: $0.element, index: $0.offset) }
        guard videos.count >= 2 else { return nil }
        let sorted = videos.sorted { left, right in
            left.name.compare(right.name, options: [.numeric, .caseInsensitive, .diacriticInsensitive]) == .orderedAscending
        }
        let position = episode - 1
        guard position >= 0, position < sorted.count else { return nil }
        let chosen = sorted[position]
        let info = parse(chosen.name)
        return Match(fileIndex: chosen.index, parsedTitle: info.title ?? chosen.name, resolution: info.resolution, codec: info.codec)
    }

    /// Desktop's titleMatchesEntry.
    static func titleMatches(_ item: Item, query: Query, parse: Parser) -> Bool {
        let wanted = normalize(query.title)
        if wanted.utf16.count < 2 { return false }
        let texts = [item.name] + item.files
        return texts.contains { text in
            let candidate = normalize(parse(text).title ?? text)
            return candidate.utf16.count >= 2 && (candidate.range(of: wanted) != nil || wanted.range(of: candidate) != nil)
        }
    }

    /// Desktop's `normalize`: lower case, compatibility decomposition, and no spaces or punctuation.
    static func normalize(_ text: String) -> String {
        text.lowercased().decomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: #"[\s.\-_()\[\]:;,!?'"‘’“”–—]+"#, with: "", options: .regularExpression)
    }

    /// Desktop's buildLibraryStream. Desktop builds this label as a plain template literal, not through its
    /// translation table, so the English "Library" is kept as written there.
    static func stream(_ item: Item, _ found: Match) -> JSONValue {
        let index = found.fileIndex ?? 0
        let filename = index < item.files.count ? item.files[index] : item.name
        let providerName = item.provider.name
        let addonName = providerName + " Library"
        let cacheTag = "[" + item.provider.rawValue.uppercased() + "+]"
        var fields: [String: JSONValue] = [
            "name": .string(filename),
            "title": .string(cacheTag + " " + addonName),
            "infoHash": .string(item.hash),
            "addonId": .string(item.provider.rawValue + "-library"),
            "addonName": .string(addonName),
        ]
        if let fileIndex = found.fileIndex { fields["fileIdx"] = .integer(Int64(fileIndex)) }
        return .object(fields)
    }

    /// Desktop's mergeAndDedupe. Library streams come first, then addon streams. Streams with the same identity
    /// become one entry: its contributors list every addon that offered it, its sources are united, and a missing
    /// URL is filled from the later stream.
    static func mergeAndDedupe(library: [JSONValue], addons: [JSONValue]) -> [JSONValue] {
        var order: [String] = []
        var seen: [String: [String: JSONValue]] = [:]
        for stream in library {
            let key = identity(stream)
            var entry = stream.objectValue
            entry["contributors"] = .array([contributor(stream)])
            if seen[key] == nil { order.append(key) }
            seen[key] = entry
        }
        for stream in addons {
            let key = identity(stream)
            guard var prior = seen[key] else {
                var entry = stream.objectValue
                entry["contributors"] = .array([contributor(stream)])
                order.append(key)
                seen[key] = entry
                continue
            }
            addContributor(&prior, stream)
            let sources = stream["sources"].array.compactMap { $0.string }
            if !sources.isEmpty {
                var united: [String] = []
                let known: [String] = (prior["sources"]?.array ?? []).compactMap { $0.string }
                for source in known + sources where !united.contains(source) {
                    united.append(source)
                }
                prior["sources"] = .array(united.map(JSONValue.string))
            }
            if (prior["url"]?.string ?? "").isEmpty, let url = stream["url"].string, !url.isEmpty { prior["url"] = .string(url) }
            seen[key] = prior
        }
        return order.compactMap { key in seen[key].map { JSONValue.object($0) } }
    }

    /// Desktop's streamKey.
    static func identity(_ stream: JSONValue) -> String {
        if let hash = stream["infoHash"].string, !hash.isEmpty {
            return "hash:" + hash.lowercased() + ":" + fileIndexText(stream["fileIdx"])
        }
        if let url = stream["url"].string, !url.isEmpty { return "url:" + url }
        return "n:" + (stream["name"].string ?? "") + ":" + (stream["title"].string ?? "")
    }

    private static func contributor(_ stream: JSONValue) -> JSONValue {
        .object(["id": stream["addonId"], "name": stream["addonName"]])
    }

    private static func addContributor(_ entry: inout [String: JSONValue], _ stream: JSONValue) {
        var list = entry["contributors"]?.array ?? []
        let id = stream["addonId"]
        if !list.contains(where: { $0["id"] == id }) { list.append(contributor(stream)) }
        entry["contributors"] = .array(list)
    }

    private static func fileIndexText(_ value: JSONValue) -> String {
        switch value {
        case .integer(let number): String(number)
        case .unsigned(let number): String(number)
        case .number(let number): String(number)
        case .string(let text): text
        default: ""
        }
    }

    /// The production lister: the profile's DebridClient. A provider without a key, or one whose listing
    /// fails, yields nil and contributes nothing, as Desktop skips a failed listing.
    static func lister(_ client: DebridClient?) -> Lister {
        { provider in
            guard let client, let outcome = try? await client.listLibrary(provider), let entries = outcome.value else { return nil }
            return entries.map { Item(provider: provider, hash: $0.hash, name: $0.name, files: ($0.files ?? []).compactMap { $0.name }) }
        }
    }

    private static let videoPattern = #"\.(mkv|mp4|avi|mov|m4v|webm|ts|flv|wmv|m2ts|mpg|mpeg|ogv|3gp)(\?|#|$)"#
    private static let nonEpisodePattern = #"(?:^|[^a-z0-9])(?:ncop|nced|creditless|opening|ending|preview|trailer|extra|special|sample|menu|bonus|interview|making|scan|booklet|ost)(?:[^a-z0-9]|$)"#

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
