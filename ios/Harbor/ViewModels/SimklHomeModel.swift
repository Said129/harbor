import Foundation
import Observation

/// Desktop's `buildSimklHomeRows` (`lib/simkl/home-rails.ts`) as Discovery rails for Home, one model per profile.
/// The rails read the profile's Simkl library after a library refresh, plus Simkl's calendar and trending feeds.
/// Home adds `rails` as it does the Trakt and Stremboxd rails (see the port report for the hook).
@MainActor @Observable final class SimklHomeModel {
    private static var models: [String: SimklHomeModel] = [:]
    /// One model per profile, so Home reads the rails of the profile on screen.
    static func forOwner(_ owner: String) -> SimklHomeModel {
        if let saved = models[owner] { return saved }
        let model = SimklHomeModel(owner: owner)
        models[owner] = model
        return model
    }

    private(set) var rows: [DiscoveryRail] = []
    private(set) var loading = false
    @ObservationIgnored private let owner: String
    @ObservationIgnored private let preferences: SimklHomeRailPreferences
    @ObservationIgnored private let account: SimklAccountStore
    @ObservationIgnored private let store: SimklLibraryStore
    @ObservationIgnored private let library: SimklLibraryModel
    @ObservationIgnored private let hydrator = TraktHomeHydrator()
    @ObservationIgnored private var loadedSignature: String?
    @ObservationIgnored private var generation = 0
    /// Desktop caches the trending feed for one hour.
    @ObservationIgnored private var trendingCache: (at: Date, entries: [SimklHomeRails.Trending])?

    init(owner: String, preferences: SimklHomeRailPreferences = .shared) {
        self.owner = owner
        self.preferences = preferences
        account = SimklAccountStore.forOwner(owner)
        store = SimklLibraryStore.forOwner(owner)
        library = SimklLibraryModel(account: account, store: store, active: { true })
    }

    /// The rails for Home. When a setting or the account changes, a reload starts in the background.
    var rails: [DiscoveryRail] {
        let current = signature
        if current != loadedSignature {
            loadedSignature = current
            Task { await load() }
        }
        return rows
    }

    /// Changes whenever a setting that alters the rails, or the signed-in account, changes.
    var signature: String {
        let token = account.session.map { EBookShelf.hash($0.accessToken) } ?? ""
        return [owner, preferences.settings.signature, token].joined(separator: "|")
    }

    /// Rebuilds the rows. A newer load started meanwhile wins.
    func load() async {
        generation += 1
        let current = generation
        loading = true
        defer { if current == generation { loading = false } }
        let built = await buildRows()
        if current == generation { rows = built }
    }

    private func buildRows() async -> [DiscoveryRail] {
        do { if !account.ready { try account.load() } } catch { loadedSignature = signature; return [] }
        loadedSignature = signature
        let settings = preferences.settings
        guard settings.homeRails, account.session != nil else { return [] }
        // Refresh the library the way the Simkl screen does; a failed refresh keeps the last saved snapshot.
        await library.refresh()
        let airings = settings.upNext ? await fetchAirings() : []
        let trending = settings.trending ? await fetchTrending() : []
        let plan = SimklHomeRails.sources(library: Array(store.snapshot.items.values), airings: airings, trending: trending,
            settings: settings, now: Date(), calendar: .current)
        let configuration = MetadataPreferences.shared.configuration()
        var built: [DiscoveryRail] = []
        for source in plan {
            let metas = await hydrate(Array(source.items.prefix(SimklHomeRails.perRail)), configuration: configuration)
            guard var rail = SimklHomeRails.rail(source, metas: metas) else { continue }
            let items = source.items, hydrator = self.hydrator
            // Paging: View All asks for page 1 onward, and page 1 is the first slice.
            rail.personal = PersonalDiscoverySource(available: { true }, page: { (page: Int) async throws -> [Media] in
                let offset = max(page - 1, 0) * SimklHomeRails.perRail
                let slice = Array(items.dropFirst(offset).prefix(SimklHomeRails.perRail))
                guard !slice.isEmpty else { return [] }
                return try await hydrator.hydrate(slice, configuration: configuration)
            })
            built.append(rail)
        }
        return built
    }

    private func hydrate(_ items: [TraktLibraryItem], configuration: MetadataConfiguration) async -> [Media] {
        (try? await hydrator.hydrate(items, configuration: configuration)) ?? []
    }

    /// Desktop's `fetchCdnCalendarCombined`: the TV and anime calendars together, in that order.
    private func fetchAirings() async -> [SimklHomeRails.Airing] {
        async let tv = fetchJSON("calendar/v2/tv.json")
        async let anime = fetchJSON("calendar/v2/anime.json")
        let tvAirings = SimklHomeRails.parseAirings(await tv)
        let animeAirings = SimklHomeRails.parseAirings(await anime)
        return tvAirings + animeAirings
    }

    private func fetchTrending() async -> [SimklHomeRails.Trending] {
        if let cache = trendingCache, Date().timeIntervalSince(cache.at) < 3_600 { return cache.entries }
        let entries = SimklHomeRails.parseTrending(await fetchJSON("discover/trending/today_100.json"))
        guard !entries.isEmpty else { return trendingCache?.entries ?? [] }
        trendingCache = (Date(), entries)
        return entries
    }

    /// The public Simkl CDN. Failure yields no rows, as Desktop's empty fallback does.
    private func fetchJSON(_ path: String) async -> JSONValue {
        let query = "client_id=" + HTTPClient.simklPublicClientID + "&app-name=harbor&app-version=0.9.132"
        // The calendar feed is large, so it gets a longer timeout than the default metadata request.
        return (try? await HTTPClient().json("https://data.simkl.in/" + path + "?" + query, timeout: 30)) ?? .null
    }
}
