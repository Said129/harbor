import Foundation

extension Addon {
    var configurable: Bool {
        manifest["behaviorHints"]["configurable"] == .bool(true) || manifest["behaviorHints"]["configurationRequired"] == .bool(true)
    }
    var configurationURL: URL? {
        guard configurable, var parts = URLComponents(string: transportUrl),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil,
              parts.user == nil, parts.password == nil,
              parts.percentEncodedPath.lowercased().hasSuffix("/manifest.json") else { return nil }
        // Desktop's manifestToConfigureUrl removes the manifest/query suffix.
        parts.percentEncodedPath = String(parts.percentEncodedPath.dropLast("manifest.json".count)) + "configure"
        parts.query = nil; parts.fragment = nil
        return parts.url
    }
    var logoURL: String? {
        guard let raw = manifest["logo"].string, let base = URL(string: transportUrl),
              let url = URL(string: raw, relativeTo: base)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url.absoluteString
    }
}

enum AddonReplacement {
    static func apply(_ replacement: Addon, replacing id: String, in addons: [Addon]) throws -> [Addon] {
        guard let index = addons.firstIndex(where: { $0.id == id }) else { throw HarborError(code: "addon-not-installed") }
        let original = addons[index]
        guard let manifestID = original.manifest["id"].string, !manifestID.isEmpty,
              replacement.manifest["id"].string == manifestID else { throw HarborError(code: "addon-reconfigure-mismatch") }
        guard !addons.enumerated().contains(where: { $0.offset != index && $0.element.id == replacement.id }) else { throw HarborError(code: "addon-reconfigure-duplicate") }
        var result = addons, updated = replacement
        updated.enabled = original.enabled
        result[index] = updated
        return result
    }
}
