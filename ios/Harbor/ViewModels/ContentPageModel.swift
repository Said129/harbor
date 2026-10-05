import Foundation
import Observation

@MainActor @Observable
final class ContentPageModel {
    var rows: [CatalogRow] = []
    var heroes: [Media] = []
    var curated: [DiscoveryRail] = []
    var loading = false
    var error: String?
    private var generation = 0
    private var loadedSignature = ""
    func load(kind: String, app: AppModel, refresh: Bool = false) async {
        let configuration = MetadataPreferences.shared.configuration()
        let signature = kind + app.addons.filter(\.enabled).map(\.id).joined() + configuration.tmdbKey + configuration.region + configuration.language + String(configuration.translateTitles)
        guard refresh || signature != loadedSignature else { return }
        generation += 1
        let current = generation
        loading = true; error = nil
        rows = []; heroes = []; curated = []
        defer { if generation == current { loading = false } }
        // Desktop's Movies/Shows fallback is Cinemeta top plus genre rails.
        // It is a content provider, independent of the installed stream addons.
        do {
            if kind == "movie" || kind == "series" {
                if !configuration.tmdbKey.isEmpty {
                    let definitions = TMDBService().definitions(kind)
                    await withTaskGroup(of: (Int, DiscoveryRail?).self) { group in
                        for (index, rail) in definitions.enumerated() {
                            group.addTask {
                                do { var result = rail; result.metas = try await TMDBService().page(rail, page: 1, configuration: configuration); return (index, result) }
                                catch { return (index, nil) }
                            }
                        }
                        var fetched: [(Int, DiscoveryRail)] = []
                        for await (index, rail) in group {
                            guard current == generation, let rail, !rail.metas.isEmpty else { continue }
                            fetched.append((index, rail)); curated = fetched.sorted { $0.0 < $1.0 }.map(\.1)
                            if heroes.isEmpty { heroes = Array(rail.metas.prefix(5)) }
                        }
                    }
                }
                if curated.isEmpty {
                let addon = try await app.service.install(HarborService.cinemetaManifest)
                let plans: [RequestPlan] = try await app.service.core.call("catalogs", ["addons": try .encoded([addon])])
                guard let top = plans.first(where: { $0.kind == kind && $0.catalog?.id == "top" }) else { throw HarborError(code: "catalog-unavailable") }
                let genres = ["Action", "Drama", "Comedy", "Sci-Fi", "Thriller", "Horror", "Romance", "Animation", "Adventure", "Crime", "Mystery", "Fantasy", "Documentary"]
                let definitions: [(String, String?)] = [(kind == "movie" ? "Top películas" : "Top series", nil)] + genres.map { ($0, Optional($0)) }
                await withTaskGroup(of: (Int, CatalogRow?).self) { group in
                    for (index, definition) in definitions.enumerated() {
                        let service = app.service
                        group.addTask {
                            do {
                                let fetched = try await service.catalog(top, genre: definition.1, skip: 0)
                                let plan = RequestPlan(key: "native-\(kind)-\(index)", url: top.url, title: definition.0, kind: kind, addon: top.addon, addonPriority: 0, timeoutMs: top.timeoutMs, catalog: top.catalog)
                                return (index, CatalogRow(plan: plan, metas: fetched.metas, selectedGenre: definition.1))
                            } catch { return (index, nil) }
                        }
                    }
                    var fetched: [(Int, CatalogRow)] = []
                    for await (index, row) in group {
                        guard current == generation, let row, !row.metas.isEmpty else { continue }
                        fetched.append((index, row)); rows = fetched.sorted { $0.0 < $1.0 }.map(\.1)
                        if heroes.isEmpty { heroes = Array(row.metas.prefix(5)) }
                    }
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
            heroes = Array((curated.flatMap(\.metas) + rows.flatMap(\.metas)).filter { seen.insert($0.identity).inserted }.prefix(5))
            let originals = heroes
            await withTaskGroup(of: (Int, Media).self) { group in
                for (index, media) in originals.enumerated() {
                    let service = app.service; let addons = app.addons
                    group.addTask { (index, (try? await service.metadata(media, addons: addons)) ?? media) }
                }
                for await (index, media) in group {
                    if current == generation && index < heroes.count { heroes[index] = media }
                }
            }
            if rows.isEmpty && curated.isEmpty { error = "No se encontraron catálogos disponibles. Revisa tus addons o vuelve a intentarlo." }
            loadedSignature = signature
        } catch is CancellationError { return }
        catch { if current == generation { self.error = safeMessage(error) } }
    }
}
