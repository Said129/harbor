import Foundation

enum TraktScrobbleAction: String, Codable, Equatable, Sendable { case start, pause, stop }

struct TraktWatchIdentity: Codable, Equatable, Sendable {
    let mediaID: String
    var episode: Episode?
    var key: String { "\(mediaID)|\(episode?.season.map(String.init) ?? "")|\(episode?.episode.map(String.init) ?? "")" }
    var valid: Bool {
        !mediaID.isEmpty && mediaID.utf8.count <= 1_024
            && (episode.map { ($0.season ?? -1) >= 0 && ($0.episode ?? 0) > 0 && $0.id.utf8.count <= 2_048 } ?? true)
    }
    var sanitized: Self {
        var copy = self
        if let episode {
            copy.episode = Episode(id: episode.id, season: episode.season, episode: episode.episode, imdbID: episode.imdbID,
                imdbSeason: episode.imdbSeason, imdbEpisode: episode.imdbEpisode, tvdbEpisodeID: episode.tvdbEpisodeID)
        }
        return copy
    }
    init(mediaID: String, episode: Episode? = nil) { self.mediaID = mediaID; self.episode = episode }
    init(session: PlaybackSession, media: Media?) {
        mediaID = session.target.id
        episode = media?.videos?.first { $0.belongs(to: session.target) }
        if episode == nil, let season = session.target.season, let number = session.target.episode {
            episode = Episode(id: session.target.videoId ?? "\(mediaID):\(season):\(number)", season: season, episode: number)
        }
    }
}

struct TraktWatchTarget: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable { case movie, show, episode }
    let kind: Kind
    let ids: TrackerShowIDs
    var season: Int?
    var number: Int?
    var episodeIDs: TrackerShowIDs?
    var resolvable: Bool { kind == .episode && (episodeIDs?.json.objectValue.isEmpty ?? true) }
    init(kind: Kind, ids: TrackerShowIDs, season: Int? = nil, number: Int? = nil, episodeIDs: TrackerShowIDs? = nil) {
        self.kind = kind; self.ids = ids; self.season = season; self.number = number; self.episodeIDs = episodeIDs
    }
    init(_ resolved: TrackerResolvedEpisode) { self.init(kind: .episode, ids: resolved.showIds, season: resolved.season, number: resolved.number) }
    static func resolve(_ identity: TraktWatchIdentity) -> Self? {
        guard identity.valid else { return nil }
        let parts = identity.mediaID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        func ids(_ name: String, _ value: JSONValue) -> TrackerShowIDs { .init(.object([name: value])) }
        func episode(_ ids: TrackerShowIDs, _ season: Int?, _ number: Int?) -> Self? {
            guard let season, season >= 0, let number, number > 0 else { return nil }
            return .init(kind: .episode, ids: ids, season: season, number: number)
        }
        if ["mal", "kitsu"].contains(parts.first ?? "") {
            guard let ref = identity.episode else { return nil }
            let imdb = ref.imdbID.flatMap { $0.range(of: "^tt[0-9]+$", options: .regularExpression) != nil ? $0 : nil }
            let show = imdb.map { ids("imdb", .string($0)) } ?? .init(.object([:]))
            if let tvdb = ref.tvdbEpisodeID, tvdb > 0 {
                var season = ref.season, number = ref.episode
                if let mapped = ref.imdbSeason { season = mapped }
                if let mapped = ref.imdbEpisode { number = mapped }
                return .init(kind: .episode, ids: show, season: season, number: number, episodeIDs: ids("tvdb", .integer(Int64(tvdb))))
            }
            guard imdb != nil else { return nil }
            return episode(show, ref.imdbSeason, ref.imdbEpisode)
        }
        if let first = parts.first, first.range(of: "^tt[0-9]+$", options: .regularExpression) != nil {
            let show = ids("imdb", .string(first))
            if parts.count >= 3 { return episode(show, Int(parts[1]), Int(parts[2])) }
            if let ref = identity.episode { return episode(show, ref.season, ref.episode) }
            return .init(kind: .movie, ids: show)
        }
        guard parts.count >= 3, parts[0] == "tmdb", let id = Int64(parts[2]), id > 0 else { return nil }
        let target = ids("tmdb", .integer(id))
        if parts[1] == "movie" { return .init(kind: .movie, ids: target) }
        guard parts[1] == "tv" else { return nil }
        if parts.count >= 5, let found = episode(target, Int(parts[3]), Int(parts[4])) { return found }
        if let ref = identity.episode { return episode(target, ref.season, ref.episode) }
        return .init(kind: .show, ids: target)
    }
    var json: JSONValue {
        if kind != .episode { return .object(["kind": .string(kind.rawValue), "ids": ids.json]) }
        var fields: [String: JSONValue] = ["kind": .string("episode"), "show": .object(["ids": ids.json])]
        if let season { fields["season"] = .integer(Int64(season)) }; if let number { fields["number"] = .integer(Int64(number)) }
        if let episodeIDs { fields["episodeIds"] = episodeIDs.json }; return .object(fields)
    }
    func scrobbleBody(_ progress: Double) -> JSONValue? {
        guard progress.isFinite else { return nil }
        var body: [String: JSONValue] = ["progress": .number(Self.roundedProgress(progress))]
        if kind != .episode { body[kind.rawValue] = .object(["ids": ids.json]); return .object(body) }
        if let episodeIDs, !episodeIDs.json.objectValue.isEmpty {
            body["episode"] = .object(["ids": episodeIDs.json])
            if !ids.json.objectValue.isEmpty { body["show"] = .object(["ids": ids.json]) }
        } else {
            guard let season, let number else { return nil }
            body["show"] = .object(["ids": ids.json]); body["episode"] = .object(["season": .integer(Int64(season)), "number": .integer(Int64(number))])
        }
        return .object(body)
    }
    var historyBody: JSONValue? {
        switch kind {
        case .movie: return .object(["movies": .array([.object(["ids": ids.json])])])
        case .show: return nil
        case .episode:
            if let episodeIDs, !episodeIDs.json.objectValue.isEmpty { return .object(["episodes": .array([.object(["ids": episodeIDs.json])])]) }
            guard let season, let number else { return nil }
            return .object(["shows": .array([.object(["ids": ids.json, "seasons": .array([.object(["number": .integer(Int64(season)), "episodes": .array([.object(["number": .integer(Int64(number))])])])])])])])
        }
    }
    /// Number(value.toFixed(2)) rounds the exact binary fraction. Multiplying a
    /// Double by 100 first would turn values such as 2.675 into the wrong tie.
    static func roundedProgress(_ progress: Double) -> Double {
        guard progress.isFinite else { return 0 }
        let value = min(100, max(0, progress))
        guard value > 0 else { return 0 }
        let bits = value.bitPattern, exponent = Int((bits >> 52) & 0x7ff) - 1_023 - 52
        let numerator = ((bits & ((1 << 52) - 1)) | (1 << 52)) * 100
        let shift = -exponent
        guard shift > 0, shift < 64 else { return shift >= 64 ? 0 : value }
        let integral = numerator >> shift, remainder = numerator & ((UInt64(1) << shift) - 1)
        let rounded = integral + (remainder >= (UInt64(1) << (shift - 1)) ? 1 : 0)
        return Double(rounded) / 100
    }
}

enum TraktHistoryReceipt {
    static func confirms(_ value: JSONValue) -> Bool {
        ["added", "existing"].reduce(0) { sum, group in sum + (value[group]["movies"].integer ?? 0) + (value[group]["episodes"].integer ?? 0) } > 0
    }
}

enum TraktWatchEndpoint: Sendable {
    case scrobble(TraktScrobbleAction, JSONValue), history(JSONValue)
    var path: String { switch self { case .scrobble(let action, _): "/scrobble/" + action.rawValue; case .history: "/sync/history" } }
    var body: JSONValue { switch self { case .scrobble(_, let body), .history(let body): body } }
}

struct TraktPlaybackPolicy: Sendable {
    enum Status: String, Equatable, Sendable { case loading, playing, paused, ended }
    struct Event: Equatable, Sendable { let action: TraktScrobbleAction; let progress: Double }
    struct Delivery: Sendable { let identity: TraktWatchIdentity; let event: Event }
    private var identity: TraktWatchIdentity?
    private var last: TraktScrobbleAction?
    private var furthest = 0.0
    private var resetSeen = true
    private var seekPosition = 0.0, seekAt = 0.0, resyncedAt = 0.0
    private var position = 0.0, duration = 0.0
    private var renderedIdentity: TraktWatchIdentity?
    private var renderedStatus: Status?
    private var renderedDuration: Double?
    mutating func update(identity: TraktWatchIdentity, status: Status, position: Double, duration: Double, now: TimeInterval, isClockTick: Bool = false) -> [Delivery] {
        guard position.isFinite, duration.isFinite, now.isFinite else { return [] }
        var deliveries: [Delivery] = []
        if let previous = self.identity, previous.key != identity.key {
            if last != .stop, furthest > 0 { deliveries.append(.init(identity: previous, event: .init(action: furthest >= 90 ? .stop : .pause, progress: furthest >= 90 ? 100 : furthest))) }
            last = nil; furthest = 0; resetSeen = false; seekPosition = 0; seekAt = 0; resyncedAt = 0
            renderedIdentity = nil; renderedStatus = nil; renderedDuration = nil
        }
        self.identity = identity; self.position = position; self.duration = duration
        guard TraktWatchTarget.resolve(identity) != nil else { return deliveries }
        let render = !isClockTick || renderedIdentity != identity || renderedStatus != status || renderedDuration != duration
        if render {
            renderedIdentity = identity; renderedStatus = status; renderedDuration = duration
            if status == .ended {
                if duration >= 150, last == .start || last == .pause {
                    furthest = max(furthest, min(100, max(0, position / duration * 100)))
                    deliveries.append(.init(identity: identity, event: .init(action: .stop, progress: furthest))); last = .stop
                }
                return deliveries
            }
            if !resetSeen { if status == .loading || duration <= 0 { resetSeen = true }; return deliveries }
            guard duration >= 150 else { return deliveries }
            let progress = min(100, max(0, position / duration * 100)); furthest = max(furthest, progress)
            guard last != .stop else { return deliveries }
            if status == .playing, last != .start { last = .start; deliveries.append(.init(identity: identity, event: .init(action: .start, progress: progress))) }
            else if status == .paused, last == .start { last = .pause; deliveries.append(.init(identity: identity, event: .init(action: .pause, progress: progress))) }
        }
        guard resetSeen, duration >= 150 else { return deliveries }
        if last == .start, isClockTick {
            let progress = min(100, max(0, position / duration * 100)); furthest = max(furthest, progress)
            let delta = position - seekPosition, elapsed = now - seekAt
            let jumped = abs(delta) > 8 && (elapsed < 1.5 || abs(delta / max(0.001, elapsed)) > 4)
            seekPosition = position; seekAt = now
            if jumped, now - resyncedAt >= 30 {
                resyncedAt = now; deliveries.append(.init(identity: identity, event: .init(action: .start, progress: progress)))
            }
        } else if last != .start, render { seekPosition = position; seekAt = now; resyncedAt = 0 }
        return deliveries
    }
    mutating func finish(identity current: TraktWatchIdentity? = nil, position: Double? = nil, duration: Double? = nil) -> Delivery? {
        if let current, current.key == identity?.key, let position, let duration, position.isFinite, duration.isFinite {
            self.position = position; self.duration = duration
        }
        guard let identity, last == .start || last == .pause else { return nil }
        guard self.duration > 0 else { last = .pause; return nil }
        furthest = min(100, max(furthest, self.position / self.duration * 100))
        let action: TraktScrobbleAction = furthest >= 90 ? .stop : .pause; last = action
        return .init(identity: identity, event: .init(action: action, progress: action == .stop ? 100 : furthest))
    }
}
