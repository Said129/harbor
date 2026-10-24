import Foundation
import Observation

@MainActor @Observable final class MusicExploreModel {
    let client: any MusicExploreCalling
    let asset: MusicExploreAsset?
    private(set) var genres: [MusicGenre]
    private(set) var chart: MusicGenreSelection?
    private(set) var loading = false
    private(set) var filtering = false
    private(set) var filterFailure = false
    private(set) var chartFailure = false
    @ObservationIgnored private var filterGeneration = UUID()
    @ObservationIgnored private var chartGeneration = UUID()
    init(client: any MusicExploreCalling) {
        let loaded = try? MusicExploreAsset.read()
        self.client = client; asset = loaded; genres = loaded?.visibleGenres ?? []
    }
    func filter(_ filters: MusicGenreFilters, locale: Locale, debounce: Bool = true) async {
        guard let asset else { filterFailure = true; return }
        let token = UUID(); filterGeneration = token; filtering = true; filterFailure = false
        defer { if token == filterGeneration { filtering = false } }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(150)) }
            let countries = Dictionary(uniqueKeysWithValues: asset.definitions.countries.map { ($0, locale.localizedString(forRegionCode: $0) ?? $0) })
            let names = Dictionary(uniqueKeysWithValues: asset.definitions.genres.filter { (10108...10133).contains($0.id) }.map { ("music.genre." + $0.slug, $0.displayName) })
            let result = try await client.filter(filters, countryNames: countries, genreNames: names)
            try Task.checkCancellation(); guard token == filterGeneration else { return }
            genres = result.filter { !asset.mobileExcludedGenreIds.contains($0.id) }
        } catch is CancellationError { }
        catch { if token == filterGeneration, !Task.isCancelled { filterFailure = true } }
    }
    func loadChart(refresh: Bool = false) async {
        guard asset != nil, chart == nil || refresh else { return }
        let token = UUID(); chartGeneration = token; loading = true; chartFailure = false
        defer { if token == chartGeneration { loading = false } }
        do {
            let result = try await client.chart(); try Task.checkCancellation()
            guard token == chartGeneration else { return }; chart = result
        } catch is CancellationError { }
        catch { if token == chartGeneration, !Task.isCancelled, chart == nil { chartFailure = true } }
    }
    func dispose() { filterGeneration = UUID(); chartGeneration = UUID(); client.dispose() }
}

@MainActor @Observable final class MusicGenreModel {
    private(set) var selection: MusicGenreSelection?
    private(set) var related: [MusicGenre] = []
    private(set) var loading = false
    private(set) var failure = false
    private(set) var more = true
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var nextPage = 0
    @ObservationIgnored private var genreID: Int?
    func load(_ genre: Int, client: any MusicExploreCalling) async {
        let token = UUID(); generation = token; genreID = genre
        selection = nil; related = []; nextPage = 0; more = true; failure = false; loading = true
        defer { if token == generation { loading = false } }
        do {
            let value = try await client.selection(genre); try Task.checkCancellation()
            guard token == generation else { return }; selection = value
            let neighbors = try await client.related(genre); try Task.checkCancellation()
            guard token == generation else { return }; related = neighbors.filter { $0.id != 95 }
        } catch is CancellationError { }
        catch { if token == generation, !Task.isCancelled { failure = true } }
    }
    func loadNext(client: any MusicExploreCalling) async {
        guard !loading, more, let genreID, let initial = selection else { return }
        let token = generation; loading = true; failure = false
        defer { if token == generation { loading = false } }
        do {
            let page = try await client.tracks(genreID, page: nextPage); try Task.checkCancellation()
            guard token == generation else { return }
            var trackIDs = Set(initial.tracks.map(\.id)), artistIDs = Set(initial.artists.map(\.id)), albumIDs = Set((initial.albums ?? []).map(\.id))
            var tracks = initial.tracks, positions = initial.positions
            for (index, track) in page.tracks.enumerated() where trackIDs.insert(track.id).inserted {
                tracks.append(track); positions.append(page.positions.indices.contains(index) ? page.positions[index] : nil)
            }
            let freshArtists = page.artists.filter { artistIDs.insert($0.id).inserted }
            let freshAlbums = (page.albums ?? []).filter { albumIDs.insert($0.id).inserted }
            let artists: [MusicCatalogItem] = initial.artists + freshArtists
            let albums: [MusicCatalogItem] = (initial.albums ?? []) + freshAlbums
            var popularity: [String: Double] = initial.popularity ?? [:]
            for (identity, score) in page.popularity ?? [:] { popularity[identity] = max(popularity[identity] ?? 0, score) }
            selection = MusicGenreSelection(tracks: tracks, positions: positions, artists: artists,
                albums: albums, playlists: initial.playlists, popularity: popularity, done: page.done)
            nextPage += 1; more = page.done != true
        } catch is CancellationError { }
        catch { if token == generation, !Task.isCancelled { failure = true } }
    }
}
