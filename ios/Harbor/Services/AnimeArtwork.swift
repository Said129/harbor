import Foundation

/// Harbor's original public art index, with its daily public update.
actor AnimeArtwork {
    static let shared = AnimeArtwork()
    private struct Art: Decodable, Sendable {
        let bg: String?
        let logo: String?
        let desc: String?
    }
    private struct Index: Decodable, Sendable { let v: Int?; let art: [String: Art] }
    private var art: [String: Art] = [:]
    private var loaded = false
    private var refreshing = false
    private var checked = Date.distantPast
    private var minimumEntryCount = 1
    private var cacheURL: URL? {
        try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("harbor-anime-hero-art.json")
    }
    func enrich(_ items: [Media]) async -> [Media] {
        loadSeed()
        if !refreshing, Date().timeIntervalSince(checked) >= 24 * 60 * 60 {
            refreshing = true
            Task { await refresh() }
        }
        return items.map { original in
            guard let entry = art[original.id] else { return original }
            var media = original
            if let background = Self.image(entry.bg) { media.background = background }
            if let logo = Self.image(entry.logo) { media.logo = logo }
            if let description = entry.desc, media.description?.isEmpty != false { media.description = description }
            return media
        }
    }
    private func loadSeed() {
        guard !loaded else { return }
        loaded = true
        if let url = Bundle.main.url(forResource: "DesktopAnimeArtwork", withExtension: "json"),
           let data = try? Data(contentsOf: url), let seed = try? JSONDecoder().decode(Index.self, from: data) {
            art = seed.art; minimumEntryCount = max(1, Int(ceil(Double(seed.art.count) * 0.9)))
        }
        if let url = cacheURL, let data = try? Data(contentsOf: url), data.count <= 8 * 1024 * 1024,
           let cache = try? JSONDecoder().decode(Index.self, from: data), cache.art.count >= minimumEntryCount {
            art = cache.art
            checked = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
    }
    private func refresh() async {
        defer { refreshing = false; checked = Date() }
        guard let payload = try? await HTTPClient().json("https://harbor.site/anime-hero-art.json", timeout: 20),
              let data = try? JSONEncoder().encode(payload), data.count <= 8 * 1024 * 1024, let updated = try? JSONDecoder().decode(Index.self, from: data),
              updated.art.count >= minimumEntryCount else { return }
        art = updated.art
        if let url = cacheURL { try? data.write(to: url, options: .atomic) }
    }
    private static func image(_ value: String?) -> String? {
        guard let value, let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { return nil }
        return value
    }
}
