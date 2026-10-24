import Foundation
import Observation

@MainActor @Observable final class MusicArtistRosterModel {
    private(set) var rows: [MusicArtistAudience] = []
    private(set) var loading = false
    private(set) var failure = false
    private(set) var exhausted = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cursor = 0
    @ObservationIgnored private var genre: Int?
    @ObservationIgnored private var enrichment: Task<Void, Never>?
    @ObservationIgnored private var pendingAudience: [MusicArtistReference] = []
    @ObservationIgnored private var revision: UUID?
    @ObservationIgnored private var pageLoaded = false
    func load(_ genre: Int, known: [MusicCatalogArtist], client: any MusicArtistCalling, revision: UUID? = nil) async {
        if self.genre != genre || self.revision != revision {
            cancel(); self.genre = genre; self.revision = revision; rows = []; cursor = 0
            exhausted = false; failure = false; pendingAudience = []; pageLoaded = false
        }
        if !pageLoaded { await loadNext(known: known, client: client) }
        else { enrich(client: client) }
    }
    func loadNext(known: [MusicCatalogArtist], client: any MusicArtistCalling) async {
        guard !loading, !exhausted, let genre else { return }
        let token = generation, offset = cursor; loading = true; failure = false
        defer { if token == generation { loading = false } }
        do {
            let page = try await client.roster(genre, offset: offset); try Task.checkCancellation()
            guard token == generation else { return }
            if let next = page.next, next <= offset { throw HarborError(code: "music-artist-cursor") }
            var seen = Set(rows.map(\.id))
            let fresh = page.artists.filter { seen.insert($0.id).inserted }.map { supplied in
                var artist = supplied
                if artist.artwork == nil { artist.artwork = known.first { $0.name.lowercased() == artist.name.lowercased() }?.artwork }
                return artist
            }
            rows += fresh.map { .init(artist: $0) }; cursor = page.next ?? offset; exhausted = page.next == nil
            pageLoaded = true; pendingAudience += fresh; enrich(client: client)
        } catch is CancellationError { }
        catch { if token == generation, !Task.isCancelled { failure = true } }
    }
    private func enrich(client: any MusicArtistCalling) {
        guard enrichment == nil, !pendingAudience.isEmpty else { return }
        let token = generation
        enrichment = Task { [weak self] in
            guard let self else { return }
            defer { if token == self.generation { self.enrichment = nil } }
            while !self.pendingAudience.isEmpty {
                guard token == self.generation, !Task.isCancelled else { return }
                let batch = Array(self.pendingAudience.prefix(3))
                do {
                    let stats = try await client.audience(batch); try Task.checkCancellation()
                    guard token == self.generation else { return }
                    let byID = Dictionary(stats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    self.rows = self.rows.map { byID[$0.id] ?? $0 }
                } catch is CancellationError { return }
                catch { if token != self.generation { return } }
                self.pendingAudience.removeFirst(min(batch.count, self.pendingAudience.count))
            }
        }
    }
    func cancel() { generation = UUID(); enrichment?.cancel(); enrichment = nil; loading = false }
}
