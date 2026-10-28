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
        var result = [primary]
        let specific = addon.manifest["resources"].array.filter { $0["name"].string == "stream" }
        func accepts(_ values: JSONValue) -> Bool {
            let prefixes = values.array.compactMap(\.string)
            return prefixes.isEmpty || prefixes.contains(where: id.hasPrefix)
        }
        let declared: [JSONValue]
        if !specific.isEmpty { declared = specific.filter { accepts($0["idPrefixes"]) }.flatMap { $0["types"].array } }
        else if declaresStreams(addon), accepts(addon.manifest["idPrefixes"]) { declared = addon.manifest["types"].array }
        else { declared = [] }
        for value in declared.compactMap(\.string) where !value.isEmpty && !result.contains(value) { result.append(value) }
        return result
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
    static func fetch(_ plan: RequestPlan, fallbacks: [RequestPlan],
        load: @escaping @Sendable (RequestPlan) async throws -> JSONValue = {
            try await HTTPClient().json($0.url, timeout: Double($0.timeoutMs) / 1_000)
        }) async throws -> (RequestPlan, JSONValue?, String?) {
        let candidates = [plan] + fallbacks
        var last: String?
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            do {
                let value = try await load(candidate); try Task.checkCancellation()
                if index < candidates.count - 1, value["streams"].array.isEmpty { continue }
                return (candidate, value, nil)
            } catch is CancellationError { throw CancellationError() }
            catch let error as HarborError { last = error.code }
            catch { last = "invalid-response" }
        }
        return (plan, nil, last)
    }
}
