import Foundation
import Observation

@MainActor @Observable final class MusicCatalogModel {
    let client: any MusicCatalogCalling
    private(set) var rows: [MusicCatalogRow] = []
    private(set) var result: MusicCatalogSearch?
    private(set) var loading = false
    private(set) var failure: String?
    private(set) var activeQuery = ""
    private(set) var hasRequested = false
    @ObservationIgnored private var homeLoaded = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var cachedSearch: (String, MusicCatalogSearch)?
    init(client: any MusicCatalogCalling = MusicCatalogClient()) { self.client = client }

    func load(query raw: String, refresh: Bool = false, debounce: Bool = true) async {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = UUID(); generation = token; activeQuery = query; failure = nil; result = nil; hasRequested = true
        guard query.count <= 200 else { failure = "Search is too long."; loading = false; return }
        if query.isEmpty, homeLoaded, !refresh { loading = false; return }
        if !refresh, let (previousQuery, previousResult) = cachedSearch, query == previousQuery {
            result = previousResult; loading = false; return
        }
        loading = true
        defer { if generation == token { loading = false } }
        do {
            if !query.isEmpty, debounce { try await Task.sleep(for: .milliseconds(350)) }
            if query.isEmpty {
                let value = try await client.home(); try Task.checkCancellation()
                guard token == generation else { return }
                rows = value; homeLoaded = true
            } else {
                let value = try await client.search(query, limit: 24); try Task.checkCancellation()
                guard token == generation else { return }
                result = value; cachedSearch = (query, value)
            }
        } catch is CancellationError { }
        catch {
            guard token == generation, !Task.isCancelled else { return }
            if query.isEmpty, !rows.isEmpty { return }
            if let (previousQuery, previousResult) = cachedSearch, query == previousQuery { result = previousResult; return }
            failure = "Music is unavailable right now."
        }
    }
}

@MainActor @Observable final class MusicCatalogDetailModel {
    private(set) var items: [MusicCatalogItem] = []
    private(set) var loading = false
    private(set) var failure: String?
    private(set) var nextCursor: String?
    private(set) var total: UInt64?
    private(set) var scope: MusicCatalogScope = .catalog
    private(set) var loaded = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var usedCursors: Set<String> = []
    @ObservationIgnored private var route: (MusicCatalogArtist, MusicCatalogKind)?

    func load(_ item: MusicCatalogItem, kind: MusicCatalogKind, client: any MusicCatalogCalling) async {
        let token = UUID(); generation = token; usedCursors = []; route = nil
        items = []; nextCursor = nil; total = nil; failure = nil; loading = true; loaded = false; scope = .catalog
        defer { if generation == token { loading = false; loaded = true } }
        do {
            switch item {
            case .album(let album):
                let value = try await client.albumTracks(album); try Task.checkCancellation()
                guard token == generation else { return }; items = value.map(MusicCatalogItem.track)
            case .playlist(let playlist):
                let value = try await client.playlistTracks(playlist); try Task.checkCancellation()
                guard token == generation else { return }; items = value.map(MusicCatalogItem.track)
            case .artist(let artist):
                let page = try await client.artistCatalog(artist, kind: kind, cursor: nil); try Task.checkCancellation()
                guard token == generation else { return }
                route = (artist, kind); apply(page, appending: false)
            case .track, .station: break
            }
        } catch is CancellationError { }
        catch {
            guard token == generation, !Task.isCancelled else { return }
            failure = "Music is unavailable right now."
        }
    }
    func loadNext(client: any MusicCatalogCalling) async {
        guard !loading, let (artist, kind) = route, let cursor = nextCursor, !usedCursors.contains(cursor) else { return }
        let token = generation; loading = true; failure = nil
        defer { if token == generation { loading = false } }
        do {
            let page = try await client.artistCatalog(artist, kind: kind, cursor: cursor); try Task.checkCancellation()
            guard token == generation else { return }
            usedCursors.insert(cursor); apply(page, appending: true)
        } catch is CancellationError { }
        catch {
            guard token == generation, !Task.isCancelled else { return }
            failure = "Music is unavailable right now."
        }
    }
    private func apply(_ page: MusicCatalogPage, appending: Bool) {
        var seen = Set<String>()
        items = ((appending ? items : []) + page.items).filter { seen.insert($0.id).inserted }
        nextCursor = page.nextCursor.flatMap { usedCursors.contains($0) ? nil : $0 }
        total = page.total ?? total; scope = page.scope
    }
}
