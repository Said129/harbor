import Foundation

/// Desktop's `useAnilistWatched` and `useMalWatched` read the open title's list entry without a lists screen, and
/// `watched-map.ts` keeps the whole list for 120 seconds. This keeps `TrackerListProgressStore` filled from the same
/// list requests the lists screens make, on launch, when the app becomes active and when a title opens.
enum TrackerListProgressRefresh {
    /// Desktop's `watched-map.ts` cache lifetime.
    static let lifetime: TimeInterval = 120

    /// Whether a load that finished at `last` is still fresh at `now`.
    static func isFresh(last: Date?, now: Date) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last) < lifetime
    }

    /// The kitsu number of a `kitsu:N` Harbor id, or nil for any other id.
    static func kitsuNumber(_ harborID: String) -> Int? {
        guard harborID.hasPrefix("kitsu:") else { return nil }
        let text = String(harborID.dropFirst(6))
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), value > 0 else { return nil }
        return value
    }

    /// A kitsu title has no list key of its own. Its AniList entry (or, when AniList has none, its MyAnimeList entry)
    /// is copied under the `kitsu:N` id, so `TrackerListWatched.keys` finds it.
    static func aliasEntries(_ entries: [String: TrackerListWatched.Progress], kitsu: Int, anilistID: Int?, malID: Int?) -> [String: TrackerListWatched.Progress] {
        if let anilistID, let progress = entries["anilist:\(anilistID)"] { return ["kitsu:\(kitsu)": progress] }
        if let malID, let progress = entries["mal:\(malID)"] { return ["kitsu:\(kitsu)": progress] }
        return [:]
    }
}

/// The network half of `TrackerListProgressRefresh`: the same list calls as `AniListListsView` and `MyAnimeListListsView`.
@MainActor enum TrackerListProgressLoader {
    private static var lastLoaded: [String: Date] = [:]

    /// Reloads both lists for one profile unless the last load is still fresh. A failed load leaves the store as it was.
    static func refresh(owner: String, now: Date = Date()) async {
        guard !TrackerListProgressRefresh.isFresh(last: lastLoaded[owner], now: now) else { return }
        lastLoaded[owner] = now
        await refreshAniList(owner: owner)
        await refreshMyAnimeList(owner: owner)
    }

    /// Opening a title: refreshes the lists when they are stale, then copies a kitsu title's entry under its kitsu id.
    static func prepare(harborID: String, owner: String) async {
        await refresh(owner: owner)
        guard let kitsu = TrackerListProgressRefresh.kitsuNumber(harborID) else { return }
        let anilistID = await AnimeFranchiseService.shared.anilistMediaID(kitsu: kitsu)
        let malID = await AnimeFranchiseService.shared.malMediaID(kitsu: kitsu)
        let store = TrackerListProgressStore.forOwner(owner)
        store.replace(TrackerListProgressRefresh.aliasEntries(store.entries, kitsu: kitsu, anilistID: anilistID, malID: malID))
    }

    static func refreshAniList(owner: String) async {
        let account = AniListAccount.forOwner(owner)
        if !account.ready { try? account.load() }
        guard let session = account.session, session.isActive() else { return }
        let client = AniListClient(transport: AniListHTTPTransport())
        do {
            let entries = try await AniListListsService.collection(userID: session.userId, token: session.accessToken, client: client)
            TrackerListProgressStore.forOwner(owner).replace(TrackerListWatched.aniListProgress(entries))
        } catch {
            if let apiError = error as? AniListAPIError, apiError.isAuthenticationError { await account.validate() }
        }
    }

    static func refreshMyAnimeList(owner: String) async {
        let account = MALAccount.forOwner(owner)
        if !account.ready { try? account.load() }
        guard let session = account.session else { return }
        var token = session.accessToken
        if !session.isActive(), let renewed = await account.refresh() { token = renewed }
        do {
            let client = MALClient(transport: MALHTTPTransport())
            let entries = try await MALListsService.fetchAll(token: token, client: client, refresh: { await account.refresh() })
            TrackerListProgressStore.forOwner(owner).replace(TrackerListWatched.malProgress(entries))
        } catch {
            return
        }
    }
}
