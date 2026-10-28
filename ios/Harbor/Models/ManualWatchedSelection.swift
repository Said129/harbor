import Foundation

enum ManualWatchedSelection {
    struct Request: Sendable {
        let identity: TraktWatchIdentity
        let target: TraktWatchTarget
    }
    // Desktop's releasedEpisodes + airedOnly: specials are individual actions;
    // undated entries after the last aired episode are not bulk-marked early.
    static func releasedEpisodes(_ media: Media, now: Date = Date()) -> [Episode] {
        let ordered = (media.videos ?? []).filter { ($0.season ?? 0) >= 1 && ($0.episode ?? 0) > 0 }.sorted {
            $0.season == $1.season ? ($0.episode ?? 0) < ($1.episode ?? 0) : ($0.season ?? 0) < ($1.season ?? 0)
        }
        let dates = ordered.map(\.releaseDate)
        guard dates.contains(where: { $0 != nil }) else { return ordered }
        let boundary = dates.lastIndex { $0.map { $0 <= now } ?? false } ?? -1
        return ordered.enumerated().compactMap { index, episode in
            (dates[index].map { $0 <= now } ?? (index <= boundary)) ? episode : nil
        }
    }
    static func requests(_ media: Media, episodes: [Episode], wholeSeries: Bool) -> [Request] {
        let anime = ["kitsu:", "mal:", "anilist:", "anidb:"].contains { media.id.hasPrefix($0) }
        guard !(wholeSeries && anime) else { return [] }
        let explicit = media.imdbID.flatMap { TrackerShowIDs(.object(["imdb": .string($0)])).json["imdb"].string }
        if media.episodic {
            // Anime requires each episode's verified mapping, never the raw
            // absolute number paired with a metadata-level show identifier.
            let id = anime ? media.id : explicit ?? media.id
            return episodes.compactMap { episode in
                let identity = TraktWatchIdentity(mediaID: id, episode: episode)
                guard let target = TraktWatchTarget.resolve(identity), target.kind == .episode else { return nil }
                return Request(identity: identity, target: target)
            }
        }
        guard media.type == "movie" else { return [] }
        let identity = TraktWatchIdentity(mediaID: media.id)
        guard identity.valid else { return [] }
        let direct = TraktWatchTarget.resolve(identity)
        var fields: [String: JSONValue] = [:]
        if let direct, direct.kind == .movie { fields = direct.ids.json.objectValue }
        if let explicit { fields["imdb"] = .string(explicit) }
        let ids = TrackerShowIDs(.object(fields))
        guard !ids.json.objectValue.isEmpty else { return [] }
        return [.init(identity: identity, target: .init(kind: .movie, ids: ids))]
    }
}
