import Foundation
import Observation

@MainActor @Observable
final class ContentPageModel {
    var rows: [CatalogRow] = []
    var heroes: [Media] = []
    var heroSources: [String: String] = [:]
    private(set) var seriesHeroIDs = Set<String>()
    var curated: [DiscoveryRail] = []
    var loading = false
    var error: String?
    private var generation = 0
    private var loadedSignature = ""
    /// Inline paging state for movie and series rows, keyed by row id (Desktop's `loadMore` in `movies.tsx`).
    private var rowPaging: [String: DesktopGridPaging] = [:]
    private var rowHasMore: [String: Bool] = [:]
    private var rowPagingLoading: Set<String> = []
    func load(kind: String, app: AppModel, refresh: Bool = false) async {
        let configuration = MetadataPreferences.shared.configuration()
        let signature = kind + app.accountOperationScope + app.addons.filter(\.enabled).map(\.id).joined() + configuration.tmdbKey + configuration.region + configuration.language + String(configuration.translateTitles)
        guard refresh || signature != loadedSignature else { return }
        generation += 1
        let current = generation
        loading = true; error = nil
        rowPaging = [:]; rowHasMore = [:]
        let previousRows = signature == loadedSignature ? rows : []
        let previousCurated = signature == loadedSignature ? curated : []
        let recentMovies = DailyHeroRotation.RecentMovies(kind == "movie" ? StreamPlaybackHistory.remembered(owner: app.library.owner) : [:])
        let now = Date()
        let day = DailyHeroRotation.currentDay(now: now)
        rows = previousRows; curated = previousCurated
        if signature != loadedSignature { heroes = []; heroSources = [:]; seriesHeroIDs = [] }
        defer { if generation == current { loading = false } }
        // Desktop's Movies/Shows fallback is Cinemeta top plus genre rails.
        // It is a content provider, independent of the installed stream addons.
        do {
            if ["movie", "series"].contains(kind) {
                if !configuration.tmdbKey.isEmpty {
                    let definitions = TMDBService().definitions(kind, now: now)
                    async let feature: Void = loadFeaturedHero(kind: kind, configuration: configuration, recent: recentMovies, day: day, now: now, generation: current)
                    await withTaskGroup(of: (Int, DiscoveryRail?).self) { group in
                        for (index, rail) in definitions.enumerated() {
                            group.addTask {
                                do { var result = rail; result.metas = try await TMDBService().page(rail, page: 1, configuration: configuration); return (index, result) }
                                catch { return (index, nil) }
                            }
                        }
                        var fetched: [(Int, DiscoveryRail)] = []
                        for await (index, rail) in group {
                            guard current == generation else { continue }
                            guard let rail else { continue }
                            fetched.append((index, rail))
                            curated = CatalogRefresh.merge(order: definitions.map(\.id), received: fetched.map(\.1), previous: previousCurated)
                            if !rail.metas.isEmpty { rows = [] }
                            if kind == "series", rail.ranked, heroes.isEmpty { setSeriesHero(ShowsHero.fallback(rail.metas)) }
                        }
                    }
                    await feature
                }
                try Task.checkCancellation()
                guard current == generation else { return }
                if !curated.contains(where: { !$0.metas.isEmpty }) {
                    let addon = try await app.service.install(HarborService.cinemetaManifest)
                    let plans: [RequestPlan] = try await app.service.core.call("catalogs", ["addons": try .encoded([addon])])
                    let providerKind = kind
                    guard let top = plans.first(where: { $0.kind == providerKind && $0.catalog?.id == "top" }) else { throw HarborError(code: "catalog-unavailable") }
                    let genres = kind == "series" ? ShowsCatalog.fallbackGenres : ["Action", "Drama", "Comedy", "Sci-Fi", "Thriller", "Horror", "Romance", "Animation", "Adventure", "Crime", "Mystery", "Fantasy", "Documentary"]
                    let definitions: [(String, String?)] = [(kind == "movie" ? "Top Movies" : "Top Series", nil)] + genres.map { ("Top " + $0, Optional($0)) }
                    let ordered = definitions.enumerated().map { index, definition in
                        kind == "series" ? ShowsCatalog.fallbackKey(for: definition.1) : "native-\(kind)-\(index)"
                    }
                    await withTaskGroup(of: (Int, CatalogRow?).self) { group in
                        for (index, definition) in definitions.enumerated() {
                            let service = app.service
                            group.addTask {
                                do {
                                    let fetched = try await service.catalog(top, genre: definition.1, skip: 0)
                                    let plan = RequestPlan(key: ordered[index], url: top.url, title: definition.0, kind: providerKind, addon: top.addon, addonPriority: 0, timeoutMs: top.timeoutMs, catalog: top.catalog)
                                    return (index, CatalogRow(plan: plan, metas: fetched.metas, selectedGenre: definition.1, receivedCount: fetched.receivedCount))
                                } catch { return (index, nil) }
                            }
                        }
                        var fetched: [(Int, CatalogRow)] = []
                        for await (index, row) in group {
                            guard current == generation else { continue }
                            guard let row else { continue }
                            fetched.append((index, row))
                            rows = CatalogRefresh.merge(order: ordered, received: fetched.map(\.1), previous: previousRows)
                            if kind == "movie", index == 0, !row.metas.isEmpty {
                                heroes = DailyHeroRotation.movies([row.metas], recent: recentMovies, day: day)
                            } else if kind == "series", index == 0 {
                                setSeriesHero(ShowsHero.fallback(row.metas))
                            }
                        }
                    }
                }
            } else if kind == "anime" {
                rows = AddonCatalogRules.discoveredRows(app.rows.filter(\.isAnimeCatalog))
                let definitions = AnimeService.definitions()
                guard definitions.count == 24 else { throw HarborError(code: "anime-row-assets") }
                let records = app.library.items
                let picksOptions = AnimePicksPreferences.shared.options
                let watchedIDs: Set<String> = picksOptions.hideWatched ? Self.watchedAnimeIDs(records, app: app) : []
                await withTaskGroup(of: (Int, DiscoveryRail?).self) { group in
                    for (index, rail) in definitions.enumerated() {
                        group.addTask {
                            do {
                                var result = rail
                                if rail.path == "anime:picks" { result.metas = try await AnimeService.shared.picks(records: records, options: picksOptions, watchedIDs: watchedIDs) }
                                else if rail.id == "anilist-top100" {
                                    let first = try await AnimeService.shared.page(rail, page: 1)
                                    let second = try await AnimeService.shared.page(rail, page: 2)
                                    result.metas = first + second
                                } else { result.metas = try await AnimeService.shared.page(rail, page: 1) }
                                return (index, result)
                            } catch { return (index, nil) }
                        }
                    }
                    var fetched: [(Int, DiscoveryRail)] = []
                    for await (index, rail) in group {
                        guard current == generation else { continue }
                        guard let rail else { continue }
                        fetched.append((index, rail))
                        curated = CatalogRefresh.merge(order: definitions.map(\.id), received: fetched.map(\.1), previous: previousCurated)
                    }
                }
            } else {
                rows = app.rows.filter { row in
                    if kind == "anime" { return row.plan.kind == "anime" || row.plan.addon.manifest["id"].string?.localizedCaseInsensitiveContains("kitsu") == true || row.plan.title.localizedCaseInsensitiveContains("anime") }
                    return ["tv", "channel"].contains(row.plan.kind)
                }
            }
            try Task.checkCancellation()
            guard current == generation else { return }
            if kind != "anime" {
                let addonRows = app.rows.filter { $0.plan.kind == kind && $0.plan.addon.manifest["id"].string != "com.linvo.cinemeta" }
                for row in addonRows where !rows.contains(where: { $0.id == row.id }) { rows.append(row) }
            }
            var seen = Set<String>()
            if kind == "anime" {
                let trending = curated.first { $0.id == "anilist-trending" }?.metas ?? []
                let airing = curated.first { $0.id == "anime-airing" }?.metas ?? []
                let winners = curated.first { $0.id == "anime-awards" }?.metas ?? []
                var candidates: [Media] = Array(trending.prefix(3))
                candidates.append(contentsOf: winners.prefix(1))
                candidates.append(contentsOf: airing.prefix(2))
                candidates.append(contentsOf: curated.flatMap(\.metas))
                candidates.append(contentsOf: rows.flatMap(\.metas))
                heroes = Array(candidates.filter { seen.insert($0.identity).inserted }.prefix(6))
                heroSources = [:]
                for media in heroes {
                    if trending.contains(where: { $0.id == media.id }) { heroSources[media.id] = "AniList" }
                    else if airing.contains(where: { $0.id == media.id }) { heroSources[media.id] = "MAL" }
                }
                heroes = await AnimeArtwork.shared.enrich(heroes)
                guard current == generation else { return }
            } else if kind == "movie" {
                if !curated.contains(where: { !$0.metas.isEmpty }),
                   let top = rows.first(where: { $0.plan.key == "native-movie-0" }) {
                    heroes = DailyHeroRotation.movies([top.metas], recent: recentMovies, day: day)
                }
                if heroes.isEmpty {
                    heroes = DailyHeroRotation.movies(curated.map(\.metas) + rows.map(\.metas), recent: recentMovies, day: day)
                }
            } else if kind == "series" {
                if heroes.isEmpty {
                    setSeriesHero(ShowsHero.fallback(curated.first(where: \.ranked)?.metas ?? rows.flatMap(\.metas)))
                }
            } else {
                heroes = Array((curated.flatMap(\.metas) + rows.flatMap(\.metas)).filter { seen.insert($0.identity).inserted }.prefix(5))
            }
            let originals = heroes
            await withTaskGroup(of: (Int, Media).self) { group in
                for (index, media) in originals.enumerated() {
                    let service = app.service; let addons = app.addons
                    group.addTask {
                        var enriched = (try? await service.metadata(media, addons: addons)) ?? media
                        // Canonical episode metadata must not discard the selected provider's score/art.
                        enriched.background = media.background ?? enriched.background
                        enriched.logo = media.logo ?? enriched.logo
                        if let score = media.imdbRating { enriched.imdbRating = score; enriched.ratingSource = media.ratingSource }
                        return (index, enriched)
                    }
                }
                for await (index, media) in group {
                    if current == generation && index < heroes.count {
                        if let source = heroSources[originals[index].id] { heroSources[media.id] = source }
                        heroes[index] = media
                    }
                }
            }
            let hasTitles = rows.contains { !$0.metas.isEmpty } || curated.contains { !$0.metas.isEmpty }
            if !hasTitles { error = "No se encontraron catálogos disponibles. Revisa tus addons o vuelve a intentarlo." }
            if hasTitles { loadedSignature = signature }
        } catch is CancellationError { return }
        catch { if current == generation { self.error = safeMessage(error) } }
    }
    private func loadFeaturedHero(kind: String, configuration: MetadataConfiguration, recent: DailyHeroRotation.RecentMovies,
                                  day: Int, now: Date, generation requestedGeneration: Int) async {
        let featured: [Media]
        if kind == "series" {
            featured = await ShowsHeroPool.shared.slides(configuration: configuration, now: now)
        } else {
            let lists = await TMDBService().movieHeroLists(configuration: configuration)
            featured = DailyHeroRotation.movies(lists, recent: recent, day: day)
        }
        guard !Task.isCancelled, generation == requestedGeneration else { return }
        guard !featured.isEmpty else { return }
        if kind == "series" { setSeriesHero(featured) }
        else { heroes = featured }
    }

    private func setSeriesHero(_ titles: [Media]) {
        heroes = titles
        seriesHeroIDs = Set(titles.map(\.id))
    }
    /// Desktop's `loadMore` (`movies.tsx`): when a movie or series row reaches its end, request its next catalog page,
    /// skip the titles it has, and stop at Desktop's row cap. Native Cinemeta fallback rows never page, as on Desktop.
    func loadMoreRow(id: String, app: AppModel) async {
        guard let index = rows.firstIndex(where: { $0.id == id }), ["movie", "series"].contains(rows[index].plan.kind),
              !rows[index].plan.key.hasPrefix("native-") else { return }
        let row = rows[index]
        let hasMore = rowHasMore[id] ?? CatalogRowPaging.initialHasMore(count: row.metas.count)
        guard CatalogRowPaging.shouldRequest(hasMore: hasMore, loading: rowPagingLoading.contains(id), count: row.metas.count) else { return }
        rowPagingLoading.insert(id)
        defer { rowPagingLoading.remove(id) }
        var paging = rowPaging[id] ?? DesktopGridPaging(initialCount: row.receivedCount ?? row.metas.count)
        guard let result = try? await app.service.catalog(row.plan, genre: row.selectedGenre, skip: paging.loaded) else { return }
        let received = result.receivedCount ?? result.metas.count
        paging.received(received)
        rowPaging[id] = paging
        guard let current = rows.firstIndex(where: { $0.id == id }) else { return }
        let merged = CatalogRowPaging.merge(current: rows[current].metas, more: result.metas, received: received)
        rows[current].metas = merged.metas
        rowHasMore[id] = merged.hasMore
    }
    /// The anime library titles the viewer has watched, read on the main actor for the picks filter.
    private static func watchedAnimeIDs(_ records: [LibraryRecord], app: AppModel) -> Set<String> {
        Set(records.compactMap(\.media).filter { AnimeService.isAnime($0.id) && app.library.watched($0) }.map(\.id))
    }

    func refreshAnimePicks(app: AppModel) async {
        guard !loading, let index = curated.firstIndex(where: { $0.id == "anime-picks" }) else { return }
        let current = generation, owner = app.accountOperationScope
        let picksOptions = AnimePicksPreferences.shared.options
        let watchedIDs: Set<String> = picksOptions.hideWatched ? Self.watchedAnimeIDs(app.library.items, app: app) : []
        guard let picks = try? await AnimeService.shared.picks(records: app.library.items, options: picksOptions, watchedIDs: watchedIDs), !Task.isCancelled,
              current == generation, owner == app.accountOperationScope, curated.indices.contains(index), curated[index].id == "anime-picks" else { return }
        curated[index].metas = picks
    }
}
