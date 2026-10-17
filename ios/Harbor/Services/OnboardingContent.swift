import Foundation

enum OnboardingStep: String, CaseIterable, Identifiable {
    case splash, language, welcome, layout, tmdb, stremio, streaming, subtitles, taste, done
    var id: String { rawValue }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var next: Self { Self.allCases[min(index + 1, Self.allCases.count - 1)] }
    var previous: Self { Self.allCases[max(index - 1, 0)] }
    var canSkip: Bool { [.tmdb, .stremio, .streaming, .subtitles, .taste].contains(self) }
}

struct OnboardingTastePicks {
    static let maximum = 5
    private(set) var values: [Media] = []
    mutating func toggle(_ media: Media) {
        if values.contains(where: { $0.id == media.id }) { values.removeAll { $0.id == media.id } }
        else if values.count < Self.maximum { values.append(media) }
    }
    mutating func reset() { values = [] }
}

struct OnboardingContent: Sendable {
    static let cap = 40
    static func mix(_ lists: [[Media]], limit: Int = OnboardingContent.cap) -> [Media] {
        guard limit > 0 && limit <= 60 else { return [] }
        var output: [Media] = []; var seen = Set<String>()
        for index in 0..<(lists.map(\.count).max() ?? 0) {
            for list in lists where index < list.count {
                let media = list[index]
                guard media.poster?.isEmpty == false, seen.insert(media.id).inserted else { continue }
                output.append(media)
                if output.count == limit { return output }
            }
        }
        return output
    }
    func taste(configuration: MetadataConfiguration, service: HarborService) async throws -> [Media] {
        if !configuration.tmdbKey.isEmpty {
            let genres = [28, 35, 18, 878, 27, 53, 10749, 16, 14, 80, 37, 12, 9648, 99, 10752]
            let trending = TMDBService().homeDefinitions().filter { ["tmdb-trending-movies", "tmdb-trending-tv"].contains($0.id) }
            let definitions = trending + genres.map { genre in
                DiscoveryRail(id: "taste-\(genre)", title: "", kind: "movie", path: "discover/movie",
                              parameters: ["with_genres": String(genre), "sort_by": "popularity.desc", "vote_count.gte": "800", "vote_average.gte": "6.4"])
            }
            let lists = await bounded(definitions) { definition in
                let values = (try? await TMDBService().page(definition, page: 1, configuration: configuration)) ?? []
                return definition.id.hasPrefix("taste-") ? Array(values.prefix(2)) : values
            }
            try Task.checkCancellation()
            let mixed = Self.mix(lists)
            if mixed.count >= 16 { return mixed }
        }
        let plans = try await cinemetaPlans(service: service)
        let requests: [(String, String?)] = [("movie", nil), ("series", nil)] + ["Western", "Documentary", "Animation", "Crime", "Comedy"].map { ("movie", $0) }
        let lists = await bounded(requests) { request in
            guard let plan = plans.first(where: { $0.kind == request.0 && $0.catalog?.id == "top" }) else { return [] }
            return (try? await service.catalog(plan, genre: request.1, skip: 0).metas) ?? []
        }
        try Task.checkCancellation()
        return Self.mix(lists)
    }
    func splash(service: HarborService) async throws -> [Media] {
        let plans = try await cinemetaPlans(service: service)
        let requests = plans.filter { ["movie", "series"].contains($0.kind) && $0.catalog?.id == "top" }
        let lists = await bounded(requests) { plan in (try? await service.catalog(plan, genre: nil, skip: 0).metas) ?? [] }
        try Task.checkCancellation()
        return Self.mix(lists, limit: 60)
    }
    private func cinemetaPlans(service: HarborService) async throws -> [RequestPlan] {
        guard let addon = try await service.catalogProviders([]).first else { throw HarborError(code: "catalog-unavailable") }
        return try await service.core.call("catalogs", ["addons": try .encoded([addon])])
    }
    private func bounded<T: Sendable>(_ items: [T], operation: @escaping @Sendable (T) async -> [Media]) async -> [[Media]] {
        await withTaskGroup(of: (Int, [Media]).self) { group in
            var iterator = Array(items.enumerated()).makeIterator()
            func enqueue(_ item: (offset: Int, element: T)) { group.addTask { (item.offset, await operation(item.element)) } }
            for _ in 0..<3 { if let item = iterator.next() { enqueue(item) } }
            var lists = Array(repeating: [Media](), count: items.count)
            for await (index, values) in group {
                if Task.isCancelled { group.cancelAll(); continue }
                lists[index] = values
                if let item = iterator.next() { enqueue(item) }
            }
            return lists
        }
    }
}
