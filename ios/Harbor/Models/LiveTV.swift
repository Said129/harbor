import Foundation
import Observation

struct LivePlaylistSource: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var url: String?
    var xtream: XtreamAccount?
    var xtreamContainer: String?
}
struct LiveChannel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let source: String
    let tvgID: String?
    let name: String
    let logo: String?
    let group: String?
    let url: String
    let catchup: String?
    let duration: Double?
    let attributes: [String: String]
    var headers: [String: String] {
        var values: [String: String] = [:]
        if let agent = attributes["vlcopt-user-agent"] ?? attributes["http-user-agent"], !agent.isEmpty { values["User-Agent"] = agent }
        if let referrer = attributes["vlcopt-referrer"] ?? attributes["http-referrer"], !referrer.isEmpty { values["Referer"] = referrer }
        if let cookie = attributes["vlcopt-cookie"], !cookie.isEmpty { values["Cookie"] = cookie }
        return values
    }
    var drm: Bool { attributes["kodiprop-license-type"] != nil || attributes["kodiprop-license-key"] != nil }
    var media: Media { Media(id: "iptv:" + id, type: "tv", name: name, poster: logo, background: logo, logo: logo, description: group, releaseInfo: "Live") }
}
private struct LiveTVDocument: Codable {
    var version = 1
    var sources: [LivePlaylistSource] = []
    var favorites: Set<String> = []
}

@MainActor @Observable
final class LiveTVPreferences {
    let owner: String
    private var stored = LiveTVDocument()
    private(set) var ready = false
    private(set) var error: String?
    var sources: [LivePlaylistSource] { stored.sources }
    var favorites: Set<String> { stored.favorites }
    private var key: String { "live-tv-" + EBookShelf.hash(owner) }
    init(owner: String) {
        self.owner = owner
        do {
            let saved = try KeychainStore().read(key, as: LiveTVDocument.self) ?? LiveTVDocument()
            guard saved.version == 1, saved.sources.count <= 32, saved.sources.allSatisfy({ UUID(uuidString: $0.id) != nil }) else { throw HarborError(code: "iptv-store") }
            stored = saved; ready = true
        } catch { self.error = "No se pudo recuperar Live TV. Las listas y los favoritos anteriores se conservan." }
    }
    func add(_ source: LivePlaylistSource) throws {
        var next = stored
        guard !next.sources.contains(where: { $0.id == source.id }), UUID(uuidString: source.id) != nil else { throw HarborError(code: "iptv-store") }
        next.sources.append(source); try save(next)
    }
    func remove(_ source: LivePlaylistSource) throws {
        var next = stored; next.sources.removeAll { $0.id == source.id }; next.favorites = next.favorites.filter { !$0.hasPrefix(source.id + "::") }; try save(next)
    }
    func toggle(_ channel: LiveChannel) throws {
        var next = stored
        if next.favorites.contains(channel.id) { next.favorites.remove(channel.id) } else { next.favorites.insert(channel.id) }
        try save(next)
    }
    private func save(_ next: LiveTVDocument) throws {
        guard ready, next.sources.count <= 32, next.favorites.count <= 10_000 else { throw HarborError(code: "iptv-store") }
        let bytes = try JSONEncoder().encode(next)
        guard bytes.count <= 2 * 1024 * 1024 else { throw HarborError(code: "iptv-store") }
        try KeychainStore().write(next, key: key); stored = next
    }
}
