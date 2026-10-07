import SwiftUI
import Observation

struct DesktopVoyage: Decodable, Identifiable, Sendable {
    let id: String
    let label: String
    let tagline: String
    let genre: String?
    let backdrop: String?
    let seeds: [String]
    static let all: [DesktopVoyage] = {
        struct Catalog: Decodable { let themes: [DesktopVoyage] }
        guard let url = Bundle.main.url(forResource: "DesktopVoyages", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode(Catalog.self, from: data).themes) ?? []
    }()
}

@MainActor @Observable
final class DiscoverModel {
    var recommended: [Media] = []
    var trending: [Media] = []
    var topRated: [Media] = []
    var awards: [Media] = []
    var loading = false
    var error: String?
    private var generation = 0
    private var signature = ""
    func refreshRecommendations(app: AppModel) {
        var seen = Set<String>()
        let watched = Set(app.library.items.filter(\.watched).map(\.id))
        let pool = (app.rows.flatMap(\.metas) + trending).filter { ["movie", "series"].contains($0.type) && !watched.contains($0.id) && seen.insert($0.identity).inserted }
        recommended = Array(pool.prefix(8))
    }
    func load(app: AppModel, refresh: Bool = false) async {
        let configuration = MetadataPreferences.shared.configuration()
        let currentSignature = configuration.tmdbKey + configuration.language + (app.user?.id ?? "guest")
        guard !loading, refresh || signature != currentSignature else { return }
        generation += 1; let current = generation
        loading = true; error = nil
        defer { if current == generation { loading = false } }
        refreshRecommendations(app: app)
        if !configuration.tmdbKey.isEmpty {
            let definitions = [DiscoveryRail(id: "discover-trending", title: "Trending This Week", kind: "movie", path: "trending/movie/week"), DiscoveryRail(id: "discover-rated", title: "Top Rated", kind: "movie", path: "discover/movie", parameters: ["vote_average.gte": "8.0", "vote_count.gte": "1000", "with_runtime.gte": "70", "sort_by": "vote_average.desc"])]
            for rail in definitions {
                do {
                    let items = try await TMDBService().page(rail, page: 1, configuration: configuration)
                    try Task.checkCancellation(); guard current == generation else { return }
                    if rail.id == "discover-trending" { trending = items; refreshRecommendations(app: app) }
                    else { topRated = items }
                } catch is CancellationError { return } catch { self.error = safeMessage(error) }
            }
        }
        do {
            struct Winners: Decodable { struct Entry: Decodable { let id: String; let title: String }; let winners: [Entry] }
            guard let url = Bundle.main.url(forResource: "DesktopFilmAwards", withExtension: "json") else { throw HarborError(code: "awards-catalog") }
            let winners = try JSONDecoder().decode(Winners.self, from: Data(contentsOf: url)).winners
            var items: [(Int, Media)] = []
            let service = app.service; let addons = app.addons
            for start in stride(from: 0, to: min(24, winners.count), by: 4) {
                try Task.checkCancellation()
                let batch = winners[start..<min(start + 4, min(24, winners.count))]
                await withTaskGroup(of: (Int, Media?).self) { group in
                    for (index, item) in batch.enumerated() {
                        let media = Media(id: item.id, type: "movie", name: item.title)
                        group.addTask { (start + index, try? await service.metadata(media, addons: addons)) }
                    }
                    for await (index, media) in group { if let media { items.append((index, media)) } }
                }
                guard current == generation else { return }
                awards = items.sorted { $0.0 < $1.0 }.map(\.1)
            }
        } catch is CancellationError { return } catch { self.error = safeMessage(error) }
        if !recommended.isEmpty || !awards.isEmpty { signature = currentSignature }
    }
}

struct DiscoverView: View {
    let app: AppModel
    @State private var model = DiscoverModel()
    @State private var kind = "movie"
    @State private var catalog = ""
    @State private var genre = ""
    @State private var length = 5
    @State private var surprise: Media?
    @State private var lastSurprise: String?
    private var catalogs: [CatalogRow] { app.rows.filter { !$0.plan.isPlaybackHistoryCatalog && $0.plan.catalog != nil && (kind == "anime" ? $0.isAnimeCatalog : $0.plan.kind == kind && !$0.isAnimeCatalog) } }
    private var selected: CatalogRow? { catalogs.first { $0.id == catalog } ?? catalogs.first }
    private var genres: [String] { selected?.plan.catalog?.extra.first { $0.name == "genre" }?.options ?? [] }
    private var pool: [Media] { var seen = Set<String>(); return (model.recommended + model.trending + model.awards + app.rows.flatMap(\.metas)).filter { seen.insert($0.identity).inserted } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !model.recommended.isEmpty {
                    Text("Recommended").font(HarborTheme.displayFont(28)).padding(.horizontal)
                    DiscoverFeatured(items: model.recommended, app: app)
                }
                catalogBrowser
                surpriseChooser
                voyageChooser
                if !model.trending.isEmpty { shelf("Trending This Week", items: model.trending) }
                genreTiles
                if !model.topRated.isEmpty { shelf("Top Rated", items: model.topRated) }
                queue
                if !model.awards.isEmpty { shelf("Award Winning", items: model.awards) }
                if model.loading { ProgressView().frame(maxWidth: .infinity) }
                if let error = model.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange).padding(.horizontal); Button("Reintentar") { Task { await model.load(app: app, refresh: true) } }.padding(.horizontal) }
            }.padding(.top, 20).padding(.bottom, 32)
        }.background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("discover-original")
            .task(id: app.storageReady) { if app.storageReady { await model.load(app: app) } }
            .refreshable { await model.load(app: app, refresh: true) }
            .onChange(of: kind) { _, _ in catalog = ""; genre = "" }
            .onChange(of: catalog) { _, _ in genre = "" }
            .onChange(of: app.rows.flatMap(\.metas).map(\.identity)) { _, _ in model.refreshRecommendations(app: app) }
            .onChange(of: app.library.items.filter(\.watched).map(\.id)) { _, _ in model.refreshRecommendations(app: app) }
            .navigationDestination(item: $surprise) { DetailView(media: $0, app: app) }
    }
    private var catalogBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browse your catalogs").font(HarborTheme.font(17, weight: .semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Menu { ForEach([("Movies", "movie"), ("Series", "series"), ("Anime", "anime")], id: \.1) { name, value in Button(name) { kind = value } } } label: { control("TYPE", value: kind == "movie" ? "Movies" : kind == "series" ? "Series" : "Anime") }
                    Menu { ForEach(catalogs) { row in Button(row.plan.addon.name + " · " + row.plan.title) { catalog = row.id } } } label: { control("CATALOG", value: selected?.plan.title ?? "Catalogs") }
                    Menu { Button("All genres") { genre = "" }; ForEach(genres, id: \.self) { value in Button(value) { genre = value } } } label: { control("GENRE", value: genre.isEmpty ? "All genres" : genre) }
                    if let row = selected {
                        NavigationLink {
                            CatalogBrowserView(app: app, initial: withGenre(row))
                        } label: { Text("Browse").font(HarborTheme.font(13, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 20).frame(height: 44).background(.white, in: .capsule) }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
        }.padding(.horizontal)
    }
    private func withGenre(_ row: CatalogRow) -> CatalogRow {
        CatalogRow(plan: row.plan, metas: genre.isEmpty ? row.metas : [], selectedGenre: genre.isEmpty ? nil : genre, receivedCount: genre.isEmpty ? row.receivedCount : 0)
    }
    private var surpriseChooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("¿No puedes decidirte?").font(HarborTheme.font(17, weight: .semibold))
            Button {
                let candidates = pool.filter { $0.identity != lastSurprise }
                guard let pick = (candidates.isEmpty ? pool : candidates).randomElement() else { return }
                lastSurprise = pick.identity; surprise = pick
            } label: {
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) { ForEach(Array(pool.prefix(18)), id: \.identity) { media in Artwork(url: media.poster, fallback: media.fallbackPoster, maxPixels: 120) } }.accessibilityHidden(true)
                    LinearGradient(colors: [HarborTheme.background, HarborTheme.background.opacity(0.85), HarborTheme.background.opacity(0.3)], startPoint: .leading, endPoint: .trailing).allowsHitTesting(false)
                    HStack(spacing: 12) {
                        Image("desktop-dices").resizable().scaledToFit().frame(width: 18, height: 18).foregroundStyle(HarborTheme.background).frame(width: 36, height: 36).background(HarborTheme.ink, in: .circle)
                        VStack(alignment: .leading, spacing: 3) { Text("Sorpréndeme").font(HarborTheme.font(14, weight: .semibold)); Text("Elige un título al azar").font(HarborTheme.font(12)).foregroundStyle(.secondary) }
                    }.padding(16)
                }.frame(height: 76).clipShape(.rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(pool.isEmpty).accessibilityIdentifier("discover-surprise")
        }.padding(.horizontal)
    }
    private func control(_ label: String, value: String) -> some View {
        HStack(spacing: 8) { Text(label).font(HarborTheme.font(9, weight: .semibold)).tracking(1).foregroundStyle(.secondary); Text(value).font(HarborTheme.font(13, weight: .medium)).lineLimit(1); Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 12, height: 12).rotationEffect(.degrees(90)) }
            .padding(.horizontal, 12).frame(minHeight: 44).background(HarborTheme.surface, in: .capsule)
    }
    private var voyageChooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NEW VOYAGE").font(HarborTheme.font(10, weight: .semibold)).tracking(2).foregroundStyle(HarborTheme.accent)
            Text("Where to today?").font(HarborTheme.displayFont(28))
            Text("Pick a direction. You steer from there, one film at a time.").font(HarborTheme.font(13)).foregroundStyle(.secondary)
            HStack(spacing: 6) { Text("How many films?").font(HarborTheme.font(12)).foregroundStyle(.secondary); Spacer(); ForEach([3, 5, 7], id: \.self) { count in HarborPill(title: String(count), selected: count == length) { withAnimation(.easeInOut(duration: 0.2)) { length = count } } } }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(DesktopVoyage.all) { theme in
                    NavigationLink { VoyageRouteView(theme: theme, count: length, app: app) } label: {
                        ZStack(alignment: .bottomLeading) {
                            Artwork(url: theme.backdrop, maxPixels: 500).accessibilityHidden(true)
                            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 5) { if let genre = theme.genre { Text(genre.uppercased()).font(HarborTheme.font(9, weight: .semibold)).tracking(1).foregroundStyle(HarborTheme.accent) }; Text(theme.label).font(HarborTheme.font(14, weight: .semibold)); Text(theme.tagline).font(HarborTheme.font(11)).foregroundStyle(.white.opacity(0.7)).lineLimit(2) }.padding(12)
                        }.frame(height: 140).clipShape(.rect(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal)
    }
    private var genreTiles: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Browse by Genre").font(HarborTheme.font(19, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(["Action", "Drama", "Comedy", "Horror", "Sci-Fi", "Romance"], id: \.self) { name in
                    if let row = app.rows.first(where: { $0.plan.kind == "movie" && $0.plan.catalog?.extra.contains(where: { $0.name == "genre" && $0.options.contains(name) }) == true }) {
                        NavigationLink { CatalogBrowserView(app: app, initial: CatalogRow(plan: row.plan, metas: [], selectedGenre: name, receivedCount: 0)) } label: {
                            ZStack(alignment: .bottomLeading) { Artwork(url: row.metas.first(where: { $0.genres?.contains(name) == true })?.background, maxPixels: 500); LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom); Text(name).font(HarborTheme.displayFont(22)).padding(14) }.frame(height: 90).clipShape(.rect(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(.horizontal)
    }
    private var queue: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Discovery Queue").font(HarborTheme.displayFont(27))
            NavigationLink { DiscoveryQueueView(items: pool, app: app) } label: {
                ZStack(alignment: .trailing) {
                    HStack(spacing: 0) { ForEach(Array(pool.prefix(5)), id: \.identity) { item in Artwork(url: item.background ?? item.poster, fallback: item.fallbackBackground, maxPixels: 350) } }.accessibilityHidden(true)
                    LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                    Label("Explore", image: "desktop-chevron-right").font(HarborTheme.displayFont(30)).padding(20)
                }.frame(height: 118).clipShape(.rect(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(pool.isEmpty)
        }.padding(.horizontal)
    }
    private func shelf(_ title: String, items: [Media]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(HarborTheme.font(18, weight: .semibold)).padding(.horizontal)
            ScrollView(.horizontal) { LazyHStack(alignment: .top, spacing: 12) { ForEach(items, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain) } }.padding(.horizontal) }.scrollIndicators(.hidden)
        }
    }
}

private struct DiscoverFeatured: View {
    let items: [Media]
    let app: AppModel
    @State private var selected = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TabView(selection: $selected) {
                ForEach(Array(items.prefix(8).enumerated()), id: \.element.identity) { index, item in
                    NavigationLink(value: item) {
                        ZStack(alignment: .topLeading) { Artwork(url: item.background, fallback: item.fallbackBackground, fallbacks: [item.poster].compactMap { $0 }, maxPixels: 1100); Text("FEATURED").font(HarborTheme.font(10, weight: .semibold)).tracking(1).padding(8).background(.black.opacity(0.5), in: .capsule).padding(16) }.clipShape(.rect(cornerRadius: 15)).padding(.horizontal)
                    }.buttonStyle(.plain).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .automatic)).frame(height: 225)
            if !items.isEmpty {
                let item = items[min(selected, items.count - 1)]
                NavigationLink(value: item) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name).font(HarborTheme.displayFont(25))
                        if let year = item.releaseInfo { Text(year).font(HarborTheme.font(12)).foregroundStyle(.secondary) }
                        if let description = item.description { Text(description).font(HarborTheme.font(14)).foregroundStyle(.secondary).lineLimit(3) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).padding(.horizontal)
            }
        }.onChange(of: items.map(\.identity)) { _, _ in if selected >= items.count { selected = 0 } }
    }
}

private struct VoyageRouteView: View {
    let theme: DesktopVoyage
    let count: Int
    let app: AppModel
    @State private var items: [Media] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(theme.label).font(HarborTheme.displayFont(30)); Text(theme.tagline).font(HarborTheme.font(14)).foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                    NavigationLink(value: item) { HStack(alignment: .top, spacing: 16) { Text(String(index + 1)).font(HarborTheme.displayFont(32)).foregroundStyle(HarborTheme.accent); Poster(media: item, width: 110); VStack(alignment: .leading, spacing: 8) { Text(item.name).font(HarborTheme.font(17, weight: .semibold)); if let text = item.description { Text(text).font(HarborTheme.font(13)).foregroundStyle(.secondary).lineLimit(5) } } } }.buttonStyle(.plain)
                }
                if loading { ProgressView() }; if let error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange); Button("Reintentar") { Task { await load() } } }
            }.padding()
        }.background(HarborTheme.background).navigationTitle(theme.label).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .task { if items.isEmpty { await load() } }
    }
    private func load() async {
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        let watched = Set(app.library.items.filter(\.watched).map(\.id))
        for id in theme.seeds.filter({ !watched.contains($0) }).shuffled() {
            if items.count >= count { break }
            do { let response = try await HTTPClient().json("https://v3-cinemeta.strem.io/meta/movie/\(id).json"); try Task.checkCancellation(); if let media = Media.parse(response["meta"], kind: "movie"), !items.contains(where: { $0.id == media.id }) { items.append(media) } }
            catch is CancellationError { return } catch { continue }
        }
        if items.count < count { error = "That route wouldn't chart. Try a different direction." }
    }
}

private struct DiscoveryQueueView: View {
    let items: [Media]
    let app: AppModel
    @State private var index = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Your Discovery Queue").font(HarborTheme.displayFont(30))
                if items.indices.contains(index) {
                    let media = items[index]
                    CinemaHero(metas: [media], app: app)
                    Text("\(index + 1) / \(items.count)").font(HarborTheme.font(13)).foregroundStyle(.secondary)
                    HStack { Button("Previous") { if index > 0 { index -= 1 } }.disabled(index == 0); Spacer(); Button("Next") { if index + 1 < items.count { index += 1 } }.disabled(index + 1 >= items.count) }.buttonStyle(HarborAccountButtonStyle())
                }
            }.padding(.vertical, 20)
        }.background(HarborTheme.background).navigationTitle("Explore").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}
