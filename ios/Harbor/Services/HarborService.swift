import Foundation

struct HarborService: Sendable {
    let core = CoreBridge()
    let http = HTTPClient()
    static let cinemetaManifest = "https://v3-cinemeta.strem.io/manifest.json"

    func catalogProviders(_ addons: [Addon]) async throws -> [Addon] {
        // A declared Cinemeta entry, including a disabled one, is an explicit
        // account choice. Otherwise provide Harbor's built-in content catalog
        // independently of the account's stream-only addons.
        guard !addons.contains(where: { $0.manifest["id"].string == "com.linvo.cinemeta" }) else { return addons }
        if let builtin = try? await BuiltinCatalogProvider.shared.cinemeta() { return addons + [builtin] }
        return addons
    }

    func install(_ url: String) async throws -> Addon {
        struct Normalized: Decodable, Sendable { let url: String }
        let normalized: Normalized = try await core.call("normalizeAddon", ["url": .string(url)])
        let manifest = try await http.json(normalized.url)
        return try await core.call("installAddon", ["url": .string(normalized.url), "manifest": manifest])
    }

    func catalogs(_ addons: [Addon], search: String? = nil, genre: String? = nil, skip: Int = 0, previous: [CatalogRow] = [], onRow: (@MainActor @Sendable (CatalogRow) -> Void)? = nil) async throws -> ([CatalogRow], [String]) {
        let plans: [RequestPlan] = try await core.call("catalogs", ["addons": try .encoded(addons), "search": search.map(JSONValue.string) ?? .null, "genre": genre.map(JSONValue.string) ?? .null, "skip": .integer(Int64(skip))])
        return try await withThrowingTaskGroup(of: (RequestPlan, JSONValue?, String?).self) { group in
            var iterator = plans.makeIterator()
            func enqueue(_ plan: RequestPlan) {
                group.addTask {
                    do { return (plan, try await http.json(plan.url, timeout: Double(plan.timeoutMs) / 1000), nil) }
                    catch is CancellationError { throw CancellationError() }
                    catch let error as HarborError { return (plan, nil, error.code) }
                    catch { return (plan, nil, "invalid-response") }
                }
            }
            for _ in 0..<6 { if let plan = iterator.next() { enqueue(plan) } }
            var rows: [CatalogRow] = []; var errors: [String] = []
            while let (plan, value, failure) = try await group.next() {
                if let value {
                    do {
                        let row = try decodeCatalog(value, plan: plan)
                        rows.append(row)
                        if !row.metas.isEmpty { await onRow?(row) }
                    } catch { errors.append("catalog-response"); await Diagnostics.shared.recordFailure(error) }
                }
                if let failure { errors.append(failure) }
                if let next = iterator.next() { enqueue(next) }
            }
            try Task.checkCancellation()
            return (Self.mergeCatalogs(plans: plans, received: rows, previous: previous), errors)
        }
    }

    static func mergeCatalogs(plans: [RequestPlan], received: [CatalogRow], previous: [CatalogRow]) -> [CatalogRow] {
        CatalogRefresh.merge(order: plans.map(\.key), received: received, previous: previous)
    }

    func metadata(_ media: Media, addons: [Addon]) async throws -> Media {
        let configuration = await MetadataPreferences.shared.configuration()
        if media.id.hasPrefix("tmdb:") && !configuration.tmdbKey.isEmpty {
            let enriched = try await TMDBService().detail(media, configuration: configuration)
            if enriched.id != media.id {
                if var combined = try? await addonMetadata(enriched, addons: addons) {
                    combined.logo = enriched.logo ?? combined.logo; combined.background = enriched.background ?? combined.background
                    combined.cast = enriched.cast ?? combined.cast; combined.director = enriched.director ?? combined.director
                    return combined
                }
                return enriched
            }
            return enriched
        }
        var result = try await addonMetadata(media, addons: addons)
        if !configuration.tmdbKey.isEmpty, let enriched = try? await TMDBService().detail(result, configuration: configuration) {
            result.logo = enriched.logo ?? result.logo
            result.background = enriched.background ?? result.background
            result.cast = enriched.cast?.isEmpty == false ? enriched.cast : result.cast
            result.director = enriched.director?.isEmpty == false ? enriched.director : result.director
        }
        return result
    }
    private func addonMetadata(_ media: Media, addons: [Addon]) async throws -> Media {
        let plans = try await resources(addons, "meta", media.type, media.id)
        let result = try await fetch(plans)
        for plan in plans {
            if let value = result.values.first(where: { $0.0.key == plan.key })?.1,
               let meta = Media.parse(value["meta"], kind: media.type) { return meta }
        }
        if media.id.hasPrefix("tt") && ["movie", "series"].contains(media.type),
           let value = try? await http.json("https://v3-cinemeta.strem.io/meta/\(media.type)/\(media.id).json"),
           let parsed = Media.parse(value["meta"], kind: media.type) { return parsed }
        throw HarborError(code: result.errors.first ?? "no-metadata")
    }

    func catalog(_ plan: RequestPlan, genre: String?, skip: Int) async throws -> CatalogRow {
        guard let definition = plan.catalog else { throw HarborError(code: "invalid-catalog") }
        let plans: [RequestPlan] = try await core.call("catalogs", ["addons": try .encoded([plan.addon]), "search": .null, "genre": genre.map(JSONValue.string) ?? .null, "skip": .integer(Int64(skip))])
        guard let request = plans.first(where: { $0.kind == plan.kind && $0.catalog?.id == definition.id }) else { throw HarborError(code: "catalog-unavailable") }
        let response = try await http.json(request.url, timeout: Double(request.timeoutMs) / 1000)
        // Keep the original plan identity/order across filters and pages.
        return try decodeCatalog(response, plan: plan)
    }

    private func decodeCatalog(_ response: JSONValue, plan: RequestPlan) throws -> CatalogRow {
        guard case .array(let values) = response["metas"] else { throw HarborError(code: "invalid-catalog-response") }
        var seen = Set<String>()
        let parsed = values.compactMap { Media.parse($0, kind: plan.kind) }.filter { seen.insert($0.identity).inserted }
        let metas = plan.key.hasPrefix("native-kids-") ? parsed.filter(\.safeForKids) : parsed
        guard values.isEmpty || !parsed.isEmpty else { throw HarborError(code: "invalid-catalog-response") }
        return CatalogRow(plan: plan, metas: metas, receivedCount: values.count)
    }

    func streams(_ media: Media, videoID: String, addons: [Addon], season: Int? = nil, episode: Int? = nil) async throws -> ([StreamOffer], [String]) {
        let plans = try await resources(addons, "stream", media.type, videoID)
        let responses = try await fetch(plans)
        var raw: [JSONValue] = []
        var errors = responses.errors
        for (plan, response) in responses.values {
            do {
                let streams: [JSONValue] = try await core.call("mapStreams", ["plan": try .encoded(plan), "response": response])
                raw.append(contentsOf: streams)
            } catch { errors.append("stream-response") }
        }
        let trust: JSONValue = .object(["kind": .string(media.type), "expectedTitle": .string(media.name), "expectedSeason": season.map { .integer(Int64($0)) } ?? .null, "expectedEpisode": episode.map { .integer(Int64($0)) } ?? .null])
        let result: JSONValue = try await core.call("rank", ["streams": .array(raw), "trust": trust, "score": .object(["mediaKind": .string(media.type), "respectAddonOrder": .bool(false)])])
        return (result["picker"]["all"].array.enumerated().map { StreamOffer(id: $0.offset, raw: $0.element) }, errors)
    }

    func resolve(_ offer: StreamOffer) async throws -> PlaybackSource {
        try await core.call("resolveDirect", ["stream": offer.raw])
    }

    private func resources(_ addons: [Addon], _ resource: String, _ kind: String, _ id: String) async throws -> [RequestPlan] {
        try await core.call("resources", ["addons": try .encoded(addons), "resource": .string(resource), "kind": .string(kind), "id": .string(id)])
    }

    private struct Responses { var values: [(RequestPlan, JSONValue)] = []; var errors: [String] = [] }
    private func fetch(_ plans: [RequestPlan]) async throws -> Responses {
        try await withThrowingTaskGroup(of: (RequestPlan, JSONValue?, String?).self) { group in
            for plan in plans {
                group.addTask {
                    do { return (plan, try await http.json(plan.url, timeout: Double(plan.timeoutMs) / 1000), nil) }
                    catch is CancellationError { throw CancellationError() }
                    catch let error as HarborError { return (plan, nil, error.code) }
                    catch { return (plan, nil, "invalid-response") }
                }
            }
            var responses = Responses()
            for try await (plan, data, error) in group {
                if let data { responses.values.append((plan, data)) }
                if let error { responses.errors.append(error) }
            }
            try Task.checkCancellation()
            return responses
        }
    }
}

private actor BuiltinCatalogProvider {
    static let shared = BuiltinCatalogProvider()
    private var cached: Addon?
    private var pending: Task<Addon, Error>?
    func cinemeta() async throws -> Addon {
        if let cached { return cached }
        if let pending { return try await pending.value }
        let task = Task { try await HarborService().install(HarborService.cinemetaManifest) }
        pending = task
        defer { pending = nil }
        let result = try await task.value
        cached = result
        return result
    }
}
