import Foundation
import Observation

struct ServiceCatalogCategory: Identifiable, Sendable {
    let id: String
    let label: String
    var movies = true
    var series = true
    var movieGenres: [Int] = []
    var seriesGenres: [Int] = []
    static let all: [Self] = [
        .init(id: "all", label: "All"), .init(id: "movies", label: "Movies", series: false),
        .init(id: "tv", label: "TV Shows", movies: false),
        .init(id: "docs", label: "Documentaries", movieGenres: [99], seriesGenres: [99]),
        .init(id: "anim", label: "Animation", movieGenres: [16], seriesGenres: [16]),
        .init(id: "kids", label: "Kids & Family", movieGenres: [10751], seriesGenres: [10751]),
        .init(id: "reality", label: "Reality", movies: false, seriesGenres: [10764]),
        .init(id: "action", label: "Action", movieGenres: [28], seriesGenres: [10759]),
        .init(id: "comedy", label: "Comedy", movieGenres: [35], seriesGenres: [35]),
        .init(id: "drama", label: "Drama", movieGenres: [18], seriesGenres: [18]),
        .init(id: "horror", label: "Horror", movieGenres: [27], seriesGenres: [9648]),
        .init(id: "scifi", label: "Sci-Fi & Fantasy", movieGenres: [878], seriesGenres: [10765]),
        .init(id: "thriller", label: "Thriller", series: false, movieGenres: [53]),
        .init(id: "romance", label: "Romance", series: false, movieGenres: [10749])
    ]
    func definition(_ service: StreamingServiceDefinition, kind: String, region: String) -> DiscoveryRail? {
        guard kind == "movie" ? movies : kind == "series" && series else { return nil }
        var rail = StreamingCatalog.definition(service, kind: kind, region: region)
        rail.parameters.removeValue(forKey: "vote_count.gte")
        rail.parameters["with_watch_monetization_types"] = "flatrate|free|ads"
        rail.parameters["include_adult"] = "false"
        let genres = kind == "movie" ? movieGenres : seriesGenres
        if !genres.isEmpty { rail.parameters["with_genres"] = genres.map(String.init).joined(separator: ",") }
        return rail
    }
}

@MainActor @Observable
final class ServiceCatalogModel {
    typealias Loader = @Sendable (DiscoveryRail, Int, MetadataConfiguration) async throws -> [Media]
    @ObservationIgnored private let loader: Loader
    private let maximum = 200
    private var signature = ""
    private var generation = 0
    private var pages = ["movie": 1, "series": 1]
    private var finished = Set<String>()
    private(set) var movies: [Media] = []
    private(set) var series: [Media] = []
    private(set) var loading = false
    private(set) var error: String?
    private(set) var revision = 0
    var hasMore: Bool { finished.count < 2 }
    var allTitles: [Media] { movies + series }
    static func scopeKey(service: StreamingServiceDefinition, category: ServiceCatalogCategory, configuration: MetadataConfiguration, owner: String) -> String {
        let parts = [owner, service.key, category.id, EBookShelf.hash(configuration.tmdbKey), configuration.region, configuration.language, String(configuration.translateTitles)]
        let encoded = try! JSONEncoder().encode(parts)
        return EBookShelf.hash(String(decoding: encoded, as: UTF8.self))
    }
    init(loader: @escaping Loader = { rail, page, configuration in try await TMDBService().page(rail, page: page, configuration: configuration) }) { self.loader = loader }
    func reset() {
        generation += 1; signature = ""; pages = ["movie": 1, "series": 1]; finished = []
        movies = []; series = []; loading = false; error = nil; revision &+= 1
    }
    func load(service: StreamingServiceDefinition, category: ServiceCatalogCategory, configuration: MetadataConfiguration, owner: String, more: Bool = false) async {
        let nextSignature = Self.scopeKey(service: service, category: category, configuration: configuration, owner: owner)
        if nextSignature != signature { reset(); signature = nextSignature }
        else if !more && (!movies.isEmpty || !series.isEmpty) && error == nil { return }
        guard !loading, !configuration.tmdbKey.isEmpty, hasMore else { return }
        let current = generation
        let plans = ["movie", "series"].compactMap { kind -> DiscoveryRail? in
            guard !finished.contains(kind) else { return nil }
            guard let plan = category.definition(service, kind: kind, region: configuration.region) else { finished.insert(kind); return nil }
            return plan
        }
        guard !plans.isEmpty else { return }
        loading = true; error = nil
        defer {
            if generation == current {
                loading = false
                if !Task.isCancelled, error == nil { revision &+= 1 }
            }
        }
        let requestedPages = self.pages, fetch = self.loader
        var failed = false
        await withTaskGroup(of: (String, [Media]?).self) { group in
            for plan in plans {
                group.addTask {
                    do { return (plan.kind, try await fetch(plan, requestedPages[plan.kind] ?? 1, configuration)) }
                    catch { return (plan.kind, nil) }
                }
            }
            for await (kind, result) in group {
                guard generation == current, !Task.isCancelled else { group.cancelAll(); continue }
                guard let result else { failed = true; continue }
                let previous = kind == "movie" ? movies : series
                var ids = Set(previous.map(\.id))
                let additions = result.filter { $0.poster?.isEmpty == false && ids.insert($0.id).inserted }
                let merged = Array((previous + additions).prefix(maximum))
                if kind == "movie" { movies = merged } else { series = merged }
                self.pages[kind, default: 1] += 1
                if result.count < 20 || merged.count >= maximum { finished.insert(kind) }
            }
        }
        guard generation == current, !Task.isCancelled else { return }
        if failed { error = "Could not load this page. Try again." }
    }
}
