import Foundation
import Observation

struct ReleaseEvent: Identifiable, Sendable {
    let media: Media
    let episode: Episode?
    let date: Date
    /// The line a calendar source prints for the release ("Show S01E02: Title"); the library prints the show and its episode instead.
    var label: String? = nil
    var hasTime = false
    var isAnime = false
    var id: String { media.identity + ":" + (episode?.id ?? label ?? "release") }
    /// The type filter's value: movie, series or anime.
    var kind: String { isAnime || media.type == "anime" ? "anime" : (media.type == "movie" ? "movie" : "series") }
}

@MainActor @Observable
final class CalendarModel {
    var events: [ReleaseEvent] = []
    var loading = false
    var error: String?
    private var generation = 0
    private var metadata: [String: Media] = [:]
    private var signature = ""
    func load(month: Date, app: AppModel, source: CalendarSource = .library) async {
        if source != .library { await loadSource(source, month: month, app: app); return }
        generation += 1
        let current = generation
        let accountSignature = app.accountOperationScope + app.addons.filter(\.enabled).map(\.id).joined()
        if accountSignature != signature { metadata = [:]; signature = accountSignature }
        let records = app.library.items.filter { $0.bookmarked || $0.continuing }
        loading = true; error = nil; events = []
        defer { if current == generation { loading = false } }
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return }
        var failures = 0
        let cachedMetadata = metadata; let service = app.service; let addons = app.addons
        await withTaskGroup(of: (String, Media?).self) { group in
            var iterator = records.compactMap(\.media).makeIterator()
            func enqueue(_ media: Media) {
                let cached = cachedMetadata[media.identity]
                group.addTask {
                    if let cached { return (media.identity, cached) }
                    return (media.identity, try? await service.metadata(media, addons: addons))
                }
            }
            for _ in 0..<4 { if let media = iterator.next() { enqueue(media) } }
            for await (id, media) in group {
                guard current == generation, !Task.isCancelled else { group.cancelAll(); return }
                if let media {
                    metadata[id] = media
                    if media.episodic {
                        for episode in media.videos ?? [] {
                            if let date = episode.releaseDate, interval.contains(date) { events.append(ReleaseEvent(media: media, episode: episode, date: date)) }
                        }
                    } else if let raw = media.released, let date = parseDate(raw), interval.contains(date) {
                        events.append(ReleaseEvent(media: media, episode: nil, date: date))
                    }
                    events.sort { $0.date < $1.date }
                } else { failures += 1 }
                if let media = iterator.next() { enqueue(media) }
            }
        }
        guard current == generation, !Task.isCancelled else { return }
        if failures > 0 && events.isEmpty { error = "No se pudieron recuperar algunas fechas de tu biblioteca. Puedes volver a intentarlo." }
    }
    /// One of Desktop's other sources: All upcoming (TMDB), My Trakt, Trakt anticipated or Anime (AniList).
    private func loadSource(_ source: CalendarSource, month: Date, app: AppModel) async {
        generation += 1
        let current = generation
        loading = true; error = nil; events = []
        defer { if current == generation { loading = false } }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month], from: month)
        guard let year = parts.year, let number = parts.month else { return }
        var fetcher = CalendarFetcher(); fetcher.calendar = calendar
        let items: [CalendarItem]
        switch source {
        case .library:
            return
        case .all:
            let configuration = MetadataPreferences.shared.configuration()
            items = await fetcher.allUpcoming(key: configuration.tmdbKey, region: configuration.region, year: year, month: number)
        case .trakt:
            let owner = app.personalOwner, scope = app.accountOperationScope
            let account = TraktAccountStore.forOwner(owner)
            do { if !account.ready { try account.load() } } catch { return }
            guard account.session != nil else { return }
            let lease: TraktClient.Active = { [weak app] in app?.personalOwner == owner && app?.accountOperationScope == scope && app?.storageReady == true }
            fetcher.mine = { endpoint in
                guard let value = try? await account.response(.home(endpoint), active: lease), case .array = value else { return nil }
                return value
            }
            items = await fetcher.myTrakt(year: year, month: number)
        case .anticipated:
            items = await fetcher.anticipated(year: year, month: number)
        case .anime:
            items = await fetcher.animeAiring(year: year, month: number)
        }
        guard current == generation, !Task.isCancelled else { return }
        events = items.compactMap { item -> ReleaseEvent? in
            guard let date = item.instant ?? CalendarTime.startOfDay(item.releaseDate, calendar: calendar) else { return nil }
            return ReleaseEvent(media: item.media, episode: nil, date: date, label: item.name, hasTime: item.instant != nil, isAnime: item.isAnime)
        }
    }
    private func parseDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw) ?? ISO8601DateFormatter().date(from: String(raw.prefix(10)) + "T00:00:00Z")
    }
}
