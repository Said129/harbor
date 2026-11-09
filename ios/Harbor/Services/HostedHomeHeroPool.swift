import Foundation

struct HomeHeroRank: Sendable {
    struct Source: Sendable {
        let label: String
        let position: Int
    }

    let position: Int
    let label: String
    let sources: [Source]

    static func fallback(for media: Media, index: Int) -> Self {
        .init(position: index + 1, label: media.episodic ? "TV" : "Movies", sources: [])
    }
}

/// Desktop's public Featured pool, shared across local profiles.
actor HostedHomeHeroPool {
    static let endpoint = "https://harborcommunity.site/feed/hero-pool.json"
    static let shared = HostedHomeHeroPool(cacheURL: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("harbor-home-hero-pool.json"))
    private static let lifetime: TimeInterval = 3 * 60 * 60
    private static let maximumBytes = 1024 * 1024

    struct Entry: Sendable {
        let media: Media
        let rank: HomeHeroRank?
    }

    struct Pool: Sendable {
        private let sources: [String: [Entry]]

        init?(_ value: JSONValue) {
            let sources = value["sources"].objectValue
            guard case .array? = sources["now"] else { return nil }
            self.sources = sources.filter { ["now", "trakt", "simkl"].contains($0.key) && $0.value != .null }.mapValues { value in
                value.array.prefix(100).compactMap(Self.entry)
            }
        }

        func entries(for feed: HeroLayoutPolicy.HeroFeed) -> [Entry] {
            guard feed != .classic else { return [] }
            let key = feed == .trending ? "now" : feed.rawValue
            return sources[key] ?? sources["now"] ?? []
        }

        private static func entry(_ value: JSONValue) -> Entry? {
            guard let kind = value["type"].string, ["movie", "series"].contains(kind),
                  let background = image(value["background"].string),
                  var media = Media.parse(value, kind: kind) else { return nil }
            media.background = background
            media.logo = image(media.logo)
            media.poster = image(media.poster)
            media.addonOrigin = nil
            let ranks: [HomeHeroRank.Source] = value["sources"].array.prefix(12).compactMap { source in
                guard let label = source["label"].string, !label.isEmpty,
                      let position = source["rank"].integer, position > 0 else { return nil }
                return .init(label: label, position: position)
            }
            let rank: HomeHeroRank?
            if let position = value["rank"].integer, position > 0 {
                rank = .init(position: position, label: value["rankLabel"].string.flatMap { $0.isEmpty ? nil : $0 }
                    ?? HomeHeroRank.fallback(for: media, index: 0).label, sources: ranks)
            } else {
                rank = nil
            }
            return .init(media: media, rank: rank)
        }

        private static func image(_ value: String?) -> String? {
            guard let value, let url = URL(string: value), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil else { return nil }
            return value
        }
    }

    private struct Cache: Codable {
        let fetchedAt: Date
        let payload: JSONValue
    }

    private let cacheURL: URL?
    private let fetch: @Sendable (String) async throws -> JSONValue
    private let now: @Sendable () -> Date
    private var restored = false
    private var pool: Pool?
    private var nextCheck = Date.distantPast
    private var inflight: Task<Pool?, Never>?

    init(cacheURL: URL? = nil, fetch: @escaping @Sendable (String) async throws -> JSONValue = { try await HTTPClient().json($0) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.cacheURL = cacheURL
        self.fetch = fetch
        self.now = now
    }

    func load(for feed: HeroLayoutPolicy.HeroFeed) async -> Pool? {
        guard feed != .classic else { return nil }
        restore()
        if let inflight { return await inflight.value }
        guard now() >= nextCheck else { return pool }
        let task = Task { await self.refresh() }
        inflight = task
        return await task.value
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL), data.count <= Self.maximumBytes,
              let cache = try? JSONDecoder().decode(Cache.self, from: data), let restoredPool = Pool(cache.payload) else { return }
        pool = restoredPool
        nextCheck = min(cache.fetchedAt, now()).addingTimeInterval(Self.lifetime)
    }

    private func refresh() async -> Pool? {
        defer { inflight = nil }
        guard let payload = try? await fetch(Self.endpoint), let updated = Pool(payload) else {
            nextCheck = now().addingTimeInterval(5 * 60)
            return pool
        }
        let fetchedAt = now()
        pool = updated
        nextCheck = fetchedAt.addingTimeInterval(Self.lifetime)
        if let cacheURL, let data = try? JSONEncoder().encode(Cache(fetchedAt: fetchedAt, payload: payload)),
           data.count <= Self.maximumBytes {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return updated
    }
}
