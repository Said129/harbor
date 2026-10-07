import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    private var records: [JSONValue] = []
    private let cache = LibraryCache()
    private let service = LibraryService()
    private var session: AccountSession?
    private var generation = 0
    private var mutation = 0
    private var writable = false
    private var presentationReady = false
    private(set) var presentation = LibraryPresentation()
    private(set) var presentationError: String?
    private(set) var favorites = MediaFavorites(owner: "guest")
    private(set) var discovery = DiscoveryPreferences(owner: "guest")
    var canChangePresentation: Bool { presentationReady }
    private var lastProgressWrite: [String: UInt64] = [:]
    var loading = false
    var busy = false
    var error: String?
    var owner: String { session?.user.id ?? "guest" }
    var items: [LibraryRecord] { records.map { LibraryRecord(raw: $0) }.filter { !$0.id.isEmpty && $0.media != nil }.sorted { $0.modified > $1.modified } }
    var continuing: [LibraryRecord] {
        var display = LibraryDisplay(); display.filter = .continuing
        return LibraryListing.select(items.filter { $0.continuing && presentation.dismissed[$0.id]?.hides($0) != true }, display: display, query: "")
    }
    var hiddenContinuing: [LibraryRecord] { items.filter { $0.continuing && presentation.dismissed[$0.id]?.hides($0) == true } }
    func selectedItems(query: String) -> [LibraryRecord] {
        LibraryListing.select(filteredItems(for: presentation.display.filter), display: presentation.display, query: query)
    }
    func filteredItems(for filter: LibraryFilter) -> [LibraryRecord] {
        let selected: [LibraryRecord]
        switch filter {
        case .all: selected = items.filter { $0.bookmarked || $0.continuing || $0.watched }
        case .saved: selected = items.filter(\.bookmarked)
        case .watchlist: selected = items.filter { $0.bookmarked && !$0.watched }
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
            presentation = saved; presentationReady = true; presentationError = nil
        } catch { presentationError = "No se pudieron recuperar las preferencias de biblioteca. Los datos guardados se conservan." }
    }
    func changeDisplay(_ edit: (inout LibraryDisplay) -> Void) { changePresentation { edit(&$0.display) } }
    func hideContinuing(_ record: LibraryRecord, owner expectedOwner: String) {
        guard owner == expectedOwner, let current = items.first(where: { $0.id == record.id }), current.continuing else { return }
        changePresentation { $0.dismissed[current.id] = ContinueDismissal(current) }
    }
    func showContinuing(_ record: LibraryRecord) { changePresentation { $0.dismissed.removeValue(forKey: record.id) } }
    func noteLocalProgress(_ target: ResumeTarget, snapshot: ResumeSnapshot, owner expectedOwner: String) {
        guard owner == expectedOwner, let dismissal = presentation.dismissed[target.id], dismissal.hasNewPlayback(snapshot) else { return }
        changePresentation { $0.dismissed.removeValue(forKey: target.id) }
    }
    private func changePresentation(_ edit: (inout LibraryPresentation) -> Void) {
        guard presentationReady else { return }
        var next = presentation; edit(&next)
        do {
            guard next.valid, try JSONEncoder().encode(next).count <= 1_024 * 1_024 else { throw HarborError(code: "library-presentation") }
            try KeychainStore().write(next, key: LibraryPresentation.key(owner: owner))
            presentation = next; presentationError = nil
        } catch { presentationError = "No se pudo guardar este cambio de biblioteca. Los datos anteriores se conservan." }
    }
    func bookmarked(_ media: Media) -> Bool { items.first { $0.id == media.id }?.bookmarked ?? false }
    func watched(_ media: Media) -> Bool {
        if media.episodic {
            let available = (media.videos ?? []).filter { $0.season != nil && $0.episode != nil && $0.available }
            return !available.isEmpty && available.allSatisfy { watchedEpisodes(media).contains($0.watchedKey) }
        }
        return items.first { $0.id == media.id }?.watched ?? false
    }
    func watchedEpisodes(_ media: Media) -> Set<String> {
        let field = records.first { $0["_id"].string == media.id }?["state"]["watched"].string
        return (try? WatchedCodec.decode(field, videos: media.videos ?? [])) ?? []
    }
    func toggleEpisode(_ media: Media, episode: Episode) async {
        await update(media) { fields in
            var state = (fields["state"] ?? .null).objectValue
            let videos = media.videos ?? []
            var watched = try WatchedCodec.decode(state["watched"]?.string, videos: videos)
            if !watched.insert(episode.watchedKey).inserted { watched.remove(episode.watchedKey) }
            state["watched"] = .string(try WatchedCodec.encode(watched, videos: videos))
            fields["state"] = .object(state)
        }
    }
    func setSession(_ session: AccountSession?) async {
        generation += 1
        let current = generation
        self.session = session; records = []; error = nil; writable = false; loading = true
        favorites = MediaFavorites(owner: session?.user.id ?? "guest")
        discovery = DiscoveryPreferences(owner: session?.user.id ?? "guest")
        presentation = LibraryPresentation(); reloadPresentation()
        lastProgressWrite = [:]
        defer { if current == generation { loading = false } }
        let owner = session?.user.id ?? "guest"
        do {
            let saved = try await cache.read(owner: owner)
            guard current == generation else { return }
            records = saved; writable = true
        } catch { self.error = safeMessage(error); return }
        await sync()
    }
    func sync() async {
        guard let session, !busy else { return }
        let current = generation
        let revision = mutation
        loading = true
        defer { if current == generation { loading = false } }
        do {
            let next = try await service.records(session)
            guard current == generation, revision == mutation else { return }
            try await cache.save(next, owner: session.user.id)
            guard current == generation, revision == mutation else { return }
            records = next; error = nil; writable = true
        } catch is CancellationError { return }
        catch { if current == generation { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) } }
    }
    func toggleBookmark(_ media: Media) async {
        let taste = discovery
        let success = await update(media) { fields in
            let wasSaved = fields["removed"] != .bool(true) && fields["temp"] != .bool(true)
            fields["removed"] = .bool(wasSaved)
            let state = fields["state"] ?? .null
            fields["temp"] = .bool(wasSaved && ((state["timeOffset"].numericValue ?? 0) > 0 || (state["flaggedWatched"].numericValue ?? 0) > 0))
        }
        if success, taste.owner == owner, bookmarked(media) { taste.track(.watchlist, media: media) }
    }
    func toggleWatched(_ media: Media) async {
        let taste = discovery
        let success = await update(media) { fields in
            var state: [String: JSONValue] = [:]
            if case .object(let current) = fields["state"] { state = current }
            if media.episodic {
                let videos = media.videos ?? []
                let available = videos.filter { $0.season != nil && $0.episode != nil && $0.available }
                guard !available.isEmpty else { throw HarborError(code: "invalid-watched-state") }
                var watched = try WatchedCodec.decode(state["watched"]?.string, videos: videos)
                if available.allSatisfy({ watched.contains($0.watchedKey) }) { for video in available { watched.remove(video.watchedKey) } }
                else { for video in available { watched.insert(video.watchedKey) } }
                state["watched"] = .string(try WatchedCodec.encode(watched, videos: videos))
            } else {
                let watched = (state["flaggedWatched"]?.numericValue ?? 0) > 0 || (state["timesWatched"]?.numericValue ?? 0) > 0
                state["flaggedWatched"] = .integer(watched ? 0 : 1)
                if watched { state["timesWatched"] = .integer(0) }
            }
            state["timeOffset"] = .integer(0)
            fields["state"] = .object(state)
        }
        if success, taste.owner == owner, watched(media) { taste.track(.watched, media: media) }
    }
    func resume(for target: ResumeTarget, refresh: Bool = true) async -> CloudResume? {
        let current = generation
        if let session, refresh {
            do {
                let record = try await service.record(target.id, session: session)
                guard generation == current else { return nil }
                return record.flatMap { LibraryRecord(raw: $0).resume(for: target) }
            } catch { if generation == current { Diagnostics.shared.recordFailure(error) } }
        }
        guard generation == current else { return nil }
        return records.first { $0["_id"].string == target.id }.flatMap { LibraryRecord(raw: $0).resume(for: target) }
    }
    func saveProgress(_ media: Media, target: ResumeTarget, snapshot: ResumeSnapshot, owner expectedOwner: String) async {
        guard expectedOwner == owner else { return }
        guard snapshot.timestampMs > (lastProgressWrite[media.id] ?? 0) else { return }
        guard snapshot.exiting || snapshot.timestampMs >= (lastProgressWrite[media.id] ?? 0) + 15_000 else { return }
        let success = await update(media, progress: true) { fields in
            var state: [String: JSONValue] = [:]
            if case .object(let previous) = fields["state"] { state = previous }
            state["timeOffset"] = .number(snapshot.positionMs)
            state["duration"] = .number(snapshot.durationMs)
            state["lastWatched"] = .string(Date().ISO8601Format())
            if let season = target.season { state["season"] = .integer(Int64(season)) }
            if let episode = target.episode { state["episode"] = .integer(Int64(episode)) }
            state["video_id"] = .string(target.videoId ?? target.id)
            let finished = snapshot.durationMs > 0 && snapshot.positionMs / snapshot.durationMs >= 0.9
            if media.episodic {
                if finished, let videos = media.videos, let episode = videos.first(where: { $0.id == target.videoId }) {
                    var watched = try WatchedCodec.decode(state["watched"]?.string, videos: videos)
                    watched.insert(episode.watchedKey)
                    state["watched"] = .string(try WatchedCodec.encode(watched, videos: videos))
                }
            } else { state["flaggedWatched"] = .integer(finished ? 1 : 0) }
            fields["state"] = .object(state)
            if fields["removed"] == .bool(true) { fields["temp"] = .bool(true) }
        }
        if success { lastProgressWrite[media.id] = snapshot.timestampMs }
    }
    @discardableResult private func update(_ media: Media, progress: Bool = false, change: (inout [String: JSONValue]) throws -> Void) async -> Bool {
        guard writable, !busy else { return false }
        busy = true; mutation += 1; let current = generation; let activeSession = session
        defer { busy = false }
        do {
            // Read the current cloud item before changing it. Unknown provider
            // fields and progress from another device survive every mutation.
            let original: JSONValue?
            if let activeSession { original = try await service.record(media.id, session: activeSession) }
            else { original = records.first { $0["_id"].string == media.id } }
            guard current == generation else { return false }
            var fields = LibraryRecord.new(media)
            if case .object(let saved) = original { fields = saved }
            else {
                fields["removed"] = .bool(true)
                fields["temp"] = .bool(progress)
            }
            try change(&fields); fields["_mtime"] = .string(Date().ISO8601Format())
            let record = JSONValue.object(fields)
            if let activeSession { try await service.save(record, session: activeSession) }
            guard current == generation else { return false }
            var next = records.filter { $0["_id"].string != media.id }; next.append(record)
            try await cache.save(next, owner: activeSession?.user.id ?? "guest")
            guard current == generation else { return false }
            records = next; error = nil; return true
        } catch is CancellationError { return false }
        catch { if current == generation { self.error = safeMessage(error); Diagnostics.shared.recordFailure(error) }; return false }
    }
}
