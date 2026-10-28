import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    private var snapshot = LibrarySnapshot([]) { didSet { continuationRevision &+= 1 } }
    private var continuationRevision = 0
    @ObservationIgnored private var continuationCache: (library: Int, tracker: Int, trakt: Int, local: Int, trackerVisible: Bool, localVisible: Bool, sources: ContinueWatchingSources, records: [LibraryRecord])?
    private var traktWatchlist: TraktWatchlistSync?
    @ObservationIgnored private var watchlistCache: (library: Int, remote: Int, binding: UUID, projection: TraktWatchlistProjection)?
    private var records: [JSONValue] { snapshot.records }
    private let cache: LibraryCache
    private let service: any LibraryServing
    private let writeQueue: LibraryWriteQueue
    private var session: AccountSession?
    private var guestOwner = "guest"
    private(set) var personalOwner = "guest"
    private var generation = 0
    private var mutation = 0
    private var syncing = false
    private var writable = false
    private var presentationReady = false
    private(set) var presentation = LibraryPresentation()
    private var sharedPresentationError: String?
    private var privatePresentationError: String?
    private var privateDismissalScope: String?
    var presentationError: String? { privatePresentationError ?? sharedPresentationError }
    private(set) var favorites = MediaFavorites(owner: "guest")
    private(set) var discovery = DiscoveryPreferences(owner: "guest")
    let simklPlayback: SimklPlaybackFeed
    let traktPlayback: TraktPlaybackFeed
    let traktWatched: TraktWatchedFeed
    private let localContinue: LocalContinueStore
    private let privateDismissalStore: ContinueDismissalStore
    private var privateDismissals: [String: ContinueDismissal] = [:]
    private var privateDismissalsReady = false
    private(set) var continuingPrivate = false
    private(set) var playbackProgressStores: PlaybackProgressStores?
    private var localSnapshot = LocalContinueSnapshot()
    private var localRevision = 0
    private var localSharedOwner: String?
    private var localScope: String?
    private var localReady = false
    @ObservationIgnored private var localActive: @MainActor () -> Bool = { false }
    private(set) var continueSources = ContinueWatchingSources()
    init(simklPlayback: SimklPlaybackFeed? = nil, localContinue: LocalContinueStore = .shared, privateDismissals: ContinueDismissalStore? = nil, service: (any LibraryServing)? = nil, writeQueue: LibraryWriteQueue? = nil, traktPlayback: TraktPlaybackFeed? = nil, cache: LibraryCache? = nil, traktWatched: TraktWatchedFeed? = nil) {
        self.simklPlayback = simklPlayback ?? SimklPlaybackFeed(); self.localContinue = localContinue
        self.traktPlayback = traktPlayback ?? TraktPlaybackFeed()
        self.traktWatched = traktWatched ?? TraktWatchedFeed()
        self.cache = cache ?? LibraryCache()
        privateDismissalStore = privateDismissals ?? .shared
        let transport = service ?? LibraryService()
        self.service = transport; self.writeQueue = writeQueue ?? LibraryWriteQueue(service: transport)
    }
    var canChangePresentation: Bool { presentationReady }
    var bookmarksReady: Bool { writable }
    var canSaveBookmarks: Bool { writable && !busy }
    var hasCloudSession: Bool { session != nil }
    private var lastProgressWrite: [String: UInt64] = [:]
    var loading = false
    var busy = false
    var error: String?
    var owner: String { session?.user.id ?? guestOwner }
    var items: [LibraryRecord] { snapshot.items }
    var historyRevision: Int { continuationRevision }
    @discardableResult func removeHistory(_ record: LibraryRecord, owner expectedOwner: String, personalOwner expectedPersonalOwner: String) async -> Bool {
        guard owner == expectedOwner, personalOwner == expectedPersonalOwner,
              let saved = items.first(where: { $0.id == record.id }), LibraryHistoryEntry.eligible(saved), let media = saved.media else { return false }
        return await update(media) { fields in fields["removed"] = .bool(true); fields["temp"] = .bool(false) }
    }
    func bindTraktWatchlist(_ value: TraktWatchlistSync?) {
        if let value, value.account.owner != personalOwner { value.invalidate(); return }
        traktWatchlist?.invalidate(); traktWatchlist = value; watchlistCache = nil
    }
    private var watchlistProjection: TraktWatchlistProjection? {
        guard let binding = traktWatchlist, binding.isActive, binding.account.owner == personalOwner else { return nil }
        if let cached = watchlistCache, cached.library == continuationRevision, cached.remote == binding.store.revision, cached.binding == binding.id { return cached.projection }
        let projection = TraktWatchlistProjection(local: items, remote: binding.store.snapshot.watchlist, decisionKey: binding.decisionKey, fingerprint: binding.fingerprint)
        watchlistCache = (continuationRevision, binding.store.revision, binding.id, projection); return projection
    }
    var continuing: [LibraryRecord] {
        allContinuing.filter { dismissals[$0.id]?.hides($0) != true }
    }
    private var dismissals: [String: ContinueDismissal] { continuingPrivate ? privateDismissals : presentation.dismissed }
    private var allContinuing: [LibraryRecord] {
        guard !continuingPrivate || privateDismissalsReady else { return [] }
        let simkl = continueSources.simkl && !continuingPrivate ? simklPlayback.records(for: personalOwner) : []
        let trakt = continueSources.trakt && !continuingPrivate ? traktPlayback.records(for: personalOwner) : []
        let external = simkl + trakt
        let localVisible = localReady && localActive()
        let localRecords = continuingPrivate ? localSnapshot.personalRecords : localSnapshot.sharedRecords
        let local = localVisible ? localRecords.filter { $0.raw["nativeSource"] == .string("library") ? continueSources.library : continueSources.local } : []
        let base = continueSources.library && !continuingPrivate ? snapshot.continuing.filter { !CloudAnimeContinueImport.owns($0.id) || !localVisible } : []
        guard !external.isEmpty || !local.isEmpty else { return base }
        if let saved = continuationCache, saved.library == continuationRevision, saved.tracker == simklPlayback.revision,
           saved.trakt == traktPlayback.revision,
           saved.local == localRevision, saved.trackerVisible == !external.isEmpty, saved.localVisible == localVisible,
           saved.sources == continueSources { return saved.records }
        var seen = Set<String>()
        let merged = (base + external.filter(\.continuing) + local.filter(\.continuing))
            .sorted { $0.activityTimestamp == $1.activityTimestamp ? $0.id < $1.id : $0.activityTimestamp > $1.activityTimestamp }
            .filter { seen.insert($0.id).inserted }
        continuationCache = (continuationRevision, simklPlayback.revision, traktPlayback.revision, localRevision, !external.isEmpty, localVisible, continueSources, merged)
        return merged
    }
    func setContinueSources(_ value: ContinueWatchingSources) { if continueSources != value { continueSources = value } }
    func setContinuePrivacy(_ enabled: Bool, migratedScope: String? = nil) {
        continuingPrivate = enabled; continuationCache = nil
        privateDismissalsReady = false; privateDismissals = [:]; privatePresentationError = nil
        if let migratedScope { privateDismissalScope = migratedScope }
        guard enabled else { return }
        do {
            if let scope = privateDismissalScope { try privateDismissalStore.requireMigration(scope: scope) }
            privateDismissals = try privateDismissalStore.values(owner: personalOwner); privateDismissalsReady = true
        }
        catch { privatePresentationError = "No se pudo recuperar el historial privado. Los datos guardados se conservan."; Diagnostics.shared.recordFailure(error) }
    }
    func bindPlaybackProgress(_ stores: PlaybackProgressStores) {
        guard stores.personalOwner == personalOwner, stores.sharedOwner == localSharedOwner else { return }
        playbackProgressStores = stores
    }
    func bindLocalContinuing(sharedOwner: String, scope: String, active: @escaping @MainActor () -> Bool) async {
        localActive = active
        if localReady, localSharedOwner == sharedOwner, localScope == scope { return }
        localReady = false; localSnapshot = .init(); localRevision &+= 1; localSharedOwner = sharedOwner; localScope = scope
        let owner = personalOwner, ticket = generation
        do {
            let value = try await localContinue.snapshot(personalOwner: owner, sharedOwner: sharedOwner)
            guard generation == ticket, personalOwner == owner, localScope == scope, active() else { return }
            localSnapshot = value; localRevision &+= 1; localReady = true
            await absorbCloudAnimeHistory()
        } catch { Diagnostics.shared.recordFailure(error) }
    }
    func saveLocalProgress(_ media: Media, target: ResumeTarget, snapshot: ResumeSnapshot, source: LocalContinueSource, owner expectedOwner: String, personalOwner expectedPersonalOwner: String) async {
        guard expectedOwner == owner, expectedPersonalOwner == personalOwner, localReady, localActive(), let sharedOwner = localSharedOwner,
              let entry = LocalContinueEntry.playback(media, target: target, snapshot: snapshot, source: source) else { return }
        let ticket = generation, scope = localScope
        let lease: LocalContinueStore.Lease = { [weak self] in
            await self?.localCurrent(ticket, personalOwner: expectedPersonalOwner, sharedOwner: sharedOwner, scope: scope) ?? false
        }
        do {
            let value = try await localContinue.recordPlayback(entry, personalOwner: personalOwner, sharedOwner: sharedOwner, current: lease)
            guard localCurrent(ticket, personalOwner: expectedPersonalOwner, sharedOwner: sharedOwner, scope: scope) else { return }
            localSnapshot = value; localRevision &+= 1
        } catch is CancellationError { }
        catch { Diagnostics.shared.recordFailure(error) }
    }
    private func localCurrent(_ ticket: Int, personalOwner: String, sharedOwner: String, scope: String?) -> Bool {
        generation == ticket && self.personalOwner == personalOwner && localSharedOwner == sharedOwner && localScope == scope && localActive()
    }
    private func absorbCloudAnimeHistory() async {
        guard !continuingPrivate, localReady, localActive(), let sharedOwner = localSharedOwner else { return }
        let eligible = snapshot.items.filter { CloudAnimeContinueImport.owns($0.id) && !isDismissed($0) }
        guard !eligible.isEmpty else { return }
        let ticket = generation, owner = personalOwner, scope = localScope
        let lease: LocalContinueStore.Lease = { [weak self] in await self?.localCurrent(ticket, personalOwner: owner, sharedOwner: sharedOwner, scope: scope) ?? false }
        do {
            try await localContinue.absorbCloudAnime(eligible, sharedOwner: sharedOwner, now: Date().timeIntervalSince1970 * 1_000, current: lease)
            let value = try await localContinue.snapshot(personalOwner: owner, sharedOwner: sharedOwner)
            guard localCurrent(ticket, personalOwner: owner, sharedOwner: sharedOwner, scope: scope) else { return }
            localSnapshot = value; localRevision &+= 1
        } catch is CancellationError { }
        catch { Diagnostics.shared.recordFailure(error) }
    }
    var hiddenContinuing: [LibraryRecord] { allContinuing.filter { dismissals[$0.id]?.hides($0) == true } }
    func isDismissed(_ record: LibraryRecord) -> Bool { dismissals[record.id]?.hides(record) == true }
    func selectedItems(query: String) -> [LibraryRecord] {
        LibraryListing.select(filteredItems(for: presentation.display.filter), display: presentation.display, query: query)
    }
    func filteredItems(for filter: LibraryFilter) -> [LibraryRecord] {
        let selected: [LibraryRecord]
        switch filter {
        case .all:
            if let projection = watchlistProjection {
                selected = projection.saved + items.filter { record in
                    guard record.continuing || record.watched, let media = record.media else { return false }
                    return projection.keys.isDisjoint(with: TraktWatchlistProjection.keys(media))
                }
            } else { selected = items.filter { $0.bookmarked || $0.continuing || $0.watched } }
        case .saved: selected = watchlistProjection?.saved ?? items.filter(\.bookmarked)
        case .watchlist: selected = (watchlistProjection?.saved ?? items.filter(\.bookmarked)).filter { !$0.watched }
        case .watched: selected = items.filter(\.watched)
        case .favorites:
            selected = favorites.entries.map { favorite in
                guard let record = items.first(where: { $0.media?.identity == favorite.media.identity }) else { return favorite.record }
                var fields = record.raw.objectValue
                fields["_ctime"] = favorite.record.raw["_ctime"]
                return LibraryRecord(raw: .object(fields))
            }
        case .continuing: selected = continuing
        }
        return selected
    }
    func reloadPresentation() {
        presentationReady = false
        do {
            let saved = try KeychainStore().read(LibraryPresentation.key(owner: owner), as: LibraryPresentation.self) ?? LibraryPresentation()
            guard saved.valid else { throw HarborError(code: "library-presentation") }
            presentation = saved; presentationReady = true; sharedPresentationError = nil
        } catch { sharedPresentationError = "No se pudieron recuperar las preferencias de biblioteca. Los datos guardados se conservan." }
        if continuingPrivate { setContinuePrivacy(true) }
    }
    func changeDisplay(_ edit: (inout LibraryDisplay) -> Void) { changePresentation { edit(&$0.display) } }
    @discardableResult
    func hideContinuing(_ record: LibraryRecord, owner expectedOwner: String, now: Date = Date()) -> Task<Void, Never>? {
        guard owner == expectedOwner, let current = allContinuing.first(where: { $0.id == record.id }), current.continuing else { return nil }
        let dismissal = ContinueDismissal(current, now: now)
        guard changeDismissals({ $0[current.id] = dismissal }) else { return nil }
        mutation += 1
        let action = ContinueDismissalAction(current, privateMode: continuingPrivate, authenticated: session != nil, timestampMs: dismissal.timestampMs)
        guard action.clearsResume else { return nil }
        let ticket = generation, session = session, stores = playbackProgressStores, privateRead = continuingPrivate
        return Task { [weak self] in
            guard let self, self.generation == ticket else { return }
            do {
                if let stores {
                    let store = privateRead ? stores.personal : stores.shared
                    try await store.clear(action.target, notNewerThan: dismissal.timestampMs)
                }
                guard self.generation == ticket, let record = action.cloudRecord, let session else { return }
                let lease: LibraryWriteQueue.Lease = { [weak self] in
                    await self?.dismissalCurrent(ticket, owner: expectedOwner, id: current.id, timestampMs: dismissal.timestampMs) ?? false
                }
                _ = try await self.writeQueue.put(record, session: session, current: lease)
                guard self.generation == ticket else { return }
                let next = LibraryWriteQueue.merging(self.records, pending: [record])
                let prepared = try await self.cache.saveSnapshot(next, owner: expectedOwner)
                guard self.generation == ticket else { return }
                self.snapshot = prepared
            } catch is CancellationError { }
            catch { if self.generation == ticket { self.error = safeMessage(error) }; Diagnostics.shared.recordFailure(error) }
        }
    }
    func showContinuing(_ record: LibraryRecord) { changeDismissals { $0.removeValue(forKey: record.id) } }
    func noteLocalProgress(_ target: ResumeTarget, snapshot: ResumeSnapshot, owner expectedOwner: String, personalOwner expectedPerson: String? = nil) {
        guard owner == expectedOwner, !continuingPrivate || expectedPerson == personalOwner,
              let dismissal = dismissals[target.id], dismissal.hasNewPlayback(snapshot) else { return }
        changeDismissals { $0.removeValue(forKey: target.id) }
    }
    @discardableResult private func changeDismissals(_ edit: (inout [String: ContinueDismissal]) -> Void) -> Bool {
        guard continuingPrivate else { return changePresentation { edit(&$0.dismissed) } }
        guard privateDismissalsReady else { return false }
        do { privateDismissals = try privateDismissalStore.change(owner: personalOwner, edit); privatePresentationError = nil; return true }
        catch { privatePresentationError = "No se pudo guardar este cambio de historial privado. Los datos anteriores se conservan."; Diagnostics.shared.recordFailure(error); return false }
    }
    @discardableResult private func changePresentation(_ edit: (inout LibraryPresentation) -> Void) -> Bool {
        guard presentationReady else { return false }
        var next = presentation; edit(&next)
        do {
            guard next.valid, try JSONEncoder().encode(next).count <= 1_024 * 1_024 else { throw HarborError(code: "library-presentation") }
            try KeychainStore().write(next, key: LibraryPresentation.key(owner: owner))
            presentation = next; sharedPresentationError = nil; return true
        } catch { sharedPresentationError = "No se pudo guardar este cambio de biblioteca. Los datos anteriores se conservan."; return false }
    }
    func bookmarked(_ media: Media) -> Bool {
        if let projection = watchlistProjection { return !projection.keys.isDisjoint(with: TraktWatchlistProjection.keys(media)) }
        return items.first { $0.id == media.id }?.bookmarked ?? false
    }
    func watched(_ media: Media) -> Bool {
        if media.episodic {
            let available = ManualWatchedSelection.releasedEpisodes(media)
            let watched = watchedEpisodes(media)
            return !available.isEmpty && available.allSatisfy { watched.contains($0.watchedKey) }
        }
        let record = items.first { $0.id == media.id }
        if let manual = record?.raw["state"]["nativeManualMovie"], manual != .null { return manual == .bool(true) }
        return record?.watched == true || traktWatched.state(for: personalOwner)?.movie(media) == true
    }
    func watchedEpisodes(_ media: Media) -> Set<String> {
        let state = records.first { $0["_id"].string == media.id }?["state"] ?? .null
        var watched = (try? WatchedCodec.decode(state["watched"].string, videos: media.videos ?? [])) ?? []
        if let remote = traktWatched.state(for: personalOwner) { watched.formUnion(remote.episodes(media)) }
        let manual = state["nativeManualEpisodes"].objectValue
        for (key, value) in manual { if value == .bool(true) { watched.insert(key) } else if value == .bool(false) { watched.remove(key) } }
        for episode in media.videos ?? [] {
            var season = episode.season, number = episode.episode
            if let value = episode.imdbSeason { season = value }; if let value = episode.imdbEpisode { number = value }
            guard let season, let number else { continue }
            let canonical = "\(season):\(number)"
            let decision = manual[episode.watchedKey] ?? manual[canonical]
            if decision == .bool(true) { watched.insert(episode.watchedKey) } else if decision == .bool(false) { watched.remove(episode.watchedKey) }
        }
        return watched
    }
    func toggleEpisode(_ media: Media, episode: Episode) async {
        let wasWatched = watchedEpisodes(media).contains(episode.watchedKey), current = generation
        let success = await update(media) { fields in
            var state = (fields["state"] ?? .null).objectValue
            let videos = media.videos ?? []
            var watched = try WatchedCodec.decode(state["watched"]?.string, videos: videos)
            if wasWatched { watched.remove(episode.watchedKey) } else { watched.insert(episode.watchedKey) }
            state["watched"] = .string(try WatchedCodec.encode(watched, videos: videos))
            var manual = (state["nativeManualEpisodes"] ?? .null).objectValue; manual[episode.watchedKey] = .bool(!wasWatched); state["nativeManualEpisodes"] = .object(manual)
            if !wasWatched && fields["removed"] == .bool(true) { fields["temp"] = .bool(true) }
            fields["state"] = .object(state)
        }
        if success, current == generation, !wasWatched { traktWatched.enqueueMark(media, episodes: [episode], owner: personalOwner) }
    }
    func matchesSession(_ session: AccountSession?, personalOwner: String, guestOwner: String) -> Bool {
        writable && presentationReady && self.session?.authKey == session?.authKey
            && owner == (session?.user.id ?? guestOwner) && self.personalOwner == personalOwner
    }
    func setSession(_ session: AccountSession?, personalOwner: String? = nil, guestOwner: String = "guest", synchronize: Bool = true) async {
        generation += 1
        bindTraktWatchlist(nil)
        traktWatched.clear()
        let current = generation
        self.session = session; self.guestOwner = guestOwner
        self.personalOwner = personalOwner ?? session?.user.id ?? guestOwner
        continuingPrivate = false; privateDismissalsReady = false; privateDismissals = [:]; playbackProgressStores = nil
        privatePresentationError = nil; privateDismissalScope = nil
        localReady = false; localSnapshot = .init(); localRevision &+= 1; localScope = nil
        snapshot = LibrarySnapshot([]); syncing = false; busy = false; error = nil; writable = false; loading = true
        favorites = MediaFavorites(owner: self.personalOwner)
        discovery = DiscoveryPreferences(owner: self.personalOwner)
        presentation = LibraryPresentation(); reloadPresentation()
        lastProgressWrite = [:]
        defer { if current == generation { loading = false } }
        let owner = self.owner
        do {
            let saved = try await cache.readSnapshot(owner: owner)
            guard current == generation else { return }
            let pending = try await writeQueue.pending(owner: owner)
            guard current == generation else { return }
            snapshot = LibrarySnapshot(LibraryWriteQueue.merging(saved.records, pending: pending)); writable = true
        } catch { self.error = safeMessage(error); return }
        if synchronize { await sync() }
    }
    func sync() async {
        guard let session, !busy, !syncing else { return }
        let current = generation
        let revision = mutation
        syncing = true
        loading = true
        defer { if current == generation { loading = false; syncing = false } }
        do {
            try await flushWrites(session, ticket: current)
            guard current == generation, revision == mutation else { return }
            let next = try await service.records(session)
            guard current == generation, revision == mutation else { return }
            let pending = try await writeQueue.pending(owner: session.user.id)
            guard current == generation, revision == mutation else { return }
            let prepared = try await cache.saveSnapshot(LibraryWriteQueue.merging(next, pending: pending), owner: session.user.id)
            guard current == generation, revision == mutation else { return }
            snapshot = prepared; error = nil; writable = true
            await absorbCloudAnimeHistory()
        } catch is CancellationError { return }
        catch { if current == generation { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) } }
    }
    func toggleBookmark(_ media: Media) async {
        let taste = discovery, current = generation, binding = traktWatchlist.flatMap { $0.isActive ? $0 : nil }
        let wasSaved = bookmarked(media), related = wasSaved ? bookmarkAliases(media, binding: binding) : []
        let decision = binding?.decision(saved: !wasSaved)
        let success = await update(media, related: related) { fields in
            fields["removed"] = .bool(wasSaved)
            let state = fields["state"] ?? .null
            fields["temp"] = .bool(wasSaved && ((state["timeOffset"].numericValue ?? 0) > 0 || (state["flaggedWatched"].numericValue ?? 0) > 0))
            if let binding, let decision {
                var decisions = (fields["nativeTraktWatchlist"] ?? .null).objectValue
                decisions[binding.decisionKey] = decision; fields["nativeTraktWatchlist"] = .object(decisions)
            }
            if fields["_id"]?.string == media.id, let imdb = media.imdbID { fields["imdb_id"] = .string(imdb) }
        }
        if success, current == generation { binding?.enqueue(media, saved: !wasSaved) }
        if success, taste.owner == personalOwner, bookmarked(media) { taste.track(.watchlist, media: media) }
    }
    private func bookmarkAliases(_ media: Media, binding: TraktWatchlistSync?) -> Set<String> {
        var keys = TraktWatchlistProjection.keys(media), related = Set<String>()
        for _ in 0..<3 {
            if let binding {
                for item in binding.store.snapshot.watchlist {
                    let aliases = TraktWatchlistProjection.keys(item)
                    if !keys.isDisjoint(with: aliases) { keys.formUnion(aliases) }
                }
            }
            for record in items {
                guard let other = record.media else { continue }; let aliases = TraktWatchlistProjection.keys(other)
                if !keys.isDisjoint(with: aliases) { related.insert(record.id); keys.formUnion(aliases) }
            }
        }
        return related
    }
    @discardableResult func saveBookmark(_ media: Media, owner expectedOwner: String, personalOwner expectedPersonalOwner: String) async -> Bool {
        guard owner == expectedOwner, personalOwner == expectedPersonalOwner, writable else { return false }
        if items.first(where: { $0.id == media.id })?.bookmarked == true { return true }
        return await update(media) { fields in fields["removed"] = .bool(false); fields["temp"] = .bool(false) }
    }
    func toggleWatched(_ media: Media) async {
        let taste = discovery, current = generation, wasWatched = watched(media)
        let success = await update(media) { fields in
            var state: [String: JSONValue] = [:]
            if case .object(let current) = fields["state"] { state = current }
            if media.episodic {
                let videos = media.videos ?? []
                let available = ManualWatchedSelection.releasedEpisodes(media)
                guard !available.isEmpty else { throw HarborError(code: "invalid-watched-state") }
                var watched = try WatchedCodec.decode(state["watched"]?.string, videos: videos)
                if wasWatched { for video in available { watched.remove(video.watchedKey) } }
                else { for video in available { watched.insert(video.watchedKey) } }
                state["watched"] = .string(try WatchedCodec.encode(watched, videos: videos))
                var manual = (state["nativeManualEpisodes"] ?? .null).objectValue
                for video in available { manual[video.watchedKey] = .bool(!wasWatched) }; state["nativeManualEpisodes"] = .object(manual)
            } else {
                state["flaggedWatched"] = .integer(wasWatched ? 0 : 1); state["nativeManualMovie"] = .bool(!wasWatched)
                if wasWatched { state["timesWatched"] = .integer(0) }
            }
            state["timeOffset"] = .integer(0)
            if !wasWatched && fields["removed"] == .bool(true) { fields["temp"] = .bool(true) }
            fields["state"] = .object(state)
        }
        if success, current == generation, !wasWatched {
            traktWatched.enqueueMark(media, episodes: media.episodic ? ManualWatchedSelection.releasedEpisodes(media) : [], owner: personalOwner, wholeSeries: true)
        }
        if success, taste.owner == personalOwner, watched(media) { taste.track(.watched, media: media) }
    }
    func resume(for target: ResumeTarget, refresh: Bool = true) async -> CloudResume? {
        let current = generation, privateRead = continuingPrivate
        var fresh: CloudResume?
        if let session, refresh, !privateRead {
            do {
                let record = try await service.record(target.id, session: session)
                guard generation == current else { return nil }
                fresh = record.flatMap {
                    let value = LibraryRecord(raw: $0)
                    return isDismissed(value) ? nil : value.resume(for: target)
                }
            } catch { if generation == current { Diagnostics.shared.recordFailure(error) } }
        }
        guard generation == current, continuingPrivate == privateRead else { return nil }
        let local = localReady && localActive() ? (privateRead ? localSnapshot.personalRecords : localSnapshot.sharedRecords) : []
        let shared = privateRead ? [] : items + simklPlayback.records(for: personalOwner) + traktPlayback.records(for: personalOwner)
        // A shared dismissal clears the shared resume. Older local ledgers and
        // tracker snapshots must not resurrect the position while cloud is offline.
        let candidates = (shared + local).filter { privateRead || (session == nil && $0.raw["external"].string == nil) || !isDismissed($0) }
            .compactMap { $0.resume(for: target) } + [fresh].compactMap { $0 }
        return candidates.max { $0.entry.t < $1.entry.t }
    }
    func saveProgress(_ media: Media, target: ResumeTarget, snapshot: ResumeSnapshot, owner expectedOwner: String) async {
        guard expectedOwner == owner else { return }
        guard snapshot.timestampMs > (lastProgressWrite[media.id] ?? 0) else { return }
        guard snapshot.exiting || snapshot.timestampMs >= (lastProgressWrite[media.id] ?? 0) + 15_000 else { return }
        let current = generation
        let success = await update(media, progress: true) { fields in
            try LibraryPlayback.apply(snapshot, target: target, media: media, to: &fields)
        }
        if success, current == generation { lastProgressWrite[media.id] = snapshot.timestampMs }
    }
    @discardableResult private func update(_ media: Media, progress: Bool = false, related: Set<String> = [], change: (inout [String: JSONValue]) throws -> Void) async -> Bool {
        guard writable, !busy else { return false }
        busy = true; mutation += 1; let current = generation; let activeSession = session; let activeOwner = owner
        defer { if current == generation { busy = false } }
        do {
            // Read the current cloud item before changing it. Unknown provider
            // fields and progress from another device survive every mutation.
            let original: JSONValue?
            if let activeSession {
                do {
                    let remote = try await service.record(media.id, session: activeSession)
                    let cached = records.first { $0["_id"].string == media.id }
                    original = LibraryWriteQueue.merging([remote].compactMap { $0 }, pending: [cached].compactMap { $0 }).first
                }
                catch is CancellationError { throw CancellationError() }
                catch { original = records.first { $0["_id"].string == media.id } }
            }
            else { original = records.first { $0["_id"].string == media.id } }
            guard current == generation else { return false }
            var fields = LibraryRecord.new(media)
            if case .object(let saved) = original { fields = saved }
            else {
                fields["removed"] = .bool(true)
                fields["temp"] = .bool(progress)
            }
            try change(&fields); fields["_mtime"] = .string(ContinueDismissalAction.iso(Date().timeIntervalSince1970 * 1_000))
            let record = JSONValue.object(fields)
            var changed = [record]
            for saved in records where saved["_id"].string != media.id && related.contains(saved["_id"].string ?? "") {
                var fields = saved.objectValue; try change(&fields); fields["_mtime"] = record["_mtime"]; changed.append(.object(fields))
            }
            if let activeSession {
                let lease: LibraryWriteQueue.Lease = { [weak self] in await self?.writeCurrent(current, owner: activeOwner) ?? false }
                for record in changed { _ = try await writeQueue.put(record, session: activeSession, current: lease) }
            }
            guard current == generation else { return false }
            let ids = Set(changed.compactMap { $0["_id"].string })
            let next = records.filter { !ids.contains($0["_id"].string ?? "") } + changed
            let prepared = try await cache.saveSnapshot(next, owner: activeOwner)
            guard current == generation else { return false }
            snapshot = prepared; error = nil; return true
        } catch is CancellationError { return false }
        catch { if current == generation { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }; return false }
    }
    private func writeCurrent(_ ticket: Int, owner: String) -> Bool { generation == ticket && self.owner == owner }
    private func dismissalCurrent(_ ticket: Int, owner: String, id: String, timestampMs: Double) -> Bool {
        writeCurrent(ticket, owner: owner) && dismissals[id]?.timestampMs == timestampMs
    }
    @discardableResult private func flushWrites(_ session: AccountSession, ticket: Int) async throws -> [JSONValue] {
        let owner = session.user.id
        return try await writeQueue.flush(session, current: { [weak self] in await self?.writeCurrent(ticket, owner: owner) ?? false })
    }
    func flushPendingWrites() async {
        guard let session else { return }
        let ticket = generation, revision = mutation, owner = session.user.id
        do {
            let reconciled = try await flushWrites(session, ticket: ticket)
            guard !reconciled.isEmpty, generation == ticket, mutation == revision else { return }
            let ids = Set(reconciled.compactMap { $0["_id"].string })
            let pending = try await writeQueue.pending(owner: owner)
            guard generation == ticket, mutation == revision else { return }
            let next = LibraryWriteQueue.merging(records.filter { !ids.contains($0["_id"].string ?? "") } + reconciled, pending: pending)
            let prepared = try await cache.saveSnapshot(next, owner: owner)
            guard generation == ticket, mutation == revision else { return }
            snapshot = prepared
        }
        catch is CancellationError { }
        catch { if generation == ticket { self.error = safeMessage(error) }; Diagnostics.shared.recordFailure(error) }
    }
}
