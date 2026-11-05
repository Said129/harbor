import Foundation

/// What Desktop's AniList sync (`lib/anilist/sync.ts`) reports, shown as its sync toast.
enum AniListSyncEvent: Equatable, Sendable {
    enum Failure: String, Sendable { case updateNotConfirmed = "update-not-confirmed", unreachable }
    case syncing(title: String, episode: Int)
    case ok(title: String, episode: Int)
    case watching(title: String)
    case error(title: String, reason: Failure)
}

/// The anime entry a playing episode counts toward (`lib/tracker-progress.ts`).
struct AniListTrackerTarget: Equatable, Sendable {
    let id: String
    let episode: Int?
}

enum AniListTracking {
    /// `kitsu:N`, `mal:N` or `anilist:N`: an entry, not a season of a series.
    static func entryID(_ id: String?) -> String? {
        guard let id else { return nil }
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, ["kitsu", "mal", "anilist"].contains(String(parts[0])), isNumber(parts[1]) else { return nil }
        return id
    }

    /// AniList counts episodes within the entry. A `kitsu:N:M` stream id binds episode M to entry N explicitly;
    /// an absolute number or an IMDb episode alone carries no such ownership evidence.
    static func target(metaID: String, sourceID: String? = nil, videoID: String?, fallbackEpisode: Int?) -> AniListTrackerTarget? {
        var stream: (entry: String, number: Int)?
        let parts = (videoID ?? "").split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 3, parts[0] == "kitsu", isNumber(parts[1]), isNumber(parts[2]), let number = Int(parts[2]) {
            stream = ("kitsu:" + String(parts[1]), number)
        }
        guard let id = entryID(sourceID) ?? stream?.entry ?? entryID(metaID) else { return nil }
        if let stream, id == stream.entry { return AniListTrackerTarget(id: id, episode: stream.number) }
        return AniListTrackerTarget(id: id, episode: fallbackEpisode)
    }

    private static func isNumber(_ text: Substring) -> Bool { !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber } }

    /// Desktop's autosave rules: nothing before 90 seconds, "watching" until 70 % (or the end), then the episode count.
    enum Phase: Equatable, Sendable { case none, watching, progress }
    static let minimumSeconds = 90.0
    static let progressRatio = 0.7
    static func phase(position: Double, duration: Double, ended: Bool) -> Phase {
        guard position.isFinite, position >= minimumSeconds else { return .none }
        if ended || (duration.isFinite && duration > 0 && position / duration >= progressRatio) { return .progress }
        return .watching
    }
}

/// What to do with the user's list entry once a watched episode number is known.
enum AniListSyncPlan: Equatable, Sendable {
    case skip
    /// The list is already at or past the episode: remember that and write nothing.
    case remember(Int)
    case save(progress: Int, status: String)

    /// Forward only; an entry the user moved to Completed or Re-watching is left alone, and the last
    /// episode of a known length completes the entry.
    static func progress(status: String?, current: Int, total: Int, target: Int) -> AniListSyncPlan {
        if status == "COMPLETED" || status == "REPEATING" { return .skip }
        if total > 0 && target > total { return .skip }
        if target <= current { return .remember(current) }
        return .save(progress: target, status: total > 0 && target >= total ? "COMPLETED" : "CURRENT")
    }

    /// Starting an episode moves a Planning entry to Current; nothing else changes.
    static func marksWatching(hasEntry: Bool, status: String?, progress: Int, total: Int) -> Bool {
        guard hasEntry else { return true }
        if status != "PLANNING" { return false }
        return !(total > 0 && progress >= total)
    }
}

/// Desktop's `markAnimeWatching` and `syncAnimeProgress`.
actor AniListSync {
    private struct Entry { let episodes: Int; let hasEntry: Bool; let status: String?; let progress: Int }
    private static let sentLifetime: TimeInterval = 60

    private let client: AniListClient
    private let token: String
    private let owned: @MainActor @Sendable () -> Bool
    private let kitsuToAniList: @Sendable (Int) async -> Int?
    private let authenticationFailed: @MainActor @Sendable () async -> Void
    private let emit: @MainActor @Sendable (AniListSyncEvent) -> Void
    private let now: @Sendable () -> Date
    private var sent: [String: (progress: Int, at: Date)] = [:]
    private var inflight: Set<String> = []
    private var watchingMarked: Set<String> = []

    init(client: AniListClient, token: String, owned: @escaping @MainActor @Sendable () -> Bool = { true },
         kitsuToAniList: @escaping @Sendable (Int) async -> Int?, authenticationFailed: @escaping @MainActor @Sendable () async -> Void = { },
         emit: @escaping @MainActor @Sendable (AniListSyncEvent) -> Void = { _ in }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.token = token; self.owned = owned; self.kitsuToAniList = kitsuToAniList
        self.authenticationFailed = authenticationFailed; self.emit = emit; self.now = now
    }

    static func leadingInt(_ text: String) -> Int? {
        guard let first = text.split(separator: ":", omittingEmptySubsequences: false).first, !first.isEmpty,
              first.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(first), value > 0 else { return nil }
        return value
    }

    /// An AniList media id for `anilist:`, `kitsu:` and `mal:` ids; nil for anything else or when the lookup fails.
    func mediaID(for harborID: String) async -> Int? {
        if harborID.hasPrefix("anilist:") { return Self.leadingInt(String(harborID.dropFirst(8))) }
        if harborID.hasPrefix("kitsu:") {
            guard let kitsu = Self.leadingInt(String(harborID.dropFirst(6))) else { return nil }
            return await kitsuToAniList(kitsu)
        }
        if harborID.hasPrefix("mal:") {
            guard let mal = Self.leadingInt(String(harborID.dropFirst(4))),
                  let data = try? await client.request("query ($idMal: Int) { Media(idMal: $idMal, type: ANIME) { id } }",
                                                       variables: ["idMal": .integer(Int64(mal))], token: token) else { return nil }
            return data["Media"]["id"].integer
        }
        return nil
    }

    private func entry(_ mediaID: Int) async throws -> Entry? {
        let data = try await client.request("""
            query ($id: Int) {
              Media(id: $id, type: ANIME) {
                id
                episodes
                mediaListEntry { id progress status }
              }
            }
            """, variables: ["id": .integer(Int64(mediaID))], token: token)
        guard case .object = data["Media"] else { return nil }
        let listed = data["Media"]["mediaListEntry"]
        let hasEntry: Bool
        if case .object = listed { hasEntry = true } else { hasEntry = false }
        return Entry(episodes: data["Media"]["episodes"].integer ?? 0, hasEntry: hasEntry, status: listed["status"].string, progress: listed["progress"].integer ?? 0)
    }

    private func handle(_ error: Error, title: String) async {
        if let failure = error as? AniListAPIError, failure.status == 401 || failure.isAuthenticationError { await authenticationFailed(); return }
        await emit(.error(title: title, reason: .unreachable))
    }

    /// Moves a Planning entry to Current when playback of one of its episodes is under way. Once per id.
    func markWatching(_ harborID: String, title: String) async {
        guard !watchingMarked.contains(harborID) else { return }
        watchingMarked.insert(harborID)
        do {
            guard let media = await mediaID(for: harborID), await owned() else { watchingMarked.remove(harborID); return }
            let current = try await entry(media)
            guard await owned() else { return }
            guard AniListSyncPlan.marksWatching(hasEntry: current?.hasEntry ?? false, status: current?.status, progress: current?.progress ?? 0, total: current?.episodes ?? 0) else { return }
            _ = try await client.request("""
                mutation ($mediaId: Int, $status: MediaListStatus) {
                  SaveMediaListEntry(mediaId: $mediaId, status: $status) {
                    id
                    status
                  }
                }
                """, variables: ["mediaId": .integer(Int64(media)), "status": .string("CURRENT")], token: token)
            if await owned() { await emit(.watching(title: title)) }
        } catch {
            watchingMarked.remove(harborID)
            if let failure = error as? AniListAPIError, failure.status == 401 || failure.isAuthenticationError { await authenticationFailed() }
        }
    }

    /// Writes an episode count forward. Returns whether the attempt is settled (written, already there, or
    /// nothing to write) rather than worth retrying later.
    @discardableResult
    func syncProgress(_ harborID: String, episode: Int?, title: String, season: Int? = nil) async -> Bool {
        let episodeNumber = episode ?? 1
        guard episodeNumber >= 1 else { return true }
        let key = "\(harborID)|\(season.map(String.init) ?? "")|\(episodeNumber)"
        if let previous = sent[key], now().timeIntervalSince(previous.at) < Self.sentLifetime, previous.progress >= episodeNumber { return true }
        guard !inflight.contains(key) else { return false }
        inflight.insert(key)
        defer { inflight.remove(key) }
        do {
            guard let media = await mediaID(for: harborID), await owned() else { return false }
            let found = try await entry(media)
            guard await owned() else { return false }
            guard let current = found else { return true }
            switch AniListSyncPlan.progress(status: current.status, current: current.progress, total: current.episodes, target: episodeNumber) {
            case .skip: return true
            case .remember(let progress):
                sent[key] = (max(sent[key]?.progress ?? 0, progress), now())
                return true
            case .save(let progress, let status):
                await emit(.syncing(title: title, episode: progress))
                let saved = try await client.request("""
                    mutation ($mediaId: Int, $progress: Int, $status: MediaListStatus) {
                      SaveMediaListEntry(mediaId: $mediaId, progress: $progress, status: $status) {
                        id
                        progress
                        status
                      }
                    }
                    """, variables: ["mediaId": .integer(Int64(media)), "progress": .integer(Int64(progress)), "status": .string(status)], token: token)
                guard await owned() else { return false }
                if saved["SaveMediaListEntry"]["progress"].integer == progress {
                    sent[key] = (progress, now())
                    await emit(.ok(title: title, episode: progress))
                    return true
                }
                // An unconfirmed write stays retryable: recording it as sent would suppress the retry.
                await emit(.error(title: title, reason: .updateNotConfirmed))
                return false
            }
        } catch {
            guard await owned() else { return false }
            await handle(error, title: title)
            return false
        }
    }
}
