import Foundation

/// Public entry metadata is reusable; the current addon/account media is never cached here.
actor AnimeFranchiseEpisodeService {
    static let shared = AnimeFranchiseEpisodeService()
    typealias Fetch = @Sendable (AnimeFranchiseEntry) async throws -> Media
    struct Result: Sendable { let sources: [Media]; let missing: [String] }
    private struct Cached { let media: Media; let expires: Date }
    private let fetch: Fetch
    private let gate = AnimeMetadataGate()
    private var cache: [String: Cached] = [:]
    private var pending: [String: Task<Media, Error>] = [:]

    init(fetch: @escaping Fetch = { entry in
        let raw = try await AnimeService.metadata(id: entry.id, kind: entry.media.type)
        let variants = await AnimeEpisodeService.shared.variants(for: raw)
        let supplemented = await TVDBService.shared.supplement(variants, for: raw)
        var media = raw; media.videos = supplemented.seasons; return media
    }) { self.fetch = fetch }

    func entries(_ entries: [AnimeFranchiseEntry], language: String) async -> Result {
        var sources: [Int: Media] = [:], missing: [Int: String] = [:], next = 0
        await withTaskGroup(of: (Int, Media?).self) { group in
            func enqueue(_ index: Int) {
                group.addTask { (index, try? await self.entry(entries[index], language: language)) }
            }
            while next < min(4, entries.count) { enqueue(next); next += 1 }
            while let (index, media) = await group.next() {
                if let media { sources[index] = media } else { missing[index] = entries[index].id }
                if next < entries.count { enqueue(next); next += 1 }
            }
        }
        return Result(sources: sources.keys.sorted().compactMap { sources[$0] }, missing: missing.keys.sorted().compactMap { missing[$0] })
    }

    private func entry(_ entry: AnimeFranchiseEntry, language: String) async throws -> Media {
        guard !entry.extra, entry.id.hasPrefix("kitsu:"), AnimeService.isAnime(entry.id) else { throw HarborError(code: "anime-id") }
        let key = entry.id + "|" + language
        if let value = cache[key], value.expires > Date() { return value.media }
        if let task = pending[key] { return try await task.value }
        let fetch = self.fetch, gate = self.gate
        let task = Task {
            try await gate.run {
                let media = try await fetch(entry)
                guard media.id == entry.id, media.episodic, media.videos?.isEmpty == false else { throw HarborError(code: "no-metadata") }
                return media
            }
        }
        pending[key] = task
        defer { pending[key] = nil }
        let media = try await task.value
        // Keep large series intact while avoiding an unbounded public cache.
        let cost = media.videos?.count ?? 0
        if cost <= 10_000 {
            while cache.count >= 24 || cache.values.reduce(0, { $0 + ($1.media.videos?.count ?? 0) }) + cost > 30_000 {
                guard let key = cache.min(by: { $0.value.expires < $1.value.expires })?.key else { break }
                cache[key] = nil
            }
            cache[key] = Cached(media: media, expires: Date().addingTimeInterval(3600))
        }
        return media
    }
}
