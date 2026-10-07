import Foundation
import Observation

@MainActor @Observable
final class ContentPageModel {
    var rows: [CatalogRow] = []
    var heroes: [Media] = []
    var heroSources: [String: String] = [:]
    var curated: [DiscoveryRail] = []
    var loading = false
    var error: String?
    private var generation = 0
    private var loadedSignature = ""
    func load(kind: String, app: AppModel, refresh: Bool = false) async {
        let configuration = MetadataPreferences.shared.configuration()
        let signature = kind + (app.user?.id ?? "guest") + app.addons.filter(\.enabled).map(\.id).joined() + configuration.tmdbKey + configuration.region + configuration.language + String(configuration.translateTitles)
        guard refresh || signature != loadedSignature else { return }
        generation += 1
        let current = generation
        loading = true; error = nil
        let previousRows = signature == loadedSignature ? rows : []
        let previousCurated = signature == loadedSignature ? curated : []
        var failed = false
        rows = previousRows; curated = previousCurated
        if signature != loadedSignature { heroes = []; heroSources = [:] }
        defer { if generation == current { loading = false } }
        // Desktop's Movies/Shows fallback is Cinemeta top plus genre rails.
        // It is a content provider, independent of the installed stream addons.
        do {
            if ["movie", "series", "kids"].contains(kind) {
                if !configuration.tmdbKey.isEmpty {
                    let definitions = kind == "kids" ? TMDBService().kidsDefinitions() : TMDBService().definitions(kind)
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
                            guard let rail else { failed = true; continue }
                            fetched.append((index, rail))
                            curated = CatalogRefresh.merge(order: definitions.map(\.id), received: fetched.map(\.1), previous: previousCurated)
                            if !rail.metas.isEmpty { rows = [] }
                            if heroes.isEmpty { heroes = Array(rail.metas.prefix(5)) }
                        }
                    }
                }
                if !curated.contains(where: { !$0.metas.isEmpty }) {
                    let addon = try await app.service.install(HarborService.cinemetaManifest)
                    let plans: [RequestPlan] = try await app.service.core.call("catalogs", ["addons": try .encoded([addon])])
                    let providerKind = kind == "kids" ? "movie" : kind
                    guard let top = plans.first(where: { $0.kind == providerKind && $0.catalog?.id == "top" }) else { throw HarborError(code: "catalog-unavailable") }
                    let genres = kind == "kids" ? ["Animation", "Family"] : ["Action", "Drama", "Comedy", "Sci-Fi", "Thriller", "Horror", "Romance", "Animation", "Adventure", "Crime", "Mystery", "Fantasy", "Documentary"]
                    let definitions: [(String, String?)] = (kind == "kids" ? [] : [(kind == "movie" ? "Top Movies" : "Top Series", nil)]) + genres.map { ("Top " + $0, Optional($0)) }
                    await withTaskGroup(of: (Int, CatalogRow?).self) { group in
                        for (index, definition) in definitions.enumerated() {
                            let service = app.service
                            group.addTask {
                                do {
                                    let fetched = try await service.catalog(top, genre: definition.1, skip: 0)
                                    let plan = RequestPlan(key: "native-\(kind)-\(index)", url: top.url, title: definition.0, kind: providerKind, addon: top.addon, addonPriority: 0, timeoutMs: top.timeoutMs, catalog: top.catalog)
                                    return (index, CatalogRow(plan: plan, metas: kind == "kids" ? fetched.metas.filter(\.safeForKids) : fetched.metas, selectedGenre: definition.1, receivedCount: fetched.receivedCount))
                                } catch { return (index, nil) }
                            }
                        }
                        var fetched: [(Int, CatalogRow)] = []
                        for await (index, row) in group {
                            guard current == generation else { continue }
                            guard let row else { failed = true; continue }
                            fetched.append((index, row))
                            let ordered = definitions.indices.map { "native-\(kind)-\($0)" }
                            rows = CatalogRefresh.merge(order: ordered, received: fetched.map(\.1), previous: previousRows)
                            if heroes.isEmpty { heroes = Array(row.metas.prefix(5)) }
                        }
                    }
                }
            } else if kind == "anime" {
                rows = app.rows.filter(\.isAnimeCatalog)
                let definitions = AnimeService.definitions()
                let records = app.library.items
                await withTaskGroup(of: (Int, DiscoveryRail?).self) { group in
                    for (index, rail) in definitions.enumerated() {
                        group.addTask {
                            do {
                                var result = rail
                                if rail.path == "anime:picks" { result.metas = try await AnimeService.shared.picks(records: records) }
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
                        guard let rail else { failed = true; continue }
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
            let addonRows = app.rows.filter { $0.plan.kind == kind && $0.plan.addon.manifest["id"].string != "com.linvo.cinemeta" }
            for row in addonRows where !rows.contains(where: { $0.id == row.id }) { rows.append(row) }
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
            else if failed { error = "Algunas filas no han respondido. Los títulos disponibles siguen accesibles." }
            if hasTitles { loadedSignature = signature }
        } catch is CancellationError { return }
        catch { if current == generation { self.error = safeMessage(error) } }
    }
    func refreshAnimePicks(app: AppModel) async {
        guard !loading, let index = curated.firstIndex(where: { $0.id == "anime-picks" }) else { return }
        let current = generation, owner = app.user?.id ?? "guest"
        guard let picks = try? await AnimeService.shared.picks(records: app.library.items), !Task.isCancelled,
              current == generation, owner == (app.user?.id ?? "guest"), curated.indices.contains(index), curated[index].id == "anime-picks" else { return }
        curated[index].metas = picks
    }
}
