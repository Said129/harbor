import Foundation

/// Desktop enriches playlist titles from the user's TMDB configuration. Only
/// public metadata is cached; the playlist identity and stream remain intact.
actor VODMetadataService {
    static let shared = VODMetadataService()
    private struct Cached: Sendable { let value: Media?; let expires: Date }
    private var cache: [String: Cached] = [:]
    private var pending: [String: Task<Media?, Error>] = [:]

    func enrich(_ original: Media, configuration: MetadataConfiguration, owner: String) async throws -> Media {
        guard !configuration.tmdbKey.isEmpty, !original.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return original }
        let signature = [owner, configuration.tmdbKey, configuration.language, configuration.region, original.type, original.name.lowercased(), original.releaseInfo ?? ""].joined(separator: "|")
        let key = EBookShelf.hash(signature)
        while true {
            try Task.checkCancellation()
            if let found = cache[key], found.expires > Date() { return Self.apply(found.value, to: original) }
            if let task = pending[key] { return Self.apply(try await task.value, to: original) }
            if pending.count < 4 { break }
            try await Task.sleep(for: .milliseconds(120))
        }
        let task = Task<Media?, Error> {
            let providerKind = original.type == "series" ? "tv" : "movie"
            var parameters = ["query": original.name, "include_adult": "false"]
            if let year = original.releaseInfo.flatMap(Int.init), (1800...2200).contains(year) { parameters[providerKind == "tv" ? "first_air_date_year" : "year"] = String(year) }
            let rail = DiscoveryRail(id: "vod-metadata", title: original.name, kind: original.type, path: "search/" + providerKind, parameters: parameters)
            return try await TMDBService().page(rail, page: 1, configuration: configuration).first
        }
        pending[key] = task
        defer { pending[key] = nil }
        let value = try await task.value
        cache[key] = Cached(value: value, expires: Date().addingTimeInterval(value == nil ? 300 : 6 * 60 * 60))
        if cache.count > 512 {
            let retained = cache.sorted { $0.value.expires > $1.value.expires }.prefix(512)
            cache = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
        }
        return Self.apply(value, to: original)
    }

    nonisolated static func apply(_ metadata: Media?, to original: Media) -> Media {
        guard let metadata else { return original }
        var enriched = original
        enriched.poster = metadata.poster ?? original.poster
        enriched.background = metadata.background ?? original.background
        if let overview = metadata.description, !overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { enriched.description = overview }
        enriched.releaseInfo = metadata.releaseInfo ?? original.releaseInfo
        enriched.imdbRating = metadata.imdbRating ?? original.imdbRating
        enriched.ratingSource = metadata.ratingSource ?? original.ratingSource
        return enriched
    }
}
