import Foundation

/// A presentation slot references a real franchise entry, not a fabricated stream ID.
struct AnimeFranchiseExtra: Identifiable, Sendable {
    let entry: AnimeFranchiseEntry
    let slot: TVDBOrderSlot
    var id: String { entry.id + "|" + String(slot.id) }
    var name: String { slot.name.isEmpty ? entry.media.name : slot.name }
    var image: String? { slot.image ?? entry.media.background ?? entry.media.poster }

    static func match(_ slot: TVDBOrderSlot, entries: [AnimeFranchiseEntry], claimed: Set<String>) -> Self? {
        let eligible = entries.filter { $0.extra && !claimed.contains($0.id) }
        let title = normalized(slot.name)
        let exact = title.isEmpty ? nil : eligible.first { normalized($0.media.name) == title }
        let entry = exact ?? eligible.first { entry in
            guard let first = parsed(entry.startDate), let second = parsed(slot.aired) else { return false }
            return abs(first.timeIntervalSince(second)) <= 86_400
        }
        return entry.map { Self(entry: $0, slot: slot) }
    }

    private static func normalized(_ value: String) -> String {
        value.decomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: "", options: .regularExpression)
    }
    private static func parsed(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateParser.shared.date(value) ?? ISO8601DateParser.shared.date(String(value.prefix(10)) + "T00:00:00Z")
    }
}

enum EpisodeOrderRow: Identifiable, Sendable {
    case episode(Episode)
    case franchise(AnimeFranchiseExtra)
    var id: String {
        switch self {
        case .episode(let episode): return "episode:" + episode.routingKey
        case .franchise(let extra): return "franchise:" + extra.id
        }
    }
}

struct MediaPlaybackSelection: Sendable {
    let media: Media
    let episode: Episode?
    var key: String { media.identity + "|" + (episode?.routingKey ?? "movie") }
}

enum AnimeOneOffPresentation {
    static func isOneOff(_ media: Media, knownAnime: Bool = false, declaredEpisodes: Int? = nil) -> Bool {
        guard knownAnime || AnimeLibraryDetection.hasDirectEvidence(media) else { return false }
        if media.type == "movie" { return true }
        if let declaredEpisodes, declaredEpisodes > 1 { return false }
        let count = media.videos?.count ?? 0
        return count == 1 || (count == 0 && declaredEpisodes == 1)
    }
    static func playbackEpisode(_ media: Media) -> Episode? {
        guard let episode = media.videos?.first, episode.id.split(separator: ":").count >= 3 else { return nil }
        return episode
    }
}
