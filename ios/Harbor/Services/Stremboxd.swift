import Foundation

/// Desktop's Letterboxd bridge through Stremboxd (`lib/stremboxd/config.ts`, `settings-helper.ts`, `types.ts`, `to-meta.ts`,
/// `home-rails.ts`). Pure value logic only: configuration encoding, URLs, response mapping and rail naming and ordering.
/// The network lives in `StremboxdClient.swift`, the account state in `ViewModels/StremboxdAccount.swift`.

enum StremboxdMode: String, Codable, Equatable, Sendable {
    case publicMode = "public"
    case full
}

/// A Letterboxd list added by address (Desktop's `LetterboxdListRef`).
struct StremboxdListRef: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var owner: String?
    var filmCount: Int?
}

/// Desktop's `LetterboxdSettings` (`lib/settings/types.ts`, defaults in `lib/settings/defaults.ts`). Holds no secret: the password is never stored.
struct StremboxdSettings: Codable, Equatable, Sendable {
    static let defaultCatalogs = [
        StremboxdCatalogID.watchlist,
        StremboxdCatalogID.liked,
        StremboxdCatalogID.popular,
        StremboxdCatalogID.top250,
    ]

    var enabled = false
    var mode = StremboxdMode.publicMode
    var username = ""
    var selectedCatalogs = StremboxdSettings.defaultCatalogs
    var hiddenCatalogs: [String] = []
    var catalogOrder: [String] = []
    var showRatingsOnPosters = true
    var listRefs: [StremboxdListRef] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try container.decodeIfPresent(StremboxdMode.self, forKey: .mode) ?? .publicMode
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        selectedCatalogs = try container.decodeIfPresent([String].self, forKey: .selectedCatalogs) ?? StremboxdSettings.defaultCatalogs
        hiddenCatalogs = try container.decodeIfPresent([String].self, forKey: .hiddenCatalogs) ?? []
        catalogOrder = try container.decodeIfPresent([String].self, forKey: .catalogOrder) ?? []
        showRatingsOnPosters = try container.decodeIfPresent(Bool.self, forKey: .showRatingsOnPosters) ?? true
        listRefs = try container.decodeIfPresent([StremboxdListRef].self, forKey: .listRefs) ?? []
    }
}

/// The Letterboxd account Stremboxd signed in (Desktop's `LetterboxdSession`). Kept in the Keychain; `userToken` is Stremboxd's token.
struct StremboxdSession: Codable, Equatable, Sendable {
    var userToken: String
    var userId: String
    var username: String
    var displayName: String?
    /// Milliseconds since 1970, as on Desktop.
    var loginAt: Double
    var lists: [StremboxdListRef]

    /// Desktop's `session?.displayName || session?.username`, the name the full-mode row titles use.
    var rowName: String {
        if let displayName = displayName, !displayName.isEmpty { return displayName }
        return username
    }
}

/// Catalog ids as Stremboxd names them (`home-rails.ts`).
enum StremboxdCatalogID {
    static let watchlist = "letterboxd-watchlist"
    static let diary = "letterboxd-diary"
    static let liked = "letterboxd-liked"
    static let likedFilms = "letterboxd-liked-films"
    static let friends = "letterboxd-friends"
    static let recommended = "letterboxd-recommended"
    static let popular = "letterboxd-popular"
    static let top250 = "letterboxd-top250"
    static let listPrefix = "letterboxd-list-"

    static func list(_ id: String) -> String { listPrefix + id }
}

/// Desktop's catalog ordering, naming and visibility rules (`home-rails.ts`).
enum StremboxdRails {
    /// The row needs at least this many films on its first page (Desktop's `MIN_ROW_METAS`).
    static let minimumMetas = 4
    /// Stremboxd pages catalogs 100 at a time (Desktop's `PAGE_SIZE`).
    static let pageSize = 100

    /// Rows that need a signed-in account (Desktop's `FULL_MODE_CATALOG_IDS`).
    static let fullOnly: Set<String> = [StremboxdCatalogID.diary, StremboxdCatalogID.friends, StremboxdCatalogID.recommended]

    private static let priority: [String: Int] = [
        StremboxdCatalogID.watchlist: 0,
        StremboxdCatalogID.diary: 1,
        StremboxdCatalogID.liked: 2,
        StremboxdCatalogID.likedFilms: 2,
        StremboxdCatalogID.friends: 3,
        StremboxdCatalogID.recommended: 4,
        StremboxdCatalogID.popular: 5,
        StremboxdCatalogID.top250: 6,
    ]

    /// Desktop's `DEFAULT_NAMES`, English source strings.
    private static let defaultNames: [String: String] = [
        StremboxdCatalogID.watchlist: "Letterboxd Watchlist",
        StremboxdCatalogID.diary: "Recent Diary",
        StremboxdCatalogID.liked: "Liked Films",
        StremboxdCatalogID.likedFilms: "Liked Films",
        StremboxdCatalogID.friends: "Friends' Activity",
        StremboxdCatalogID.recommended: "Recommended for You",
        StremboxdCatalogID.popular: "Popular This Week",
        StremboxdCatalogID.top250: "Top 250 Narrative Features",
    ]

    /// Desktop's `FULL_NAME_TEMPLATES`, English source strings with `{name}`.
    private static let fullTemplates: [String: String] = [
        StremboxdCatalogID.watchlist: "{name}'s Watchlist",
        StremboxdCatalogID.diary: "{name}'s Recent Diary",
        StremboxdCatalogID.liked: "{name}'s Liked Films",
        StremboxdCatalogID.likedFilms: "{name}'s Liked Films",
        StremboxdCatalogID.friends: "{name}'s Friends Activity",
        StremboxdCatalogID.recommended: "Recommended for {name}",
        StremboxdCatalogID.popular: "Popular This Week",
        StremboxdCatalogID.top250: "Top 250 Narrative Features",
    ]

    /// Full mode reads liked films under another id (`PUBLIC_TO_FULL_ID`).
    static func realCatalogID(_ id: String, full: Bool) -> String {
        guard full, id == StremboxdCatalogID.liked else { return id }
        return StremboxdCatalogID.likedFilms
    }

    /// Desktop's `buildLetterboxdHomeRows` ordering: an explicit order first, then the built-in priority, then the id.
    /// Hidden catalogs are left out.
    static func orderedVisible(selected: [String], hidden: [String], order: [String]) -> [String] {
        let hiddenSet = Set(hidden)
        let visible = selected.filter { !hiddenSet.contains($0) }
        var explicitRank: [String: Int] = [:]
        for (index, id) in order.enumerated() { explicitRank[id] = index }
        func sortKey(_ id: String) -> Int {
            if let explicit = explicitRank[id] { return explicit }
            return (priority[id] ?? 99) + 1000
        }
        return visible.sorted { (first: String, second: String) -> Bool in
            let firstKey = sortKey(first)
            let secondKey = sortKey(second)
            if firstKey != secondKey { return firstKey < secondKey }
            return first < second
        }
    }

    static func keepsRow(metaCount: Int) -> Bool {
        metaCount >= minimumMetas
    }

    /// The name of one row. Server names win, then the list's own name, then Desktop's English fallbacks.
    enum RowName: Equatable {
        /// A name the manifest gave, already final.
        case server(String)
        /// A custom list, with its owner when known.
        case list(name: String, owner: String?)
        /// An English template with `{name}` to fill from the signed-in account.
        case template(String, name: String)
        /// An English default name.
        case fallback(String)
        /// Nothing known; the catalog id is shown.
        case unnamed(String)
    }

    static func rowName(catalogID: String, realID: String, full: Bool, displayName: String, manifestName: String?, list: StremboxdListRef?) -> RowName {
        if let manifestName = manifestName, !manifestName.isEmpty { return .server(manifestName) }
        if let list = list { return .list(name: list.name, owner: list.owner) }
        if full, let template = fullTemplates[realID] { return .template(template, name: displayName) }
        if let name = defaultNames[catalogID] ?? defaultNames[realID] { return .fallback(name) }
        return .unnamed(catalogID)
    }
}

/// Stremboxd's `/:config` segment (`config.ts`): base64url of the JSON configuration. The configure page builds the same shape.
struct StremboxdPublicConfig: Codable, Equatable, Sendable {
    struct Catalogs: Codable, Equatable, Sendable {
        var watchlist: Bool?
        var popular: Bool
        var top250: Bool
        var likedFilms: Bool?
    }

    var u: String?
    var c: Catalogs
    var l: [String]
    var r: Bool
}

enum StremboxdConfigCodec {
    /// Desktop's `buildStremboxdConfig`: the username is optional, the catalog toggles map to `c`, lists to `l`.
    static func publicConfig(_ settings: StremboxdSettings) -> StremboxdPublicConfig {
        let selected = Set(settings.selectedCatalogs)
        let username = settings.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalogs = StremboxdPublicConfig.Catalogs(
            watchlist: selected.contains(StremboxdCatalogID.watchlist) ? true : nil,
            popular: selected.contains(StremboxdCatalogID.popular),
            top250: selected.contains(StremboxdCatalogID.top250),
            likedFilms: selected.contains(StremboxdCatalogID.liked) ? true : nil
        )
        return StremboxdPublicConfig(
            u: username.isEmpty ? nil : username,
            c: catalogs,
            l: settings.listRefs.map { $0.id },
            r: settings.showRatingsOnPosters
        )
    }

    static func encode(_ config: StremboxdPublicConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(config)
        return base64URL(data)
    }

    static func decode(_ segment: String) -> StremboxdPublicConfig? {
        var base = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        guard let data = Data(base64Encoded: base) else { return nil }
        return try? JSONDecoder().decode(StremboxdPublicConfig.self, from: data)
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Where catalogs come from: the public configuration segment, or the signed-in account's user id (Desktop's full mode).
enum StremboxdSource: Equatable, Sendable {
    case config(String)
    case full(String)
}

/// Stremboxd's HTTPS addresses (`client.ts`). Path parts are checked, so a value cannot change the host or the route.
enum StremboxdURL {
    static let host = "api.stremboxd.com"
    static let base = "https://" + host

    /// Desktop's "About Stremboxd" link.
    static let configure = URL(string: "https://stremboxd.com/configure")

    static func allowed(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "https" && parts.host == host && parts.user == nil && parts.password == nil && parts.port == nil
    }

    static func endpoint(_ path: String) -> URL? {
        URL(string: base + path)
    }

    static func manifest(_ source: StremboxdSource) -> URL? {
        switch source {
        case .config(let segment):
            guard isSegment(segment) else { return nil }
            return URL(string: base + "/" + segment + "/manifest.json")
        case .full(let userID):
            guard isSegment(userID) else { return nil }
            return URL(string: base + "/stremio/" + userID + "/manifest.json")
        }
    }

    static func catalog(_ source: StremboxdSource, catalogID: String, skip: Int) -> URL? {
        guard isCatalogID(catalogID), skip >= 0, let root = sourceRoot(source) else { return nil }
        let suffix = skip > 0 ? "/skip=\(skip).json" : ".json"
        return URL(string: root + "/catalog/movie/" + catalogID + suffix)
    }

    private static func sourceRoot(_ source: StremboxdSource) -> String? {
        switch source {
        case .config(let segment):
            return isSegment(segment) ? base + "/" + segment : nil
        case .full(let userID):
            return isSegment(userID) ? base + "/stremio/" + userID : nil
        }
    }

    private static func isSegment(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{1,4096}$", options: .regularExpression) != nil
    }

    private static func isCatalogID(_ value: String) -> Bool {
        // List ids may carry capitals and underscores, so the catalog id keeps them.
        value.range(of: "^[A-Za-z0-9_-]{1,160}$", options: .regularExpression) != nil
    }
}

/// Desktop's `stremboxdMetaToMeta`: a Stremboxd catalog item becomes a movie `Media`.
enum StremboxdMapping {
    static func media(_ meta: JSONValue) -> Media? {
        guard case .object(var fields) = meta else { return nil }
        // Desktop always reports these as movies, whatever the item says.
        fields["type"] = .string("movie")
        guard var media = Media.parse(.object(fields), kind: "movie") else { return nil }
        if media.releaseInfo == nil, let year = meta["year"].integer { media.releaseInfo = String(year) }
        return media
    }

    /// The films of one catalog page, in the order Stremboxd sent them.
    static func catalog(_ page: JSONValue) -> [Media] {
        page["metas"].array.compactMap { (meta: JSONValue) -> Media? in media(meta) }
    }

    enum ManifestCheck: Equatable {
        case valid(catalogs: Int, hasWatchlist: Bool)
        /// Desktop's English message for the person.
        case invalid(String)
    }

    /// Desktop's manifest checks in `validateStremboxdConfig`.
    static func check(manifest: JSONValue, expectWatchlist: Bool) -> ManifestCheck {
        guard manifest["id"].string == "community.stremboxd" else {
            return .invalid("Unexpected manifest from Stremboxd.")
        }
        let catalogs = manifest["catalogs"].array
        guard !catalogs.isEmpty else {
            return .invalid("No catalogs returned for this configuration.")
        }
        let hasWatchlist = catalogs.contains { (catalog: JSONValue) -> Bool in catalog["id"].string == StremboxdCatalogID.watchlist }
        if expectWatchlist && !hasWatchlist {
            return .invalid("Letterboxd did not return a watchlist for this username. Check the username is correct and public.")
        }
        return .valid(catalogs: catalogs.count, hasWatchlist: hasWatchlist)
    }

    /// Desktop's `buildServerPreferences`: the catalogs and lists Stremboxd should show for a full-mode account.
    static func preferences(selected: [String], listRefs: [StremboxdListRef]) -> JSONValue {
        let chosen = Set(selected)
        var catalogs: [String: JSONValue] = [:]
        catalogs["watchlist"] = .bool(chosen.contains(StremboxdCatalogID.watchlist))
        catalogs["diary"] = .bool(chosen.contains(StremboxdCatalogID.diary))
        catalogs["friends"] = .bool(chosen.contains(StremboxdCatalogID.friends))
        catalogs["popular"] = .bool(chosen.contains(StremboxdCatalogID.popular))
        catalogs["top250"] = .bool(chosen.contains(StremboxdCatalogID.top250))
        catalogs["likedFilms"] = .bool(chosen.contains(StremboxdCatalogID.liked))
        catalogs["recommended"] = .bool(chosen.contains(StremboxdCatalogID.recommended))
        let lists: [JSONValue] = listRefs.map { (ref: StremboxdListRef) -> JSONValue in JSONValue.string(ref.id) }
        var preferences: [String: JSONValue] = [:]
        preferences["catalogs"] = .object(catalogs)
        preferences["ownLists"] = .array(lists)
        preferences["externalLists"] = .array([])
        preferences["showActions"] = .bool(true)
        preferences["showRatings"] = .bool(true)
        return .object(preferences)
    }

    static func loginBody(username: String, password: String, totp: String?) -> JSONValue {
        var body: [String: JSONValue] = [:]
        body["username"] = .string(username)
        body["password"] = .string(password)
        if let totp = totp, !totp.isEmpty { body["totp"] = .string(totp) }
        return .object(body)
    }

    /// Desktop's login response (`LetterboxdLoginResponse`) as a session. Nil when the token or the user is missing.
    static func session(fromLogin json: JSONValue, loginAt: Double) -> StremboxdSession? {
        guard let token = json["userToken"].string, !token.isEmpty,
              let userID = json["user"]["id"].string, !userID.isEmpty,
              let username = json["user"]["username"].string, !username.isEmpty else { return nil }
        let lists: [StremboxdListRef] = json["lists"].array.compactMap { (value: JSONValue) -> StremboxdListRef? in listRef(value) }
        return StremboxdSession(
            userToken: token,
            userId: userID,
            username: username,
            displayName: json["user"]["displayName"].string,
            loginAt: loginAt,
            lists: lists
        )
    }

    /// Desktop's `LetterboxdListRef`. Stremboxd may send the id as a number.
    static func listRef(_ json: JSONValue) -> StremboxdListRef? {
        let id: String
        if let text = json["id"].string {
            id = text
        } else if let number = json["id"].integer {
            id = String(number)
        } else {
            return nil
        }
        guard !id.isEmpty, let name = json["name"].string, !name.isEmpty else { return nil }
        return StremboxdListRef(id: id, name: name, owner: json["owner"].string, filmCount: json["filmCount"].integer)
    }
}
