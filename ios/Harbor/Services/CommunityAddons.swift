import Foundation

struct CommunityAddon: Identifiable, Sendable {
    let id: String
    let addon: Addon
    let slug: String
    let stars: Int
    let recentStars: Int?
    let adult: Bool
    var siteURL: URL? {
        var parts = URLComponents(string: "https://stremio-addons.net")!
        guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) else { return nil }
        parts.percentEncodedPath = "/addons/" + encoded
        return parts.url
    }
}

actor CommunityAddons {
    static let shared = CommunityAddons()
    enum Sort: String, CaseIterable, Identifiable {
        case trending, stars, createdAt
        var id: String { rawValue }
        var title: String {
            switch self { case .trending: "Tendencias"; case .stars: "Mejor valorado"; case .createdAt: "Recién agregado" }
        }
    }
    struct Spotlight: Sendable { let item: CommunityAddon; let trending: Bool }
    private struct Cached { let at: Date; let entries: [CommunityAddon] }
    private var cache: [String: Cached] = [:]
    private var pending: [String: Task<[CommunityAddon], Error>] = [:]

    func list(_ sort: Sort, allowAdult: Bool, refresh: Bool = false) async throws -> [CommunityAddon] {
        if sort == .trending {
            do {
                let rising = try await fetch("rising", refresh: refresh).filter { allowAdult || !$0.adult }
                if !rising.isEmpty { return Array(rising.prefix(24)) }
            } catch is CancellationError { throw CancellationError() }
            catch { }
            return try await list(.stars, allowAdult: allowAdult, refresh: refresh)
        }
        let query = "addons?limit=40&sort_by=\(sort.rawValue)&order=desc" + (allowAdult ? "" : "&nsfw=exclude")
        let entries = try await fetch(query, refresh: refresh)
        return Array(entries.filter { allowAdult || !$0.adult }.prefix(24))
    }

    func spotlight(allowAdult: Bool, refresh: Bool = false) async throws -> Spotlight? {
        do {
            let rising = try await fetch("rising", refresh: refresh).filter { allowAdult || !$0.adult }
            if let pick = rising.first(where: { $0.addon.backgroundURL != nil }) ?? rising.first {
                return Spotlight(item: pick, trending: true)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { }
        let top = try await list(.stars, allowAdult: allowAdult, refresh: refresh).prefix(14)
        return (top.first(where: { $0.addon.backgroundURL != nil }) ?? top.first).map { Spotlight(item: $0, trending: false) }
    }

    private func fetch(_ path: String, refresh: Bool) async throws -> [CommunityAddon] {
        if !refresh, let saved = cache[path], Date().timeIntervalSince(saved.at) < 3_600 { return saved.entries }
        let task: Task<[CommunityAddon], Error>
        if let existing = pending[path] { task = existing }
        else {
            task = Task {
                let json = try await HTTPClient().json("https://stremio-addons.net/api/v0/" + path)
                return try await Self.parse(json)
            }
            pending[path] = task
        }
        do {
            let entries = try await task.value
            pending[path] = nil
            cache[path] = Cached(at: Date(), entries: entries)
            try Task.checkCancellation()
            return entries
        } catch {
            pending[path] = nil
            throw error
        }
    }

    static func parse(_ json: JSONValue) async throws -> [CommunityAddon] {
        guard case .array(let rows) = json["addons"] else { throw HarborError(code: "addon-directory-response") }
        var result: [CommunityAddon] = [], seen = Set<String>()
        for row in rows.prefix(100) {
            try Task.checkCancellation()
            guard let uuid = row["uuid"].string, !uuid.isEmpty, uuid.utf8.count <= 200,
                  let slug = row["slug"].string, !slug.isEmpty, slug.utf8.count <= 1_024,
                  let stars = row["stars"].integer, stars >= 0,
                  let manifestID = row["manifest"]["id"].string, !manifestID.isEmpty,
                  let url = row["manifestUrl"].string, url.utf8.count <= 4_096,
                  let parts = URLComponents(string: url), parts.scheme?.lowercased() == "https",
                  parts.host != nil, parts.user == nil, parts.password == nil, parts.fragment == nil else { continue }
            do {
                let addon: Addon = try await CoreBridge().call("installAddon", ["url": .string(url), "manifest": row["manifest"]])
                guard seen.insert(uuid).inserted else { continue }
                let categories = row["categories"].array.flatMap { [$0["name"].string ?? "", $0["slug"].string ?? ""] }
                let explicitAdult = row["manifest"]["adult"] == .bool(true)
                let adult = explicitAdult || addon.adult || categories.contains { $0.range(of: #"porn|onlyfans|hentai|\bxxx\b|\bnsfw\b|\badult\b|camgirl|\bsex\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
                result.append(CommunityAddon(id: uuid, addon: addon, slug: slug, stars: stars, recentStars: row["recentStars"].integer, adult: adult))
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        guard rows.isEmpty || !result.isEmpty else { throw HarborError(code: "addon-directory-response") }
        return result
    }
}
