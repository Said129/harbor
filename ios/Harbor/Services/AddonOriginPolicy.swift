import Foundation

enum AddonOriginPolicy {
    static func base(_ value: String) -> String {
        value.hasSuffix("/manifest.json") ? String(value.dropLast("/manifest.json".count)) : value
    }
    static func bases(_ addons: [Addon], origin: MediaAddonOrigin?) -> [String] {
        guard let origin else { return [] }
        var result = origin.base.map { [base($0)] } ?? []
        for addon in addons where addon.enabled && addon.manifest["id"].string == origin.id {
            let value = base(addon.transportUrl)
            if !result.contains(value) { result.append(value) }
        }
        return result
    }
    static func isNative(_ media: Media) -> Bool {
        if ["tv", "channel"].contains(media.type) { return true }
        guard media.addonOrigin != nil else { return false }
        return media.id.range(of: "^tt[0-9]", options: .regularExpression) == nil
            && !["tmdb:", "kitsu:", "mal:"].contains(where: media.id.hasPrefix)
    }
    static func resourceURL(_ base: String, resource: String, kind: String, id: String) -> String? {
        guard var url = URLComponents(string: base), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil,
              base.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        guard let kind = kind.addingPercentEncoding(withAllowedCharacters: allowed),
              let id = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        var path = url.percentEncodedPath
        if path.hasSuffix("/manifest.json") { path = String(path.dropLast("/manifest.json".count)) }
        url.percentEncodedPath = path + "/" + resource + "/" + kind + "/" + id + ".json"
        url.fragment = nil
        return url.string
    }
    static func score(_ media: Media, addonOrder: Bool) -> JSONValue {
        var fields: [String: JSONValue] = ["mediaKind": .string(media.type == "anime" ? "series" : media.type), "respectAddonOrder": .bool(addonOrder)]
        fields["preferAddonId"] = media.addonOrigin.map { .string($0.id) }
        return .object(fields)
    }
    static func metadataURLs(_ media: Media, addons: [Addon]) -> [String] {
        var seen = Set<String>()
        return bases(addons, origin: media.addonOrigin).compactMap {
            resourceURL($0, resource: "meta", kind: media.type, id: media.id)
        }.filter { seen.insert($0).inserted }
    }
    static func streamTypes(_ addon: Addon, primary: String, id: String) -> [String] {
        [primary] + declaredStreamTypes(addon, id: id).filter { $0 != primary }
    }
    static func declaredStreamTypes(_ addon: Addon, id: String) -> [String] {
        let specific = addon.manifest["resources"].array.filter { $0["name"].string == "stream" }
        func accepts(_ values: JSONValue) -> Bool {
            let prefixes = values.array.compactMap(\.string)
            return prefixes.isEmpty || prefixes.contains(where: id.hasPrefix)
        }
        if specific.isEmpty {
            guard declaresStreams(addon), accepts(addon.manifest["idPrefixes"]) else { return [] }
            // A generic manifest may repeat a type. Request planning deduplicates URLs.
            return addon.manifest["types"].array.compactMap(\.string).filter { !$0.isEmpty }
        }
        var seen = Set<String>()
        return specific.filter { accepts($0["idPrefixes"]) }.flatMap { $0["types"].array }
            .compactMap(\.string).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    static func pluginID(_ base: String) -> String? {
        let prefix = "harbor-plugin://"
        guard base.hasPrefix(prefix) else { return nil }
        let rest = String(base.dropFirst(prefix.count))
        guard !rest.hasPrefix("repo/") else { return nil }
        let id = String(rest.prefix { $0 != "/" })
        return id.isEmpty ? nil : id
    }
    static func declaresStreams(_ addon: Addon) -> Bool {
        addon.manifest["resources"].array.contains { $0 == .string("stream") || $0["name"].string == "stream" }
    }
    static func skipsPlaybackRequests(_ addon: Addon) -> Bool {
        let id = addon.manifest["id"].string?.lowercased() ?? ""
        let url = addon.transportUrl.lowercased()
        if ["org.stremio.local", "app.torbox.stremio"].contains(id) || url.contains("/local-addon/") || url.contains("stremio.torbox.app") { return true }
        let label = [id, addon.name.lowercased(), url].joined(separator: " ")
        return label.range(of: #"aiostatus|aio[\s-]?status|--status--|stremio[\s-]?status"#, options: .regularExpression) != nil
    }
    static func timeout(_ addon: Addon) -> Int {
        let value = [addon.name, addon.manifest["id"].string ?? "", addon.transportUrl].joined(separator: " ").lowercased()
        return ["mediafusion", "comet", "torrentio", "knightcrawler", "aiostreams", "jackettio", "torbox"].contains(where: value.contains) ? 22_000 : 8_000
    }
}

struct AddonOriginMetadata: Sendable {
    func value(_ media: Media, addons: [Addon],
        load: @escaping @Sendable (String) async throws -> JSONValue = { try await HTTPClient().json($0, timeout: 8) }) async throws -> Media? {
        for url in AddonOriginPolicy.metadataURLs(media, addons: addons) {
            try Task.checkCancellation()
            do {
                let value = try await load(url); try Task.checkCancellation()
                if var result = Media.parse(value["meta"], kind: media.type) {
                    result.addonOrigin = media.addonOrigin ?? result.addonOrigin
                    return result
                }
            } catch is CancellationError { throw CancellationError() }
            catch { try Task.checkCancellation() }
        }
        return nil
    }
}

enum AddonOriginReplies {
    typealias Reply = (RequestPlan, JSONValue?, String?)

    static func fetch(_ plan: RequestPlan, fallbacks: [RequestPlan], retryPrimaryFailure: Bool = true,
        load: @escaping @Sendable (RequestPlan) async throws -> JSONValue = {
            try await HTTPClient().json($0.url, timeout: Double($0.timeoutMs) / 1_000)
        }) async throws -> Reply {
        @Sendable func query(_ candidate: RequestPlan) async throws -> Reply {
            try Task.checkCancellation()
            do {
                let value = try await load(candidate); try Task.checkCancellation()
                return (candidate, value, nil)
            } catch is CancellationError { throw CancellationError() }
            catch let error as HarborError { return (candidate, nil, error.code) }
            catch { return (candidate, nil, "invalid-response") }
        }
        let primary = try await query(plan)
        guard !fallbacks.isEmpty, primary.1?["streams"].array.isEmpty != false,
              primary.1 != nil || retryPrimaryFailure else { return primary }
        // A provider can declare several alternatives. Run them together, then
        // prefer the first populated response in declaration order.
        return try await withThrowingTaskGroup(of: (Int, Reply).self) { group in
            for (index, candidate) in fallbacks.enumerated() {
                group.addTask { (index, try await query(candidate)) }
            }
            var replies: [Int: Reply] = [:]
            for try await (index, reply) in group { replies[index] = reply }
            try Task.checkCancellation()
            let ordered = fallbacks.indices.compactMap { replies[$0] }
            if let match = ordered.first(where: { $0.1?["streams"].array.isEmpty == false }) { return match }
            if let last = ordered.last, last.1 != nil { return last }
            let failure = ordered.reversed().compactMap { $0.2 }.first ?? primary.2
            return (plan, nil, failure)
        }
    }
}
