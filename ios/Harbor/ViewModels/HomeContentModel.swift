import Foundation
import Observation

@MainActor @Observable
final class HomeContentModel {
    private(set) var rows: [DiscoveryRail] = []
    private(set) var animeRows: [DiscoveryRail] = []
    private var animeGeneration = 0
    private var animeLoadedOwner: String?
    private(set) var heroes: [Media] = []
    private(set) var loading = false
    private(set) var error: String?
    private var generation = 0
    private var loadedSignature = ""

    func reset() { generation += 1; loadedSignature = ""; rows = []; heroes = []; loading = false; error = nil; animeGeneration += 1; animeLoadedOwner = nil; animeRows = [] }

    func loadAnime(owner: String, refresh: Bool = false) async {
        guard refresh || animeLoadedOwner != owner else { return }
        animeGeneration += 1
        let current = animeGeneration
        let previous = animeLoadedOwner == owner ? animeRows : []
        animeRows = previous
        let fetched = await AnimeService.shared.homeRows()
        guard !Task.isCancelled, current == animeGeneration else { return }
        animeRows = CatalogRefresh.merge(order: AnimeService.homeDefinitions().map { String($0.id.dropFirst(5)) }, received: fetched, previous: previous)
        if !fetched.isEmpty { animeLoadedOwner = owner }
    }

    func load(app: AppModel, refresh: Bool = false) async {
        let configuration = MetadataPreferences.shared.configuration()
        let signature = [app.user?.id ?? "guest", EBookShelf.hash(configuration.tmdbKey), configuration.language, configuration.region, String(configuration.translateTitles), app.addons.filter(\.enabled).map(\.id).joined(separator: "|")].joined(separator: "|")
        guard refresh || loadedSignature != signature else { return }
        generation += 1
        let current = generation
        let previous = signature == loadedSignature ? rows : []
        rows = previous; error = nil; loading = true
        if previous.isEmpty { heroes = [] }
        defer { if generation == current { loading = false } }
        do {
            if !configuration.tmdbKey.isEmpty {
                let definitions = TMDBService().homeDefinitions()
                await withTaskGroup(of: DiscoveryRail?.self) { group in
                    for definition in definitions {
                        group.addTask {
                            do { var row = definition; row.metas = try await TMDBService().page(row, page: 1, configuration: configuration); return row }
                            catch { return nil }
                        }
                    }
                    var received: [DiscoveryRail] = []
                    for await row in group {
                        guard current == generation, !Task.isCancelled, let row else { continue }
                        received.append(row)
                        rows = CatalogRefresh.merge(order: definitions.map(\.id), received: received, previous: previous)
                    }
                }
            }
            try Task.checkCancellation()
            guard current == generation else { return }
            if !rows.contains(where: { !$0.metas.isEmpty }) {
                let addon = try await app.service.install(HarborService.cinemetaManifest)
                let plans: [RequestPlan] = try await app.service.core.call("catalogs", ["addons": try .encoded([addon])])
                guard let movie = plans.first(where: { $0.kind == "movie" && $0.catalog?.id == "top" }),
                      let series = plans.first(where: { $0.kind == "series" && $0.catalog?.id == "top" }) else { throw HarborError(code: "catalog-unavailable") }
                let definitions = HomeCinemetaDefinition.all
                var seen = Set<String>()
                let requests = definitions.filter { seen.insert($0.requestKey).inserted }
                let service = app.service
                await withTaskGroup(of: (String, [Media]?).self) { group in
                    for definition in requests {
                        let plan = definition.kind == "movie" ? movie : series
                        group.addTask {
                            do { return (definition.requestKey, try await service.catalog(plan, genre: definition.genre, skip: 0).metas) }
                            catch { return (definition.requestKey, nil) }
                        }
                    }
                    var fetched: [String: [Media]] = [:]
                    for await (key, values) in group {
                        guard current == generation, !Task.isCancelled, let values else { continue }
                        fetched[key] = values
                        let received = definitions.compactMap { definition -> DiscoveryRail? in
                            guard let titles = fetched[definition.requestKey] else { return nil }
                            return DiscoveryRail(id: definition.id, title: DesktopInterfaceText.value(definition.title), kind: definition.kind, path: "home:fixed", metas: Array(titles.dropFirst(definition.offset).prefix(definition.limit)))
                        }
                        rows = CatalogRefresh.merge(order: definitions.map(\.id), received: received, previous: previous)
                    }
                }
            }
            try Task.checkCancellation()
            guard current == generation else { return }
            let ids = rows.first?.id.hasPrefix("tmdb-") == true
                ? ["tmdb-trending-movies", "tmdb-trending-tv", "tmdb-now-playing", "tmdb-on-the-air"]
                : ["cm-top-movies", "cm-trending-tv", "cm-drama", "cm-comedy", "cm-action", "cm-scifi"]
            var seen = Set<String>()
            heroes = ids.compactMap { id in rows.first { $0.id == id }?.metas.first }.filter { seen.insert($0.identity).inserted }
            let originals = heroes, service = app.service, addons = app.addons
            await withTaskGroup(of: (Int, Media).self) { group in
                for (index, media) in originals.enumerated() {
                    group.addTask {
                        var enriched = (try? await service.metadata(media, addons: addons)) ?? media
                        enriched.background = media.background ?? enriched.background
                        enriched.logo = media.logo ?? enriched.logo
                        if let score = media.imdbRating { enriched.imdbRating = score; enriched.ratingSource = media.ratingSource }
                        return (index, enriched)
                    }
                }
                for await (index, media) in group {
                    guard current == generation, !Task.isCancelled, heroes.indices.contains(index) else { continue }
                    heroes[index] = media
                }
            }
            try Task.checkCancellation()
            guard current == generation else { return }
            if rows.contains(where: { !$0.metas.isEmpty }) { loadedSignature = signature }
            else { error = safeMessage(HarborError(code: "catalog-unavailable")) }
        } catch is CancellationError { return }
        catch { if current == generation { self.error = safeMessage(error) } }
    }
}

private struct HomeCinemetaDefinition: Sendable {
    let id: String
    let title: String
    var kind = "movie"
    var genre: String? = nil
    var offset = 0
    var limit = 30
    var requestKey: String { kind + "|" + (genre ?? "") }
    static let all: [HomeCinemetaDefinition] = [
        .init(id: "cm-top-movies", title: "Top 10 on Stremio", limit: 10),
        .init(id: "cm-popular", title: "Popular Movies", offset: 10),
        .init(id: "cm-drama", title: "Top 10 Drama", genre: "Drama", limit: 10),
        .init(id: "cm-trending-tv", title: "Trending Series", kind: "series"),
        .init(id: "cm-comedy", title: "Top 10 Comedy", genre: "Comedy", limit: 10),
        .init(id: "cm-action", title: "Action Hits", genre: "Action"),
        .init(id: "cm-scifi", title: "Sci-Fi & Fantasy", genre: "Sci-Fi"),
        .init(id: "cm-thriller", title: "Thrillers", genre: "Thriller"),
        .init(id: "cm-animation", title: "Animated Movies", genre: "Animation"),
        .init(id: "cm-horror", title: "Horror", genre: "Horror"),
        .init(id: "cm-romance", title: "Romance", genre: "Romance"),
        .init(id: "cm-adventure", title: "Adventure", genre: "Adventure"),
        .init(id: "cm-documentary", title: "Documentaries", genre: "Documentary"),
        .init(id: "cm-mystery", title: "Mystery", genre: "Mystery"),
        .init(id: "cm-fantasy", title: "Fantasy", genre: "Fantasy"),
        .init(id: "cm-drama-tv", title: "Drama Series", kind: "series", genre: "Drama"),
        .init(id: "cm-comedy-tv", title: "Comedy Series", kind: "series", genre: "Comedy"),
        .init(id: "cm-crime-tv", title: "Crime Series", kind: "series", genre: "Crime")
    ]
}
