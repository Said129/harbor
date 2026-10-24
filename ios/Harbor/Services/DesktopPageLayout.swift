import Foundation

/// The wire uses public manifest/catalog identities. Configured addon URLs and
/// native hashes belong only to this device and never enter a layout document.
struct DesktopPageRowMap: Equatable, Sendable {
    let page: String
    private(set) var pairs: [String: String]
    init(page: String, rails: [PageRail] = []) {
        self.page = page
        let ids: [String]
        if page == "home" {
            ids = ["tmdb-trending-movies", "tmdb-now-playing", "tmdb-popular-movies", "tmdb-trending-tv", "tmdb-on-the-air", "tmdb-popular-tv", "tmdb-top-rated-tv", "tmdb-top-rated-movies",
                   "cm-top-movies", "cm-popular", "cm-drama", "cm-trending-tv", "cm-comedy", "cm-action", "cm-scifi", "cm-thriller", "cm-animation", "cm-horror", "cm-romance", "cm-adventure", "cm-documentary", "cm-mystery", "cm-fantasy", "cm-drama-tv", "cm-comedy-tv", "cm-crime-tv",
                   "anime-airing", "anime-new", "anime-popular", "anime-upcoming"]
            pairs = Dictionary(uniqueKeysWithValues: ids.map { ("discovery-" + $0, $0) })
        } else {
            ids = (try? DesktopAnimeRows.read().rows.map(\.key)) ?? []
            pairs = Dictionary(uniqueKeysWithValues: ids.map { ("discovery-anime-" + $0, $0) })
            pairs["discovery-anilist-trending"] = "anilistTrending"
            pairs["discovery-anilist-top100"] = "anilistTop100"
            pairs["discovery-anime-awards"] = "awards"
        }
        register(rails)
    }
    mutating func register(_ rails: [PageRail]) {
        for rail in rails {
            switch rail {
            case .discovery(let row):
                // Anime's personalized hero is not an animeRows entry on Desktop.
                if page == "home", Self.safeID(row.id) { pairs[rail.id] = row.id }
            case .catalog(let row):
                guard let manifest = row.plan.addon.manifest["id"].string, let catalog = row.plan.catalog,
                      [manifest, catalog.type, catalog.id].allSatisfy(Self.safeID) else { continue }
                pairs[rail.id] = (page == "anime" ? "addon:" : "") + manifest + "-" + catalog.type + "-" + catalog.id
            }
        }
    }
    private static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 512 && !id.contains("://") && !id.contains("?") && !id.contains("#") && !id.contains("/")
    }
    var nativeIDs: Set<String> { Set(pairs.keys) }
    var desktopIDs: Set<String> { Set(pairs.values) }
    func desktop(_ native: String) -> String? { pairs[native] }
    func native(_ desktop: String) -> [String] { pairs.filter { $0.value == desktop }.keys.sorted() }
}

/// Desktop homeRows/animeRows replace whole values. Keep unsupported/future rows,
/// customSources/listRows and fields in the shadow when editing supported rows.
struct DesktopPageLayout: Equatable, Sendable {
    let page: String
    let raw: JSONValue
    let order: [String]
    let hidden: [String]
    let renamed: [String: String]
    let numerals: [String]
    let hero: String?
    init(page: String, raw: JSONValue) throws {
        guard ["home", "anime"].contains(page), case .object(let fields) = raw,
              try JSONEncoder().encode(raw).count <= 96 * 1_024 else { throw HarborError(code: "page-sync-value") }
        func ids(_ key: String) throws -> [String] {
            guard let value = fields[key] else { return [] }
            guard case .array(let rows) = value, rows.count <= 1_000 else { throw HarborError(code: "page-sync-value") }
            return try rows.map {
                guard let id = $0.string, !id.isEmpty, id.utf8.count <= 1_024 else { throw HarborError(code: "page-sync-value") }
                return id
            }
        }
        order = try ids("order"); hidden = try ids("hidden")
        if let value = fields["renamed"] {
            guard case .object(let names) = value, names.count <= 1_000 else { throw HarborError(code: "page-sync-value") }
            renamed = try names.reduce(into: [:]) { result, pair in
                guard !pair.key.isEmpty, pair.key.utf8.count <= 1_024, let title = pair.value.string,
                      title.utf8.count <= 4_096 else { throw HarborError(code: "page-sync-value") }
                result[pair.key] = title
            }
        } else { renamed = [:] }
        if page == "home" {
            numerals = try ids("numerals")
            if let value = fields["heroSource"], value != .null {
                guard let id = value.string, id.utf8.count <= 1_024 else { throw HarborError(code: "page-sync-value") }
                hero = id
            } else { hero = nil }
            for key in ["playButtonSquare", "secondaryMoreInfo", "cwTop"] {
                if let value = fields[key], case .bool = value { continue }
                else if fields[key] != nil { throw HarborError(code: "page-sync-value") }
            }
        } else { numerals = []; hero = nil }
        self.page = page; self.raw = raw
    }
    func native(preserving local: PageLayout, mapping: DesktopPageRowMap) -> PageLayout {
        var next = local
        next.order = Self.replace(local.order, with: Self.unique(order.flatMap(mapping.native)), known: mapping.nativeIDs)
        next.hidden = local.hidden.subtracting(mapping.nativeIDs).union(hidden.flatMap(mapping.native))
        next.renamed = local.renamed.filter { !mapping.nativeIDs.contains($0.key) }
        for (id, title) in renamed { for native in mapping.native(id) { next.renamed[native] = String(title.prefix(120)) } }
        if page == "home" {
            next.numerals = local.numerals.subtracting(mapping.nativeIDs).union(numerals.flatMap(mapping.native))
            // An explicit Desktop numerals list disables the native default ranks
            // for supported rows not selected in that list.
            next.plain = local.plain.subtracting(mapping.nativeIDs).union(mapping.nativeIDs.subtracting(next.numerals))
            if let hero, let id = mapping.native(hero).first { next.heroSource = id }
            else if hero == nil || mapping.nativeIDs.contains(local.heroSource ?? "") { next.heroSource = nil }
            next.playButtonSquare = raw["playButtonSquare"] == .bool(true)
            next.secondaryMoreInfo = raw["secondaryMoreInfo"] == .bool(true)
            next.cwTop = raw["cwTop"] == .bool(true)
        }
        return next
    }
    func applying(_ local: PageLayout, mapping: DesktopPageRowMap) throws -> Self {
        guard PageCustomization.valid(local), mapping.page == page else { throw HarborError(code: "page-sync-value") }
        var fields = raw.objectValue
        fields["order"] = .array(Self.replace(order, with: Self.unique(local.order.compactMap(mapping.desktop)), known: mapping.desktopIDs).map(JSONValue.string))
        fields["hidden"] = .array(Self.unique(hidden.filter { !mapping.desktopIDs.contains($0) } + local.hidden.sorted().compactMap(mapping.desktop)).map(JSONValue.string))
        var names = renamed.filter { !mapping.desktopIDs.contains($0.key) }
        for (native, title) in local.renamed.sorted(by: { $0.key < $1.key }) {
            guard let id = mapping.desktop(native) else { continue }
            names[id] = renamed[id].map { String($0.prefix(120)) == title ? $0 : title } ?? title
        }
        fields["renamed"] = .object(names.mapValues(JSONValue.string))
        if page == "home" {
            fields["numerals"] = .array(Self.unique(numerals.filter { !mapping.desktopIDs.contains($0) } + local.numerals.sorted().compactMap(mapping.desktop)).map(JSONValue.string))
            if let selected = local.heroSource.flatMap(mapping.desktop) { fields["heroSource"] = .string(selected) }
            else if hero == nil || !mapping.native(hero!).isEmpty { fields["heroSource"] = .null }
            fields["playButtonSquare"] = .bool(local.playButtonSquare)
            fields["secondaryMoreInfo"] = .bool(local.secondaryMoreInfo)
            fields["cwTop"] = .bool(local.cwTop)
        }
        return try Self(page: page, raw: .object(fields))
    }
    private static func unique(_ ids: [String]) -> [String] { var seen = Set<String>(); return ids.filter { seen.insert($0).inserted } }
    private static func replace(_ original: [String], with selected: [String], known: Set<String>) -> [String] {
        var iterator = selected.makeIterator(), result: [String] = []
        for id in original {
            if known.contains(id) { if let next = iterator.next() { result.append(next) } }
            else { result.append(id) }
        }
        while let next = iterator.next() { result.append(next) }
        return unique(result)
    }
}
