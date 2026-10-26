import Foundation

enum SimklScrobbleAction: String, Codable, Equatable, Sendable { case start, pause, stop }
struct SimklWatchIdentity: Codable, Equatable, Sendable {
    let mediaID: String
    var episode: Episode?
    var title: String?
    var year: Int?
    var imdb: String?
    var key: String { "\(mediaID)|\(episode?.season.map(String.init) ?? "")|\(episode?.episode.map(String.init) ?? "")" }
    var valid: Bool {
        !mediaID.isEmpty && mediaID.utf8.count <= 1_024 && (title?.utf8.count ?? 0) <= 1_024
            && (episode.map { $0.id.utf8.count <= 2_048 && ($0.season ?? -1) >= 0 && ($0.episode ?? 0) > 0 } ?? true)
    }
    var sanitized: Self {
        var copy = self
        if let episode {
            copy.episode = Episode(id: episode.id, season: episode.season, episode: episode.episode, imdbID: episode.imdbID,
                imdbSeason: episode.imdbSeason, imdbEpisode: episode.imdbEpisode, tvdbEpisodeID: episode.tvdbEpisodeID)
        }
        return copy
    }
    init(mediaID: String, episode: Episode? = nil, title: String? = nil, year: Int? = nil, imdb: String? = nil) {
        self.mediaID = mediaID; self.episode = episode; self.title = title; self.year = year; self.imdb = imdb
    }
    init(session: PlaybackSession, media: Media?) {
        mediaID = session.target.id
        let pool = media?.videos ?? []
        episode = pool.first { $0.belongs(to: session.target) }
        if episode == nil, let season = session.target.season, let number = session.target.episode {
            episode = Episode(id: session.target.videoId ?? "\(mediaID):\(season):\(number)", season: season, episode: number)
        }
        title = media?.name; year = media?.releaseInfo.flatMap { Int(String($0.prefix(4))) }; imdb = media?.imdbID
    }
    func scrobbleBody(progress: Double) -> JSONValue? {
        guard valid, progress.isFinite else { return nil }
        let progress = JSONValue.number(min(100, max(0, progress))), parts = mediaID.split(separator: ":").map(String.init)
        var ids: [String: JSONValue] = [:], bucket: String
        if let head = parts.first, head.range(of: "^tt[0-9]+$", options: .regularExpression) != nil {
            ids["imdb"] = .string(head); bucket = episode == nil ? "movie" : "show"
        } else if parts.count >= 3, parts[0] == "tmdb", ["movie", "tv"].contains(parts[1]), let number = Int64(parts[2]), number > 0 {
            guard parts[1] == "movie" || episode != nil else { return nil }
            ids["tmdb"] = .integer(number); bucket = parts[1] == "movie" ? "movie" : "show"
        } else if parts.count == 2, ["mal", "kitsu", "anilist", "anidb", "simkl"].contains(parts[0]), let number = Int64(parts[1]), number > 0 {
            ids[parts[0]] = .integer(number); bucket = episode == nil ? "movie" : "anime"
        } else { return nil }
        if let imdb = imdb ?? episode?.imdbID, imdb.range(of: "^tt[0-9]+$", options: .regularExpression) != nil, ids["imdb"] == nil { ids["imdb"] = .string(imdb) }
        var node: [String: JSONValue] = ["ids": .object(ids)]
        if let title, !title.isEmpty { node["title"] = .string(title) }; if let year { node["year"] = .integer(Int64(year)) }
        var body: [String: JSONValue] = ["progress": progress, bucket: .object(node)]
        if let episode, bucket != "movie", let number = episode.episode {
            body["episode"] = .object(["season": .integer(Int64(episode.season ?? 1)), "number": .integer(Int64(number))])
        }
        return .object(body)
    }
    func historyBody(now: Date = Date(), mapping: @Sendable (String) async throws -> JSONValue = { try await AnimeFranchiseService.shared.response(.mapping($0)) }) async throws -> JSONValue? {
        guard valid else { return nil }
        let watched = JSONValue.string(ISO8601DateFormatter().string(from: now))
        let media = Media(id: mediaID, type: episode == nil ? "movie" : "series", name: title ?? "")
        let animeEpisode = episode != nil && AnimeService.isAnime(mediaID)
        let target: SimklTarget?
        if animeEpisode, let imdb, imdb.range(of: "^tt[0-9]+$", options: .regularExpression) != nil {
            target = .init(kind: .show, ids: .init(.object(["imdb": .string(imdb)])))
        } else { target = try await SimklTarget.resolve(media, mapping: mapping) }
        guard let target else { return nil }
        if let episode, let number = animeEpisode ? episode.imdbEpisode ?? episode.episode : episode.episode {
            let row: JSONValue = .object(["number": .integer(Int64(number)), "watched_at": watched])
            let season = animeEpisode ? episode.imdbSeason ?? episode.season ?? 1 : episode.season ?? 1
            let seasonNode: JSONValue = .object(["number": .integer(Int64(season)), "episodes": .array([row])])
            return .object(["shows": .array([.object(["ids": target.ids.json, "seasons": .array([seasonNode])])])])
        }
        return .object(["movies": .array([.object(["ids": target.ids.json, "watched_at": watched])])])
    }
}

struct SimklPlaybackPolicy: Sendable {
    enum Status: Equatable, Sendable { case loading, playing, paused, ended }
    struct Event: Equatable, Sendable {
        let action: SimklScrobbleAction
        let progress: Double
        var recordWatched = false
    }
    private(set) var last: SimklScrobbleAction?
    private(set) var furthest = 0.0
    mutating func update(status: Status, position: Double, duration: Double) -> Event? {
        guard position.isFinite, duration.isFinite, duration >= 150 else { return nil }
        let progress = min(100, max(0, position / duration * 100)); furthest = max(furthest, progress)
        guard last != .stop else { return nil }
        if status == .ended {
            guard last == .start || last == .pause else { return nil }
            last = .stop; return .init(action: .stop, progress: furthest, recordWatched: furthest >= 90)
        }
        if status == .playing, last != .start { last = .start; return .init(action: .start, progress: progress) }
        if status == .paused, last == .start { last = .pause; return .init(action: .pause, progress: progress) }
        return nil
    }
    mutating func finish(position: Double, duration: Double) -> Event? {
        guard duration.isFinite, position.isFinite, duration >= 150, last == .start || last == .pause else { return nil }
        furthest = max(furthest, min(100, max(0, position / duration * 100)))
        let watched = furthest >= 90; last = watched ? .stop : .pause
        return .init(action: watched ? .stop : .pause, progress: watched ? 100 : furthest, recordWatched: watched)
    }
}
