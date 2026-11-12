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

    func install(_ url: String, timeout: TimeInterval = 8) async throws -> Addon {
        struct Normalized: Decodable, Sendable { let url: String }
        let normalized: Normalized = try await core.call("normalizeAddon", ["url": .string(url)])
        let manifest = try await http.json(normalized.url, timeout: timeout)
        return try await core.call("installAddon", ["url": .string(normalized.url), "manifest": manifest])
    }

    func catalogs(_ addons: [Addon], search: String? = nil, genre: String? = nil, skip: Int = 0, previous: [CatalogRow] = [], onRow: (@MainActor @Sendable (CatalogRow) -> Void)? = nil) async throws -> ([CatalogRow], [String]) {
        let requested: [RequestPlan] = try await core.call("catalogs", ["addons": try .encoded(addons), "search": search.map(JSONValue.string) ?? .null, "genre": genre.map(JSONValue.string) ?? .null, "skip": .integer(Int64(skip))])
        let plans = requested.filter { !$0.isPlaybackHistoryCatalog && AddonCatalogRules.isContentType($0.kind) }
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

    func metadata(_ media: Media, addons: [Addon], configuration supplied: MetadataConfiguration? = nil) async throws -> Media {
        let configuration: MetadataConfiguration
        if let supplied { configuration = supplied }
        else { configuration = await MetadataPreferences.shared.configuration() }
        let preferred = try await AddonOriginMetadata().value(media, addons: addons)
        let attempted = Set(AddonOriginPolicy.metadataURLs(media, addons: addons))
        if let preferred, AddonOriginPolicy.isNative(media) { return preferred }
        if media.id.hasPrefix("tmdb:") && !configuration.tmdbKey.isEmpty {
            let enriched: Media
            do { enriched = try await TMDBService().detail(media, configuration: configuration) }
            catch {
                try Task.checkCancellation()
                if let preferred { return preferred }
                throw error
            }
            if enriched.id != media.id {
                let provider: Media?
                if let preferred { provider = preferred }
                else { provider = try? await addonMetadata(enriched, addons: addons, attempted: attempted) }
                if var combined = provider {
                    combined.logo = enriched.logo ?? combined.logo; combined.background = enriched.background ?? combined.background
                    combined.artworkSourceID = enriched.artworkSourceID ?? combined.artworkSourceID
                    combined.imdbID = enriched.imdbID ?? (enriched.id.hasPrefix("tt") ? enriched.id : combined.imdbID)
                    combined.cast = enriched.cast ?? combined.cast; combined.director = enriched.director ?? combined.director
                    combined.details = enriched.details?.includingTrailers(from: combined.details) ?? combined.details
                    return combined
                }
                return enriched
            }
            return enriched
        }
        var result: Media
        if let preferred { result = preferred }
        else { result = try await addonMetadata(media, addons: addons, attempted: attempted) }
        if !configuration.tmdbKey.isEmpty, let enriched = try? await TMDBService().detail(result, configuration: configuration) {
            result.logo = enriched.logo ?? result.logo
            result.background = enriched.background ?? result.background
            result.cast = enriched.cast?.isEmpty == false ? enriched.cast : result.cast
            result.director = enriched.director?.isEmpty == false ? enriched.director : result.director
            result.details = enriched.details
        }
        return result
    }
    func related(_ media: Media, addons: [Addon]) async throws -> [Media] {
        guard media.id.range(of: "^tt[0-9]{7,}$", options: .regularExpression) != nil,
              ["movie", "series"].contains(media.type), let genre = media.genres?.first, !genre.isEmpty else { return [] }
        let providers = try await catalogProviders(addons)
        guard let provider = providers.first(where: { $0.enabled && $0.manifest["id"].string == "com.linvo.cinemeta" }) else { return [] }
        let plans: [RequestPlan] = try await core.call("catalogs", ["addons": try .encoded([provider]), "search": .null, "genre": .string(genre), "skip": .integer(0)])
        guard let plan = plans.first(where: { $0.kind == media.type && $0.catalog?.id == "top" && $0.catalog?.extra.first(where: { $0.name == "genre" })?.options.contains(genre) == true }) else { return [] }
        let response = try await http.json(plan.url, timeout: Double(plan.timeoutMs) / 1000)
        let row = try decodeCatalog(response, plan: plan)
        try Task.checkCancellation()
        return Array(row.metas.filter { $0.identity != media.identity }.prefix(30))
    }
    private func addonMetadata(_ media: Media, addons: [Addon], attempted: Set<String> = []) async throws -> Media {
        let plans = try await resources(addons, "meta", media.type, media.id).filter {
            !attempted.contains(AddonOriginPolicy.resourceURL($0.addon.transportUrl, resource: "meta", kind: media.type, id: media.id) ?? $0.url)
        }
        let result = try await fetch(plans)
        // Desktop's `resolveMeta` poster rule (MetaPosterPreference), read from the `preferCustomMetaAddon` setting.
        let answers: [(plan: RequestPlan, meta: Media)] = DetailSettingsRules.preferringCustomMeta(plans).compactMap { plan in
            guard let value = result.values.first(where: { $0.0.key == plan.key })?.1,
                  let meta = Media.parse(value["meta"], kind: media.type) else { return nil }
            return (plan: plan, meta: meta)
        }
        if !answers.isEmpty {
            let preferCustom = UserDefaults.standard.bool(forKey: "preferCustomMetaAddon")
            let choice = MetaPosterPreference.choose(answers.map { answer in
                MetaPosterPreference.MetaAnswer(isCinemeta: DetailSettingsRules.isCinemeta(answer.plan.addon.manifest["id"].string),
                                                hasPoster: !(answer.meta.poster ?? "").isEmpty)
            }, preferCustom: preferCustom)
            // Desktop returns nothing here; an answer without a poster is kept, as this service did before the rule.
            let answer = answers[choice.index ?? 0]
            var meta = answer.meta
            if choice.fillArtwork {
                var cinemeta = answers.first(where: { DetailSettingsRules.isCinemeta($0.plan.addon.manifest["id"].string) })?.meta
                if cinemeta == nil, let value = try? await http.json("https://v3-cinemeta.strem.io/meta/\(media.type)/\(media.id).json") {
                    cinemeta = Media.parse(value["meta"], kind: media.type)
                }
                if (meta.poster ?? "").isEmpty { meta.poster = cinemeta?.poster }
                if (meta.background ?? "").isEmpty { meta.background = cinemeta?.background }
                if (meta.logo ?? "").isEmpty { meta.logo = cinemeta?.logo }
            }
            meta.addonOrigin = meta.addonOrigin ?? media.addonOrigin ?? MediaAddonOrigin.from(answer.plan.addon)
            return meta
        }
        if AnimeService.isAnime(media.id), var parsed = try? await AnimeService.metadata(id: media.id, kind: media.type) {
            parsed.addonOrigin = media.addonOrigin; return parsed
        }
        if media.id.hasPrefix("tt") && ["movie", "series"].contains(media.type),
           !attempted.contains("https://v3-cinemeta.strem.io/meta/\(media.type)/\(media.id).json"),
           let value = try? await http.json("https://v3-cinemeta.strem.io/meta/\(media.type)/\(media.id).json"),
           var parsed = Media.parse(value["meta"], kind: media.type) { parsed.addonOrigin = media.addonOrigin; return parsed }
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
    func sourceCatalog(addonID: String, type: String, id: String, addons: [Addon]) async throws -> CatalogRow {
        // A folder selects one installed addon. Fetch the built-in manifest only
        // when that folder explicitly asks for Cinemeta and none is declared.
        let providers: [Addon]
        if addonID == "com.linvo.cinemeta", !addons.contains(where: { $0.manifest["id"].string == addonID }) {
            providers = try await catalogProviders(addons)
        } else { providers = addons }
        guard let addon = providers.first(where: { $0.enabled && $0.manifest["id"].string == addonID }) else { throw HarborError(code: "custom-source-addon") }
        let plans: [RequestPlan] = try await core.call("catalogs", ["addons": try .encoded([addon]), "search": .null, "genre": .null, "skip": .integer(0)])
        guard let plan = plans.first(where: { $0.catalog?.id == id && $0.catalog?.type == type }) else { throw HarborError(code: "custom-source-catalog") }
        return CatalogRow(plan: plan, metas: [])
    }

    private func decodeCatalog(_ response: JSONValue, plan: RequestPlan) throws -> CatalogRow {
        guard case .array(let values) = response["metas"] else { throw HarborError(code: "invalid-catalog-response") }
        var seen = Set<String>()
        let parsed = AddonCatalogRules.collapseEpisodeMetas(values.compactMap { value -> Media? in
            guard var media = Media.parse(value, kind: plan.kind) else { return nil }
            media.addonOrigin = media.addonOrigin ?? MediaAddonOrigin.from(plan.addon)
            return media
        }).filter { seen.insert($0.identity).inserted }
        guard values.isEmpty || !parsed.isEmpty else { throw HarborError(code: "invalid-catalog-response") }
        return CatalogRow(plan: plan, metas: parsed, receivedCount: values.count)
    }

    /// Desktop's score options with the configured debrid providers, so a stream
    /// cached on one of them ranks as such.
    static func scoring(_ media: Media, addonOrder: Bool, active: [DebridProvider], sources: StreamSourceSettings = .init()) -> JSONValue {
        guard case .object(var fields) = AddonOriginPolicy.score(media, addonOrder: addonOrder) else { return AddonOriginPolicy.score(media, addonOrder: addonOrder) }
        if !active.isEmpty { fields["activeDebrids"] = .array(active.map { JSONValue.string($0.rawValue) }) }
        // The rest of Desktop's score options: language preference, release date and runtime.
        if !sources.languages.isEmpty { fields["preferredLanguages"] = .array(sources.languages.map(JSONValue.string)) }
        if let released = media.released, !released.isEmpty { fields["releaseDate"] = .string(released) }
        if let runtime = Self.runtimeMinutes(media.runtime) { fields["runtimeMinutes"] = .integer(Int64(runtime)) }
        return .object(fields)
    }
    /// Desktop's `runtimeMinutes`: the first number of "148 min" or "2h 28min" style text.
    static func runtimeMinutes(_ text: String?) -> Int? {
        guard let text, let range = text.range(of: "[0-9]+", options: .regularExpression), let value = Int(text[range]), value > 0 else { return nil }
        return value
    }

    /// One partial list while addons are still answering: the ranked offers so far and how
    /// many of the requests have finished (Desktop's `onProgress` and addon quorum).
    struct StreamBatch: Sendable {
        let offers: [StreamOffer]
        let answered: Int
        let total: Int
    }
    /// Desktop emits a partial at most every 250 ms and re-checks debrid caches at most
    /// every 1.5 s, so a burst of answers neither floods the list nor the providers.
    static let partialInterval = Duration.milliseconds(250)
    static let debridCheckInterval = Duration.milliseconds(1500)

    private enum StreamEvent: Sendable {
        case reply(RequestPlan, JSONValue?, String?)
        case plugin(HarborPluginStreamBatch)
        case verified([String], DebridVerification)
        case library([JSONValue])
    }

    /// The final list with what Desktop's picker needs to explain an empty one: how many
    /// streams the addons returned and why the safety filter rejected the others.
    struct StreamResults: Sendable {
        let offers: [StreamOffer]
        let errors: [String]
        let received: Int
        let rejected: [String]
        /// Requests sent to addons; none means no addon accepts this title's IDs.
        let requests: Int
        /// The streams the safety filter set aside, shaped like ranked ones, for the switcher's "Show flagged".
        var flagged: [JSONValue] = []
    }

    /// Desktop's switcher lists a rejected stream with a zero score, a `filtered:` reason and the ROUGH tier.
    /// A rejection without a stream is dropped.
    static func flaggedStream(_ rejection: JSONValue) -> JSONValue? {
        var fields = rejection["stream"].objectValue
        if fields.isEmpty { return nil }
        let reason = rejection["reason"].string ?? ""
        fields["tier"] = .string("ROUGH")
        fields["score"] = .integer(0)
        fields["reasons"] = .array([.object(["signal": .string("filtered:" + reason), "delta": .integer(0)])])
        return .object(fields)
    }

    func streams(_ media: Media, videoID: String, addons: [Addon], season: Int? = nil, episode: Int? = nil, unfiltered: Bool = false,
        pluginSource: (@Sendable () async throws -> HarborPluginStreamBatch)? = nil, debrid: DebridClient? = nil,
        progress: (@MainActor @Sendable (StreamBatch) async -> Void)? = nil) async throws -> ([StreamOffer], [String]) {
        let results = try await streamResults(media, videoID: videoID, addons: addons, season: season, episode: episode,
                                              filterLevel: unfiltered ? "off" : nil, pluginSource: pluginSource, debrid: debrid, progress: progress)
        return (results.offers, results.errors)
    }

    /// Desktop's `runPipeline`: requests run together, each answer is ranked into a partial
    /// list for `progress`, and debrid verification runs alongside instead of after.
    /// `filterLevel` overrides the profile's safety level for this title (Search wider, Show all).
    /// `trustEpisode` is the episode the safety filter expects when it differs from the requested
    /// coordinates (Desktop's IMDb-aligned `effSeason`/`effEpisode`).
    func streamResults(_ media: Media, videoID: String, addons: [Addon], season: Int? = nil, episode: Int? = nil, filterLevel: String? = nil,
        trustEpisode: (season: Int?, episode: Int?)? = nil, animeAliases: [Int] = [],
        pluginSource: (@Sendable () async throws -> HarborPluginStreamBatch)? = nil, debrid: DebridClient? = nil,
        progress: (@MainActor @Sendable (StreamBatch) async -> Void)? = nil) async throws -> StreamResults {
        let preferences = await StreamPreferences.shared.configuration()
        let requested = try await streamRequests(media, videoID: videoID, addons: addons, season: season, episode: episode)
        // The profile's wait time and addon order shape the requests, as in Desktop's pipeline.
        let selection = StreamAddonPriority.tune(requested, settings: preferences.sources, addons: addons)
        // Items an addon lists itself are never filtered (Desktop's `addonNative`).
        let level = AddonOriginPolicy.isNative(media) ? "off" : filterLevel ?? preferences.level
        let expected = trustEpisode ?? (season: season, episode: episode)
        let trust = StreamFilterConfiguration(level: level, addonOrder: preferences.addonOrder, sources: preferences.sources).trust(media, season: expected.season, episode: expected.episode)
        let active = await debrid?.providers ?? []
        let score = Self.scoring(media, addonOrder: preferences.addonOrder, active: active, sources: preferences.sources)
        // Desktop's fetchLibraryStreams: the title's matches in the provider libraries, merged ahead of the addon streams.
        var libraryStreams: [JSONValue] = []
        // Desktop's anime inputs: the absolute episode of a kitsu or mal id, its accepted aliases, and each stream's filename fields.
        let absolute = AnimeStreamEnrichment.absoluteEpisode(videoID)
        let animeOptions: JSONValue = .object(["absoluteEpisode": absolute.map { JSONValue.integer(Int64($0)) } ?? .null,
                                               "aliases": .array(animeAliases.map { JSONValue.integer(Int64($0)) })])
        func ranked(_ raw: [JSONValue], _ verification: DebridVerification) async throws -> (offers: [StreamOffer], rejected: [String], flagged: [JSONValue]) {
            let merged = libraryStreams.isEmpty ? raw : DebridLibraryMerge.mergeAndDedupe(library: libraryStreams, addons: raw)
            var streams = StreamRequestPolicy.deduplicated(merged)
            if absolute != nil { streams = streams.map(AnimeStreamEnrichment.withFields) }
            let result: JSONValue = try await core.call("rank", ["streams": .array(streams), "trust": trust, "score": score, "debrid": verification.flags, "anime": animeOptions])
            let flagged: [JSONValue] = result["rejected"].array.compactMap { Self.flaggedStream($0) }
            return (Self.ordered(result, addons: addons, preferences: preferences), result["rejected"].array.compactMap { $0["reason"].string }, flagged)
        }
        func rank(_ raw: [JSONValue], _ verification: DebridVerification) async throws -> [StreamOffer] { try await ranked(raw, verification).offers }
        func fresh(_ raw: [JSONValue], checked: Set<String>) -> [JSONValue] {
            raw.filter { stream in stream["infoHash"].string.map { !checked.contains($0.lowercased()) } ?? false }
        }
        let total = selection.plans.count, clock = ContinuousClock()
        let librarySearch = debrid != nil && !active.isEmpty
        let libraryQuery = DebridLibraryMerge.query(type: media.type, title: media.name, releaseInfo: media.releaseInfo, season: expected.season, episode: expected.episode)
        return try await withThrowingTaskGroup(of: StreamEvent.self) { group in
            for plan in selection.plans {
                let fallbacks = selection.fallbacks[plan.key] ?? []
                let retryPrimaryFailure = selection.originFallbacks.contains(plan.key)
                group.addTask {
                    let (answered, data, error) = try await AddonOriginReplies.fetch(plan, fallbacks: fallbacks, retryPrimaryFailure: retryPrimaryFailure)
                    return .reply(answered, data, error)
                }
            }
            if let pluginSource {
                group.addTask {
                    let batch = try await Self.pluginResponse(pluginSource)
                    return .plugin(batch)
                }
            }
            if let debrid, librarySearch {
                group.addTask {
                    let found = await DebridStreamVerifier.bounded({ await DebridLibraryMerge.libraryStreams(providers: active, query: libraryQuery, list: DebridLibraryMerge.lister(debrid)) })
                    return .library(found ?? [])
                }
            }
            var raw: [JSONValue] = [], errors: [String] = [], answered = 0
            var outstanding = selection.plans.count + (pluginSource == nil ? 0 : 1) + (librarySearch ? 1 : 0)
            var verification = DebridVerification(), checked = Set<String>(), verifying = false
            var lastCheck: ContinuousClock.Instant?, lastPartial: ContinuousClock.Instant?
            while let event = try await group.next() {
                outstanding -= 1
                var forcePartial = false
                switch event {
                case .reply(let plan, let data, let error):
                    answered += 1
                    if let error { errors.append(error) }
                    if let data {
                        do {
                            let streams: [JSONValue] = try await core.call("mapStreams", ["plan": try .encoded(plan), "response": data])
                            raw += streams.map(StreamRequestPolicy.recoveringUncachedIdentity)
                        } catch { errors.append("stream-response") }
                    }
                case .plugin(let batch):
                    raw += batch.streams; errors += batch.errors
                case .verified(let hashes, let result):
                    checked.formUnion(hashes); verification.merge(result); verifying = false; lastCheck = clock.now
                    forcePartial = !result.isEmpty
                case .library(let found):
                    libraryStreams = found
                    verification.merge(DebridLibraryMerge.verification(of: found))
                    forcePartial = !found.isEmpty
                }
                try Task.checkCancellation()
                // Providers confirm the new hashes while the other addons keep answering.
                let unchecked = fresh(raw, checked: checked)
                if debrid != nil, !active.isEmpty, !verifying, !unchecked.isEmpty, outstanding > 0,
                   lastCheck.map({ clock.now - $0 >= Self.debridCheckInterval }) ?? true {
                    verifying = true; outstanding += 1
                    let hashes = DebridStreamVerifier.hashes(unchecked)
                    group.addTask {
                        let result = await DebridStreamVerifier.verify(unchecked, client: debrid)
                        return .verified(hashes, result)
                    }
                }
                // The last answer goes straight to the final list instead of a partial.
                guard let progress, !raw.isEmpty || !libraryStreams.isEmpty, outstanding > 0,
                      forcePartial || lastPartial.map({ clock.now - $0 >= Self.partialInterval }) ?? true else { continue }
                lastPartial = clock.now
                if let offers = try? await rank(raw, verification), !offers.isEmpty {
                    await progress(StreamBatch(offers: offers, answered: answered, total: total))
                }
            }
            try Task.checkCancellation()
            // Anything that arrived after the last check is confirmed before the final list.
            let unchecked = fresh(raw, checked: checked)
            if !unchecked.isEmpty { verification.merge(await DebridStreamVerifier.verify(unchecked, client: debrid)) }
            try Task.checkCancellation()
            let final = try await ranked(raw, verification)
            return StreamResults(offers: final.offers, errors: errors, received: StreamRequestPolicy.deduplicated(raw).count, rejected: final.rejected, requests: total, flagged: final.flagged)
        }
    }

    /// The ranked list in the order the profile asked for, numbered after any reordering.
    static func ordered(_ result: JSONValue, addons: [Addon], preferences: StreamFilterConfiguration) -> [StreamOffer] {
        let ranked = result["picker"]["all"].array.enumerated().map { StreamOffer(id: $0.offset, raw: $0.element) }
        let active = StreamAddonPriority.ranker(addons: addons, priority: preferences.sources.priority) != nil
        return StreamAddonPriority.order(ranked, active: active).enumerated().map { StreamOffer(id: $0.offset, raw: $0.element.raw) }
    }

    struct StreamRequests: Sendable {
        let plans: [RequestPlan]
        let fallbacks: [String: [RequestPlan]]
        var originFallbacks: Set<String> = []
    }
    func streamRequests(_ media: Media, videoID: String, addons: [Addon], season: Int? = nil, episode: Int? = nil) async throws -> StreamRequests {
        var requested: [RequestPlan] = []
        let kind = media.type == "anime" ? "series" : media.type
        let ids = StreamRequestPolicy.ids(media, videoID: videoID, season: season, episode: episode)
        var eligible = addons
        // Keep the original indexes as addon priority while excluding control-only endpoints.
        for index in eligible.indices where eligible[index].enabled && AddonOriginPolicy.skipsPlaybackRequests(eligible[index]) {
            eligible[index].enabled = false
        }
        for id in ids {
            requested += try await resources(eligible, "stream", kind, id)
        }
        let originBases = AddonOriginPolicy.bases(eligible, origin: media.addonOrigin)
        let accepted = Set(requested.map(\.key))
        var fallbacks: [String: [RequestPlan]] = [:]
        var originFallbacks = Set<String>()
        for (index, addon) in eligible.enumerated() where addon.enabled && AddonOriginPolicy.declaresStreams(addon) {
            func plans(id: String, types: [String]) -> [RequestPlan] {
                var seen = Set<String>()
                let timeout = AddonOriginPolicy.timeout(addon)
                return types.compactMap { type in
                    guard let url = AddonOriginPolicy.resourceURL(addon.transportUrl, resource: "stream", kind: type, id: id),
                          seen.insert(url).inserted else { return nil }
                    return RequestPlan(key: "\(index):stream:\(type):\(id)", url: url, title: addon.name, kind: type, addon: addon,
                                       addonPriority: index, timeoutMs: timeout, catalog: nil)
                }
            }
            if originBases.contains(AddonOriginPolicy.base(addon.transportUrl)) {
                let id = media.episodic ? videoID : media.id
                let candidates = plans(id: id, types: AddonOriginPolicy.streamTypes(addon, primary: kind, id: id))
                guard let primary = candidates.first else { continue }
                if !accepted.contains(primary.key) { requested.append(primary) }
                fallbacks[primary.key] = Array(candidates.dropFirst())
                originFallbacks.insert(primary.key)
                continue
            }
            let matches = ids.filter { accepted.contains("\(index):stream:\(kind):\($0)") }
            if matches.isEmpty {
                guard let match = StreamRequestPolicy.declaredTypeID(ids, addon: addon) else { continue }
                let candidates = plans(id: match.id, types: match.types)
                guard let primary = candidates.first else { continue }
                requested.append(primary)
                fallbacks[primary.key] = Array(candidates.dropFirst())
            } else {
                for id in matches where !StreamRequestPolicy.hasStandardScheme(id) {
                    let alternatives = AddonOriginPolicy.declaredStreamTypes(addon, id: id).filter { $0 != kind }
                    fallbacks["\(index):stream:\(kind):\(id)"] = plans(id: id, types: alternatives)
                }
            }
        }
        return .init(plans: StreamRequestPolicy.plans(requested), fallbacks: fallbacks, originFallbacks: originFallbacks)
    }

    private static func pluginResponse(_ provider: (@Sendable () async throws -> HarborPluginStreamBatch)?) async throws -> HarborPluginStreamBatch {
        guard let provider else { return .init() }
        do { return try await provider() }
        catch is CancellationError { throw CancellationError() }
        catch { try Task.checkCancellation(); return .init(errors: ["plugin-source"]) }
    }

    /// A stream with a URL plays directly. One that is only a torrent hash is
    /// resolved through the profile's debrid services, as Desktop does.
    func resolve(_ offer: StreamOffer, debrid: DebridClient? = nil, season: Int? = nil, episode: Int? = nil,
                 userCommitted: Bool = true, downloadsOwner: String? = nil) async throws -> PlaybackSource {
        try Task.checkCancellation()
        let raw = offer.raw
        let hasHash = raw["infoHash"].string?.isEmpty == false
        if hasHash, let downloadsOwner,
           let completed = await DownloadManager.shared.completedSource(raw, owner: downloadsOwner, season: season, episode: episode) {
            try Task.checkCancellation()
            return completed
        }
        let hasURL = raw["url"].string?.isEmpty == false
        if hasURL || !hasHash {
            let source: PlaybackSource = try await core.call("resolveDirect", ["stream": raw])
            if let request = DirectStreamPolicy.probeRequest(url: source.url, headers: source.headers,
                                                             userCommitted: userCommitted, hasHash: hasHash) {
                let webpage = await DirectStreamPolicy.isWebPage(request)
                try Task.checkCancellation()
                if webpage { throw HarborError(code: "stream-web-page") }
            }
            let declaredSize = raw["behaviorHints"]["videoSize"].numericValue
            if DebridStreamResolver.validSize(declaredSize, expectedSize: raw["size"].numericValue) { return source }
            guard hasHash, let debrid, !(await debrid.providers).isEmpty else { throw HarborError(code: "stub-or-error-video") }
        }
        return try await resolveTorrent(raw, debrid: debrid, season: season, episode: episode)
    }

    /// Desktop's order for a torrent hash (`resolve.ts`): the debrid services first when the profile has any, and the remote
    /// streaming server (Settings > Streaming) after them, or first when there is no debrid service at all.
    private func resolveTorrent(_ raw: JSONValue, debrid: DebridClient?, season: Int?, episode: Int?) async throws -> PlaybackSource {
        let remote = await Self.remoteResolver()
        let hasDebrid: Bool
        if let debrid { hasDebrid = !(await debrid.providers).isEmpty } else { hasDebrid = false }
        guard let remote else { return try await DebridStreamResolver.resolve(raw, client: debrid, season: season, episode: episode) }
        guard hasDebrid else { return try await Self.resolveRemote(remote, raw, season: season, episode: episode) }
        do {
            return try await DebridStreamResolver.resolve(raw, client: debrid, season: season, episode: episode)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return try await Self.resolveRemote(remote, raw, season: season, episode: episode)
        }
    }

    private static func remoteResolver() async -> StremioServerResolver? {
        await MainActor.run {
            StremioServerResolver.live(address: StremioServerPreferences.shared.address, strict: StremioServerPreferences.shared.strict)
        }
    }

    private static func resolveRemote(_ remote: StremioServerResolver, _ raw: JSONValue, season: Int?, episode: Int?) async throws -> PlaybackSource {
        switch await remote.resolve(raw, season: season, episode: episode) {
        case .stream(let url, _):
            // The stream's own subtitle entries pass through as the direct path does (`resolveDirect` keeps `subtitles`).
            return PlaybackSource(url: url, headers: nil, subtitles: try? raw["subtitles"].decoded([PlaybackSource.Subtitle].self), via: "remote-server")
        case .failure(let code):
            throw HarborError(code: code)
        }
    }

    func automaticStreams(_ offers: [StreamOffer], media: Media, season: Int?, episode: Int?, debrid: DebridClient? = nil, addons: [Addon] = []) async throws -> [StreamOffer] {
        let preferences = await StreamPreferences.shared.configuration()
        let trust = (AddonOriginPolicy.isNative(media) ? StreamFilterConfiguration(level: "off", addonOrder: preferences.addonOrder, sources: preferences.sources) : preferences).trust(media, season: season, episode: episode)
        // Ranking again must keep the provider verification the first ranking applied.
        let verification = DebridVerification.from(offers: offers.map(\.raw))
        let active = await debrid?.providers ?? []
        let result: JSONValue = try await core.call("rank", ["streams": .array(offers.map(\.raw)), "trust": trust, "score": Self.scoring(media, addonOrder: preferences.addonOrder, active: active, sources: preferences.sources), "debrid": verification.flags])
        return Self.ordered(result, addons: addons, preferences: preferences)
    }

    private func resources(_ addons: [Addon], _ resource: String, _ kind: String, _ id: String) async throws -> [RequestPlan] {
        try await core.call("resources", ["addons": try .encoded(addons), "resource": .string(resource), "kind": .string(kind), "id": .string(id)])
    }

    private struct Responses { var values: [(RequestPlan, JSONValue)] = []; var errors: [String] = [] }
    private func fetch(_ plans: [RequestPlan], fallbacks: [String: [RequestPlan]] = [:]) async throws -> Responses {
        try await withThrowingTaskGroup(of: (RequestPlan, JSONValue?, String?).self) { group in
            for plan in plans {
                group.addTask {
                    try await AddonOriginReplies.fetch(plan, fallbacks: fallbacks[plan.key] ?? [])
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
