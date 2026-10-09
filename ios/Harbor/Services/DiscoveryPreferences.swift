import Foundation
import Observation

/// Harbor's recommendation votes and 500-event taste history, isolated by account.
@MainActor @Observable
final class DiscoveryPreferences {
    enum Vote: String, Codable, Sendable { case up, down }
    enum Kind: String, Codable, Sendable {
        case open, play, dwell, watchlist, watched, voteUp, voteDown
        var weight: Double {
            switch self {
            case .open: 1
            case .play: 3
            case .dwell: 2.5
            case .watchlist: 4
            case .watched: 6
            case .voteUp: 5
            case .voteDown: -5
            }
        }
    }
    struct Snapshot: Codable, Sendable {
        let genres: [String]
        let decade: String?
        init(_ media: Media) {
            genres = Array((media.genres ?? []).prefix(40))
            decade = Int((media.releaseInfo ?? "").prefix(4)).map { "\($0 / 10 * 10)s" }
        }
        var valid: Bool { genres.count <= 40 && genres.allSatisfy { $0.utf8.count <= 128 } && (decade?.utf8.count ?? 0) <= 16 }
    }
    struct Entry: Codable, Equatable, Sendable {
        let vote: Vote
        let timestamp: Double
        let name: String
        let type: String
    }
    private struct Event: Codable, Sendable {
        let id: String
        let kind: Kind
        let timestamp: Double
        var snapshot: Snapshot
    }
    private struct Stored: Codable {
        var votes: [String: Entry] = [:]
        var events: [Event] = []
        var hintDismissed = false
        // Optional fields preserve stores written before Queue's skip actions existed.
        var queueSnoozed: [String: Double]?
        var queueBlocked: Set<String>?
        var valid: Bool {
            votes.count <= 1_000 && events.count <= 500
                && votes.allSatisfy { Self.validID($0.key) && $0.value.timestamp.isFinite && $0.value.timestamp >= 0 && $0.value.name.utf8.count <= 1_024 && $0.value.type.utf8.count <= 64 }
                && events.allSatisfy { Self.validID($0.id) && $0.timestamp.isFinite && $0.timestamp >= 0 && $0.snapshot.valid }
                && (queueSnoozed?.count ?? 0) <= 10_000 && (queueBlocked?.count ?? 0) <= 10_000
                && (queueSnoozed?.allSatisfy { Self.validID($0.key) && $0.value.isFinite && $0.value >= 0 } ?? true)
                && (queueBlocked?.allSatisfy(Self.validID) ?? true)
        }
        static func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 4_096 }
    }
    let owner: String
    private var stored = Stored()
    private(set) var ready = false
    private(set) var error: String?
    private(set) var revision = 0
    var votes: [String: Entry] { stored.votes }
    var hintDismissed: Bool { stored.hintDismissed }
    static func key(_ owner: String) -> String { "discovery-preferences-" + EBookShelf.hash(owner) }
    init(owner: String) { self.owner = owner; reload() }
    func reload() {
        ready = false
        do {
            let value = try KeychainStore().read(Self.key(owner), as: Stored.self) ?? Stored()
            guard value.valid else { throw HarborError(code: "discovery-store") }
            stored = value; ready = true; error = nil; revision &+= 1
        } catch { self.error = "No se pudieron recuperar las preferencias de recomendaciones. Los datos guardados se conservan." }
    }
    func vote(for media: Media) -> Vote? { stored.votes[media.id]?.vote }
    func isQueueItemHidden(_ id: String, now: Date = Date()) -> Bool {
        let key = Self.queueKey(id)
        return stored.queueBlocked?.contains(key) == true || (stored.queueSnoozed?[key] ?? 0) > now.timeIntervalSince1970 * 1_000
    }
    @discardableResult func snoozeQueueItem(_ id: String, now: Date = Date()) -> Bool {
        let key = Self.queueKey(id)
        let timestamp = now.timeIntervalSince1970 * 1_000
        guard ready, Stored.validID(key), timestamp.isFinite, timestamp >= 0 else { return false }
        var next = stored
        var snoozed = (next.queueSnoozed ?? [:]).filter { $0.value > timestamp }
        snoozed[key] = timestamp + 14 * 86_400_000
        next.queueSnoozed = snoozed
        return persist(next)
    }
    @discardableResult func blockQueueItem(_ id: String) -> Bool {
        let key = Self.queueKey(id)
        guard ready, Stored.validID(key) else { return false }
        var next = stored
        var blocked = next.queueBlocked ?? []
        blocked.insert(key)
        next.queueBlocked = blocked
        next.queueSnoozed?.removeValue(forKey: key)
        return persist(next)
    }
    private static func queueKey(_ id: String) -> String { id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    @discardableResult func toggle(_ vote: Vote, for media: Media, now: Date = Date()) -> Bool {
        guard ready, Stored.validID(media.id) else { return false }
        var next = stored
        if next.votes[media.id]?.vote == vote { next.votes.removeValue(forKey: media.id) }
        else {
            next.votes[media.id] = Entry(vote: vote, timestamp: now.timeIntervalSince1970 * 1_000, name: media.name, type: media.type)
            Self.append(vote == .up ? .voteUp : .voteDown, media: media, now: now, to: &next)
        }
        next.hintDismissed = true
        return persist(next)
    }
    func dismissHint() { guard ready else { return }; var next = stored; next.hintDismissed = true; _ = persist(next) }
    @discardableResult func restoreVote(for id: String, expected: Entry?, previous: Entry?) -> Bool {
        guard ready, Stored.validID(id), stored.votes[id] == expected else { return false }
        var next = stored
        next.votes[id] = previous
        return persist(next)
    }
    func track(_ kind: Kind, media: Media, now: Date = Date()) {
        guard ready, Stored.validID(media.id) else { return }
        var next = stored; Self.append(kind, media: media, now: now, to: &next); _ = persist(next)
    }
    private static func append(_ kind: Kind, media: Media, now: Date, to value: inout Stored) {
        let timestamp = now.timeIntervalSince1970 * 1_000
        if let last = value.events.last, last.id == media.id, last.kind == kind, timestamp >= last.timestamp, timestamp - last.timestamp < 90_000 {
            value.events[value.events.count - 1].snapshot = Snapshot(media)
        } else {
            value.events.append(Event(id: media.id, kind: kind, timestamp: timestamp, snapshot: Snapshot(media)))
            value.events = Array(value.events.suffix(500))
        }
    }
    private func persist(_ value: Stored) -> Bool {
        do {
            guard value.valid, try JSONEncoder().encode(value).count <= 1_024 * 1_024 else { throw HarborError(code: "discovery-store") }
            try KeychainStore().write(value, key: Self.key(owner))
            stored = value; error = nil; revision &+= 1; return true
        } catch { self.error = "No se pudo guardar esta preferencia. Los datos anteriores se conservan."; return false }
    }
    struct Affinity {
        var genres: [String: Double] = [:]
        var decades: [String: Double] = [:]
        func score(_ media: Media) -> Double {
            let profile = Snapshot(media)
            let genre = profile.genres.isEmpty ? 0 : profile.genres.reduce(0) { $0 + (genres[$1] ?? 0) } / sqrt(Double(profile.genres.count))
            return 0.8 * genre + 0.4 * (profile.decade.flatMap { decades[$0] } ?? 0)
        }
    }
    func affinity(now: Date) -> Affinity {
        var result = Affinity()
        let timestamp = now.timeIntervalSince1970 * 1_000
        for event in stored.events {
            let weight = event.kind.weight * exp(-log(2) * max(0, timestamp - event.timestamp) / (90 * 86_400_000))
            for genre in event.snapshot.genres where !genre.isEmpty { result.genres[genre, default: 0] += weight }
            if let decade = event.snapshot.decade { result.decades[decade, default: 0] += weight }
        }
        return result
    }
    func excludes(_ media: Media, now: Date) -> Bool {
        if let entry = stored.votes[media.id] {
            if entry.vote == .down { return true }
            if now.timeIntervalSince1970 * 1_000 - entry.timestamp < 7 * 86_400_000 { return true }
        }
        let name = Self.titleKey(media.name)
        return !name.isEmpty && stored.votes.values.contains { $0.vote == .down && Self.titleKey($0.name) == name }
    }
    static func titleKey(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "\\([0-9]{4}\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}

/// The original Featured scoring and genre diversification for available native lanes.
enum FeaturedRanking {
    enum Source: Equatable { case seed, trending, tmdb, awards }
    struct Candidate {
        let media: Media
        let source: Source
        let rank: Int
        var priority: Int { switch source { case .tmdb: 3; case .trending: 4; case .awards: 6; case .seed: 7 } }
        var confidence: Double { switch source { case .tmdb: 10; case .awards: 12; case .trending: 6; case .seed: 5 } }
        var prominence: Double { switch source { case .tmdb: 0.9; case .trending: 0.95; case .awards: 0.85; case .seed: 0.7 } }
    }
    private struct Scored {
        let index: Int
        let media: Media
        let value: Double
    }
    @MainActor static func select(_ candidates: [Candidate], preferences: DiscoveryPreferences, excluded: [Media], count: Int = 10, now: Date = Date()) -> [Media] {
        let ids = Set(excluded.map(\.id))
        let titles = Set(excluded.map { DiscoveryPreferences.titleKey($0.name) }.filter { !$0.isEmpty })
        var unique: [String: Candidate] = [:]
        var order: [String] = []
        for item in candidates {
            let media = item.media
            guard ["movie", "series"].contains(media.type), media.background != nil || media.fallbackBackground != nil,
                  !ids.contains(media.id), !titles.contains(DiscoveryPreferences.titleKey(media.name)), !preferences.excludes(media, now: now) else { continue }
            if item.source != .awards, let rating = media.imdbRating.flatMap(Double.init), rating < 6.8 { continue }
            if let previous = unique[media.id] { if item.priority < previous.priority { unique[media.id] = item } }
            else { unique[media.id] = item; order.append(media.id) }
        }
        let affinity = preferences.affinity(now: now)
        var scored: [Scored] = []
        for (index, id) in order.enumerated() {
            guard let item = unique[id] else { continue }
            let value = score(item, preferences: preferences, affinity: affinity, now: now)
            scored.append(Scored(index: index, media: item.media, value: value))
        }
        scored.sort { left, right in left.value == right.value ? left.index < right.index : left.value > right.value }
        var ranked: [Media] = scored.map(\.media)
        var result: [Media] = []
        while result.count < count && !ranked.isEmpty {
            var next = 0
            let tail = Array(result.suffix(3)); let genre = tail.first?.genres?.first ?? "_"
            if tail.count == 3, tail.allSatisfy({ ($0.genres?.first ?? "_") == genre }), let alternative = ranked.firstIndex(where: { ($0.genres?.first ?? "_") != genre }) { next = alternative }
            result.append(ranked.remove(at: next))
        }
        return result
    }
    @MainActor private static func score(_ item: Candidate, preferences: DiscoveryPreferences, affinity: DiscoveryPreferences.Affinity, now: Date) -> Double {
        let rating = (item.media.imdbRating.flatMap(Double.init) ?? 0) / 10
        let quality = rating > 0 ? (rating * item.confidence + 0.62 * 8) / (item.confidence + 8) : 0.5
        let taste = min(1, affinity.score(item.media) / 4)
        let vote = preferences.votes[item.media.id]
        var suppression: Double = 0
        if let vote, vote.vote == .up {
            let elapsed: Double = now.timeIntervalSince1970 * 1_000 - vote.timestamp
            let decay: Double = -log(2.0) * elapsed / (12.0 * 86_400_000.0)
            suppression = 6.0 * exp(decay)
        }
        let day = UInt32(truncatingIfNeeded: Int64(floor(now.timeIntervalSince1970 / 86_400)))
        return 6 * taste + 2 * quality + 1.2 * item.prominence / Double(1 + item.rank) - suppression + jitter(item.media.id, day: day) * 0.2
    }
    private static func jitter(_ id: String, day: UInt32) -> Double {
        var hash: UInt32 = 2_166_136_261
        for character in id.utf16 { hash = (hash ^ UInt32(character)) &* 16_777_619 }
        let seed = (hash &* 2_654_435_761) &+ day &+ 0x6d2b79f5
        var value = (seed ^ (seed >> 15)) &* (seed | 1)
        value ^= value &+ ((value ^ (value >> 7)) &* (value | 61))
        return Double(value ^ (value >> 14)) / 4_294_967_296
    }
}
