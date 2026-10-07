import Foundation

struct CommunityAddon: Identifiable, Sendable {
    let id: String
    let addon: Addon
    let slug: String
    let stars: Int
    let recentStars: Int?
    let adult: Bool
    var categories: Set<String> = []
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
    struct Page: Sendable { let entries: [CommunityAddon]; let nextPage: Int? }
    private struct Payload: Sendable { let entries: [CommunityAddon]; let pagination: JSONValue }
    private struct Cached { let at: Date; let payload: Payload }
    private struct Pending { let id: UUID; let task: Task<Payload, Error> }
    private var cache: [String: Cached] = [:]
    private var pending: [String: Pending] = [:]

    static func browsePath(page: Int, sort: Sort, category: AddonCategory, query: String, allowAdult: Bool) -> String {
        var parts = URLComponents()
        parts.path = "addons"
        parts.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "sort_by", value: sort == .createdAt ? "createdAt" : "stars"), URLQueryItem(name: "order", value: "desc")]
        if !allowAdult { parts.queryItems?.append(URLQueryItem(name: "nsfw", value: "exclude")) }
        if let slug = category.communitySlug { parts.queryItems?.append(URLQueryItem(name: "category", value: slug)) }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty { parts.queryItems?.append(URLQueryItem(name: "search", value: search)) }
        // The index decodes query strings as forms: a literal '+' in its category
        // slugs must survive as '+' rather than become a space.
        return (parts.string ?? "addons").replacingOccurrences(of: "+", with: "%2B")
    }

    func browse(page: Int, sort: Sort, category: AddonCategory, query: String, allowAdult: Bool, refresh: Bool = false) async throws -> Page {
        guard (1...10_000).contains(page), query.utf8.count <= 2_048 else { throw HarborError(code: "addon-directory-response") }
        if sort == .trending {
            do {
                let rising = try await fetch("rising", refresh: refresh)
                if !rising.isEmpty {
                    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    let matching = rising.filter { item in
                        (allowAdult || !item.adult) &&
                        (category.communitySlug.map { item.categories.contains($0) } ?? true) &&
                        (search.isEmpty || (item.addon.name + " " + (item.addon.manifest["description"].string ?? "") + " " + item.slug).localizedCaseInsensitiveContains(search))
                    }
                    return Page(entries: matching, nextPage: nil)
                }
            } catch is CancellationError { throw CancellationError() }
            catch { }
        }
        let path = Self.browsePath(page: page, sort: sort, category: category, query: query, allowAdult: allowAdult)
        let payload = try await fetchPayload(path, refresh: refresh)
        let next: Int?
        do { next = try Self.nextPage(payload.pagination, expectedPage: page) }
        catch { cache[path] = nil; throw error }
        return Page(entries: payload.entries.filter { allowAdult || !$0.adult }, nextPage: next)
    }

    static func nextPage(_ value: JSONValue, expectedPage: Int) throws -> Int? {
        guard value["page"].integer == expectedPage,
              let limit = value["limit"].integer, (1...100).contains(limit),
              let total = value["total"].integer, total >= 0,
              let pages = value["totalPages"].integer, pages >= 0, pages <= 10_000,
              case .bool(let more) = value["hasNextPage"],
              !more || expectedPage < pages else { throw HarborError(code: "addon-directory-response") }
        return more ? expectedPage + 1 : nil
    }

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
        try await fetchPayload(path, refresh: refresh).entries
    }

    private func fetchPayload(_ path: String, refresh: Bool) async throws -> Payload {
        if !refresh, let saved = cache[path], Date().timeIntervalSince(saved.at) < 3_600 { return saved.payload }
        let work: Pending
        if let existing = pending[path] { work = existing }
        else {
            let task = Task {
                let json = try await HTTPClient().json("https://stremio-addons.net/api/v0/" + path)
                return Payload(entries: try await Self.parse(json), pagination: json["pagination"])
            }
            work = Pending(id: UUID(), task: task)
            pending[path] = work
        }
        do {
            let payload = try await work.task.value
            if pending[path]?.id == work.id {
                pending[path] = nil
                cache[path] = Cached(at: Date(), payload: payload)
                while cache.count > 48, let oldest = cache.min(by: { $0.value.at < $1.value.at })?.key { cache[oldest] = nil }
            }
            try Task.checkCancellation()
            return payload
        } catch {
            if pending[path]?.id == work.id { pending[path] = nil }
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
                let slugs = Set(row["categories"].array.compactMap { $0["slug"].string })
                result.append(CommunityAddon(id: uuid, addon: addon, slug: slug, stars: stars, recentStars: row["recentStars"].integer, adult: adult, categories: slugs))
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        guard rows.isEmpty || !result.isEmpty else { throw HarborError(code: "addon-directory-response") }
        return result
    }
}
