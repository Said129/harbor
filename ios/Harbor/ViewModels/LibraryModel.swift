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
    private var lastProgressWrite: [String: UInt64] = [:]
    var loading = false
    var busy = false
    var error: String?
    var items: [LibraryRecord] { records.map { LibraryRecord(raw: $0) }.filter { !$0.id.isEmpty && $0.media != nil }.sorted { $0.modified > $1.modified } }
    var continuing: [LibraryRecord] { items.filter(\.continuing) }
    func bookmarked(_ media: Media) -> Bool { items.first { $0.id == media.id }?.bookmarked ?? false }
    func watched(_ media: Media) -> Bool { items.first { $0.id == media.id }?.watched ?? false }
    func setSession(_ session: AccountSession?) async {
        generation += 1
        let current = generation
        self.session = session; records = []; error = nil; writable = false; loading = true
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
        catch { if current == generation { error = safeMessage(error); Diagnostics.shared.recordFailure(error) } }
    }
    func toggleBookmark(_ media: Media) async {
        await update(media) { fields in
            let wasSaved = fields["removed"] != .bool(true) && fields["temp"] != .bool(true)
            fields["removed"] = .bool(wasSaved)
            let state = fields["state"] ?? .null
            fields["temp"] = .bool(wasSaved && ((state["timeOffset"].numericValue ?? 0) > 0 || (state["flaggedWatched"].numericValue ?? 0) > 0))
        }
    }
    func toggleWatched(_ media: Media) async {
        await update(media) { fields in
            var state: [String: JSONValue] = [:]
            if case .object(let current) = fields["state"] { state = current }
            let watched = (state["flaggedWatched"]?.numericValue ?? 0) > 0
            state["flaggedWatched"] = .integer(watched ? 0 : 1)
            state["timeOffset"] = .integer(0)
            fields["state"] = .object(state)
        }
    }
    func saveProgress(_ media: Media, target: ResumeTarget, snapshot: ResumeSnapshot) async {
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
            state["flaggedWatched"] = .integer(finished ? 1 : 0)
            fields["state"] = .object(state)
            if fields["removed"] == .bool(true) { fields["temp"] = .bool(true) }
        }
        if success { lastProgressWrite[media.id] = snapshot.timestampMs }
    }
    @discardableResult private func update(_ media: Media, progress: Bool = false, change: (inout [String: JSONValue]) -> Void) async -> Bool {
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
            change(&fields); fields["_mtime"] = .string(Date().ISO8601Format())
            let record = JSONValue.object(fields)
            if let activeSession { try await service.save(record, session: activeSession) }
            guard current == generation else { return false }
            var next = records.filter { $0["_id"].string != media.id }; next.append(record)
            try await cache.save(next, owner: activeSession?.user.id ?? "guest")
            guard current == generation else { return false }
            records = next; error = nil; return true
        } catch is CancellationError { return false }
        catch { if current == generation { error = safeMessage(error); Diagnostics.shared.recordFailure(error) }; return false }
    }
}
