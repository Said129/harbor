import Foundation

/// Desktop addon sharing: `manifestToShareUrl` (src/lib/addon-store.ts) builds the link the
/// detail page copies, and `normalizeInstallUrl` (src/components/installer-viewport.tsx) turns a
/// pasted `stremio://` or `https` link into the manifest URL that gets installed.
enum AddonSharing {
    enum Scheme: Sendable { case https, stremio }
    static let incomingLinksKey = "stremioDeeplinkInstall"

    static func acceptsIncomingLinks(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: incomingLinksKey) as? Bool ?? true
    }

    /// An OS-delivered install link opens the existing form. Content and authentication URLs
    /// are separate routes, and configured paths and queries must survive the scheme change.
    static func incomingManifest(_ url: URL) -> URL? {
        guard url.absoluteString.utf8.count <= 16_384,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "stremio",
              let host = parts.host, !host.isEmpty, host.lowercased() != "detail",
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.port.map({ (1...65_535).contains($0) }) ?? true else { return nil }
        guard parts.percentEncodedPath.hasSuffix("/manifest.json") ||
              parts.percentEncodedPath.hasSuffix("/configure") else { return nil }
        parts.scheme = "https"
        return parts.url
    }

    /// Desktop `manifestToShareUrl(transportUrl, scheme)`: only the leading http(s) scheme changes.
    static func shareText(transportUrl: String, scheme: Scheme) -> String {
        guard scheme == .stremio else { return transportUrl }
        for prefix in ["https://", "http://"] where transportUrl.prefix(prefix.count).lowercased() == prefix {
            return "stremio://" + String(transportUrl.dropFirst(prefix.count))
        }
        return transportUrl
    }

    /// The `stremio://` link offered for sharing an installed or browsed addon.
    static func shareURL(for addon: Addon) -> URL? {
        URL(string: shareText(transportUrl: addon.transportUrl, scheme: .stremio))
    }

    /// Desktop `normalizeInstallUrl`: a `stremio://` link becomes `https://`, a trimmed http(s)
    /// link is kept, and anything else is rejected. Matching is case-sensitive, as on Desktop.
    static func installLink(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("stremio://") { return "https://" + String(trimmed.dropFirst("stremio://".count)) }
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") { return trimmed }
        return nil
    }
}
