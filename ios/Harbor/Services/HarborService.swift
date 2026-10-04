import Foundation

struct HarborService: Sendable {
    let core = CoreBridge()
    let http = HTTPClient()
    static let cinemetaManifest = "https://v3-cinemeta.strem.io/manifest.json"

    func install(_ url: String) async throws -> Addon {
        struct Normalized: Decodable, Sendable { let url: String }
        let normalized: Normalized = try await core.call("normalizeAddon", ["url": .string(url)])
        let manifest = try await http.json(normalized.url)
        return try await core.call("installAddon", ["url": .string(normalized.url), "manifest": manifest])
    }

    func catalogs(_ addons: [Addon], search: String? = nil, genre: String? = nil, skip: Int = 0) async throws -> ([CatalogRow], [String]) {
        let plans: [RequestPlan] = try await core.call("catalogs", ["addons": try .encoded(addons), "search": search.map(JSONValue.string) ?? .null, "genre": genre.map(JSONValue.string) ?? .null, "skip": .integer(Int64(skip))])
        let responses = try await fetch(plans)
        var rows: [CatalogRow] = []
        var errors = responses.errors
        for (plan, value) in responses.values {
            do {
                guard case .array = value["metas"] else { throw HarborError(code: "invalid-catalog-response") }
                let metas = try value["metas"].decoded([Media].self)
                rows.append(CatalogRow(plan: plan, metas: metas))
            } catch { errors.append("catalog-response") }
        }
        return (plans.compactMap { plan in rows.first { $0.id == plan.key } }, errors)
    }

    func metadata(_ media: Media, addons: [Addon]) async throws -> Media {
        let plans = try await resources(addons, "meta", media.type, media.id)
        let result = try await fetch(plans)
        for plan in plans {
            if let value = result.values.first(where: { $0.0.key == plan.key })?.1,
               value["meta"] != .null { return try value["meta"].decoded(Media.self) }
        }
        throw HarborError(code: result.errors.first ?? "no-metadata")
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
