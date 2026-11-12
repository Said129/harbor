import Foundation
import Observation

struct LivePlaylistSource: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var url: String?
    var xtream: XtreamAccount?
    var xtreamContainer: String?
    /// Desktop's `epgUrl`: the guide address the user typed. It comes before any address derived from the playlist.
    var epgURL: String?
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
    /// Optional so documents saved before these fields existed still decode.
    var favoriteItems: [LiveChannel]?
    var pinnedChannels: [String]?
    var groupPrefs: [String: LiveGroupPrefs]?
    /// Desktop's `channel-stats.ts` play counts, keyed by channel id. Optional so older documents still decode.
    var channelPlays: [String: Int]?
}

@MainActor @Observable
final class LiveTVPreferences {
    let owner: String
    private var stored = LiveTVDocument()
    private(set) var ready = false
    private(set) var error: String?
    var sources: [LivePlaylistSource] { stored.sources }
    var favorites: Set<String> { stored.favorites }
    /// Desktop's favourites snapshot: favourites keep their own channel data, so they show when their playlist is not loaded.
    var favoriteItems: [LiveChannel] { stored.favoriteItems ?? [] }
    var pinnedChannels: [String] { stored.pinnedChannels ?? [] }
    func groupPrefs(for sourceID: String) -> LiveGroupPrefs { stored.groupPrefs?[sourceID] ?? LiveGroupPrefs() }
    /// How often each channel was started from this list, for Desktop's most-watched order.
    var channelPlayCounts: [String: Int] { stored.channelPlays ?? [:] }
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
        var next = stored; next.sources.removeAll { $0.id == source.id }; next.favorites = next.favorites.filter { !$0.hasPrefix(source.id + "::") }
        next.favoriteItems = next.favoriteItems?.filter { $0.source != source.id }
        next.pinnedChannels = next.pinnedChannels?.filter { !$0.hasPrefix(source.id + "::") }
        next.groupPrefs?[source.id] = nil
        next.channelPlays = next.channelPlays?.filter { !$0.key.hasPrefix(source.id + "::") }
        try save(next)
    }
    /// Desktop's `recordChannelPlay`: one more start for the channel. The 600 most-played channels are kept.
    func recordPlay(_ channel: LiveChannel) throws {
        var next = stored
        var plays: [String: Int] = next.channelPlays ?? [:]
        plays[channel.id, default: 0] += 1
        if plays.count > 600 {
            let kept: [(String, Int)] = plays.sorted { $0.value > $1.value }.prefix(600).map { ($0.key, $0.value) }
            plays = Dictionary(uniqueKeysWithValues: kept)
        }
        next.channelPlays = plays
        try save(next)
    }
    func toggle(_ channel: LiveChannel) throws {
        var next = stored
        var items = next.favoriteItems ?? []
        if next.favorites.contains(channel.id) { next.favorites.remove(channel.id); items.removeAll { $0.id == channel.id } }
        else { next.favorites.insert(channel.id); items.append(channel) }
        next.favoriteItems = items
        try save(next)
    }
    func togglePinned(_ channel: LiveChannel) throws {
        var next = stored
        next.pinnedChannels = LiveTVCatalogOrder.togglingChannelPin(next.pinnedChannels ?? [], channelID: channel.id)
        try save(next)
    }
    func toggleGroupPin(source sourceID: String, group: String) throws {
        var next = stored
        var map = next.groupPrefs ?? [:]
        map[sourceID] = LiveTVCatalogOrder.togglingPin(map[sourceID] ?? LiveGroupPrefs(), group: group)
        next.groupPrefs = map
        try save(next)
    }
    func toggleGroupHidden(source sourceID: String, group: String) throws {
        var next = stored
        var map = next.groupPrefs ?? [:]
        map[sourceID] = LiveTVCatalogOrder.togglingHidden(map[sourceID] ?? LiveGroupPrefs(), group: group)
        next.groupPrefs = map
        try save(next)
    }
    /// Desktop's favourites hydrate: favourites saved before snapshots existed get one once their playlist loads.
    func rememberFavorites(_ channels: [LiveChannel]) {
        guard ready else { return }
        var items = stored.favoriteItems ?? []
        var known = Set(items.map(\.id))
        var added = false
        for channel in channels where stored.favorites.contains(channel.id) {
            if known.insert(channel.id).inserted { items.append(channel); added = true }
        }
        guard added else { return }
        var next = stored; next.favoriteItems = items
        try? save(next)
    }
    private func save(_ next: LiveTVDocument) throws {
        guard ready, next.sources.count <= 32, next.favorites.count <= 10_000, (next.favoriteItems?.count ?? 0) <= 10_000, (next.pinnedChannels?.count ?? 0) <= 10_000 else { throw HarborError(code: "iptv-store") }
        let bytes = try JSONEncoder().encode(next)
        guard bytes.count <= 2 * 1024 * 1024 else { throw HarborError(code: "iptv-store") }
        try KeychainStore().write(next, key: key); stored = next
    }
}
