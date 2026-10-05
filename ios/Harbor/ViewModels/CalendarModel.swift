import Foundation
import Observation

struct ReleaseEvent: Identifiable, Sendable {
    let media: Media
    let episode: Episode?
    let date: Date
    var id: String { media.identity + ":" + (episode?.id ?? "release") }
}

@MainActor @Observable
final class CalendarModel {
    var events: [ReleaseEvent] = []
    var loading = false
    var error: String?
    private var generation = 0
    private var metadata: [String: Media] = [:]
    private var signature = ""
    func load(month: Date, app: AppModel) async {
        generation += 1
        let current = generation
        let accountSignature = (app.user?.id ?? "guest") + app.addons.filter(\.enabled).map(\.id).joined()
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
    private func parseDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw) ?? ISO8601DateFormatter().date(from: String(raw.prefix(10)) + "T00:00:00Z")
    }
}
