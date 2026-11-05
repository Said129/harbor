import Foundation

/// MyAnimeList ids for the other anime ids Harbor knows (Desktop's `lib/mal/mutations.ts` and `anime-mapping.ts`).
enum MALMapping {
    static func malID(anilist: Int) async -> Int? {
        if let mapped = await AnimeFranchiseService.shared.malMediaID(anilist: anilist) { return mapped }
        // ARM and AniZip miss some newer entries while AniList itself carries `idMal`.
        let data = try? await AniListClient(transport: AniListHTTPTransport())
            .request("query ($id: Int) { Media(id: $id, type: ANIME) { idMal } }", variables: ["id": .integer(Int64(anilist))], token: nil)
        return data?["Media"]["idMal"].integer
    }

    static func malID(kitsu: Int) async -> Int? {
        if let mapped = await AnimeFranchiseService.shared.malMediaID(kitsu: kitsu) { return mapped }
        guard let anilist = await AnimeFranchiseService.shared.anilistMediaID(kitsu: kitsu) else { return nil }
        return await malID(anilist: anilist)
    }
}

/// Desktop's `markMalWatching` and `syncMalProgress` (`lib/mal/sync.ts`).
actor MALSync {
    private struct Entry { let episodes: Int; let hasEntry: Bool; let status: String?; let watched: Int; let rewatching: Bool }
    private static let sentLifetime: TimeInterval = 60

    private let client: MALClient
    private var token: String
    private let refresh: @MainActor @Sendable () async -> String?
    private let owned: @MainActor @Sendable () -> Bool
    private let anilistToMAL: @Sendable (Int) async -> Int?
    private let kitsuToMAL: @Sendable (Int) async -> Int?
    private let emit: @MainActor @Sendable (AniListSyncEvent) -> Void
    private let now: @Sendable () -> Date
    private var sent: [String: (progress: Int, at: Date)] = [:]
    private var inflight: Set<String> = []
    private var watchingMarked: Set<String> = []

    init(client: MALClient, token: String, refresh: @escaping @MainActor @Sendable () async -> String? = { nil },
         owned: @escaping @MainActor @Sendable () -> Bool = { true },
         anilistToMAL: @escaping @Sendable (Int) async -> Int?, kitsuToMAL: @escaping @Sendable (Int) async -> Int?,
         emit: @escaping @MainActor @Sendable (AniListSyncEvent) -> Void = { _ in }, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client; self.token = token; self.refresh = refresh; self.owned = owned
        self.anilistToMAL = anilistToMAL; self.kitsuToMAL = kitsuToMAL; self.emit = emit; self.now = now
    }

    /// One request; after a 401 the token is refreshed once and the request repeated, as Desktop's client does.
    private func call(_ path: String, method: String = "GET", form: [(String, String)] = []) async throws -> JSONValue {
        do { return try await client.request(path, method: method, form: form, token: token) }
        catch let error as MALAPIError where error.status == 401 {
            guard let renewed = await refresh() else { throw error }
            token = renewed
            return try await client.request(path, method: method, form: form, token: token)
        }
    }

    /// A MyAnimeList id for `mal:`, `anilist:` and `kitsu:` ids; nil for anything else or when the lookup fails.
    func mediaID(for harborID: String) async -> Int? {
        if harborID.hasPrefix("mal:") { return AniListSync.leadingInt(String(harborID.dropFirst(4))) }
        if harborID.hasPrefix("anilist:") {
            guard let id = AniListSync.leadingInt(String(harborID.dropFirst(8))) else { return nil }
            return await anilistToMAL(id)
        }
        if harborID.hasPrefix("kitsu:") {
            guard let id = AniListSync.leadingInt(String(harborID.dropFirst(6))) else { return nil }
            return await kitsuToMAL(id)
        }
        return nil
    }

    private func entry(_ malID: Int) async throws -> Entry {
        let data = try await call("/anime/\(malID)?fields=num_episodes,my_list_status")
        let listed = data["my_list_status"]
        let hasEntry: Bool
        if case .object = listed { hasEntry = true } else { hasEntry = false }
        return Entry(episodes: data["num_episodes"].integer ?? 0, hasEntry: hasEntry, status: listed["status"].string,
                     watched: listed["num_episodes_watched"].integer ?? 0, rewatching: listed["is_rewatching"] == .bool(true))
    }

    private func isUnauthorized(_ error: Error) -> Bool { (error as? MALAPIError)?.status == 401 }

    /// Moves a Plan to watch entry to Watching when playback of one of its episodes is under way. Once per id.
    func markWatching(_ harborID: String, title: String) async {
        guard !watchingMarked.contains(harborID) else { return }
        watchingMarked.insert(harborID)
        do {
            guard let malID = await mediaID(for: harborID), await owned() else { watchingMarked.remove(harborID); return }
            let current = try await entry(malID)
            guard await owned() else { return }
            guard MALSyncPlan.marksWatching(hasEntry: current.hasEntry, status: current.status, watched: current.watched, total: current.episodes) else { return }
            _ = try await call("/anime/\(malID)/my_list_status", method: "PATCH", form: [("status", "watching")])
            if await owned() { await emit(.watching(title: title)) }
        } catch {
            watchingMarked.remove(harborID)
        }
    }

    /// Writes an episode count forward. Returns whether the attempt is settled rather than worth retrying later.
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
            guard let malID = await mediaID(for: harborID), await owned() else { return false }
            let current = try await entry(malID)
            guard await owned() else { return false }
            switch MALSyncPlan.progress(status: current.status, isRewatching: current.rewatching, current: current.watched, total: current.episodes, target: episodeNumber) {
            case .skip: return true
            case .remember(let watched):
                sent[key] = (max(sent[key]?.progress ?? 0, watched), now())
                return true
            case .save(let watched, let status):
                await emit(.syncing(title: title, episode: watched))
                let saved = try await call("/anime/\(malID)/my_list_status", method: "PATCH",
                                           form: [("num_watched_episodes", String(watched)), ("status", status)])
                guard await owned() else { return false }
                if saved["num_episodes_watched"].integer == watched {
                    sent[key] = (watched, now())
                    await emit(.ok(title: title, episode: watched))
                    return true
                }
                // An unconfirmed write stays retryable: recording it as sent would suppress the retry.
                await emit(.error(title: title, reason: .updateNotConfirmed))
                return false
            }
        } catch {
            guard await owned() else { return false }
            if !isUnauthorized(error) { await emit(.error(title: title, reason: .unreachable)) }
            return false
        }
    }
}
