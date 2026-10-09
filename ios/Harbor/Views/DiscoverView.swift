import SwiftUI
import Observation

struct DesktopVoyage: Decodable, Identifiable, Sendable {
    let id: String
    let label: String
    let tagline: String
    let genre: String?
    let backdrop: String?
    let seeds: [String]
    static func copy(_ key: String) -> String { spanish[key] ?? key }
    private static let spanish: [String: String] = {
        guard let url = Bundle.main.url(forResource: "DesktopDiscoverSpanish", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()
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
    private var owner: String?
    func synchronizeOwner(_ value: String) {
        guard owner != value else { return }
        owner = value; generation += 1; signature = ""; loading = false; error = nil
        recommended = []; trending = []; topRated = []; awards = []
    }
    func refreshRecommendations(app: AppModel) {
        var pool = app.rows.filter { !$0.plan.isPlaybackHistoryCatalog }.flatMap(\.metas).enumerated().map { FeaturedRanking.Candidate(media: $0.element, source: .seed, rank: $0.offset) }
        pool += trending.enumerated().map { FeaturedRanking.Candidate(media: $0.element, source: .trending, rank: $0.offset) }
        pool += topRated.enumerated().map { FeaturedRanking.Candidate(media: $0.element, source: .tmdb, rank: $0.offset) }
        pool += awards.enumerated().map { FeaturedRanking.Candidate(media: $0.element, source: .awards, rank: $0.offset) }
        let excluded = app.library.items.filter { $0.watched || $0.continuing }.compactMap(\.media)
        recommended = FeaturedRanking.select(pool, preferences: app.library.discovery, excluded: excluded)
    }
    func load(app: AppModel, refresh: Bool = false) async {
        synchronizeOwner(app.library.owner)
        let owner = app.library.owner
        let configuration = MetadataPreferences.shared.configuration()
        let currentSignature = configuration.tmdbKey + configuration.language + owner
        guard !loading, refresh || signature != currentSignature else { return }
        generation += 1; let current = generation
        loading = true; error = nil
        defer { if current == generation { loading = false } }
        refreshRecommendations(app: app)
        if !configuration.tmdbKey.isEmpty {
            let definitions = [DiscoveryRail(id: "discover-trending", title: DesktopVoyage.copy("Trending This Week"), kind: "movie", path: "trending/movie/week"), DiscoveryRail(id: "discover-rated", title: DesktopVoyage.copy("Top Rated"), kind: "movie", path: "discover/movie", parameters: ["vote_average.gte": "8.0", "vote_count.gte": "1000", "with_runtime.gte": "70", "sort_by": "vote_average.desc"])]
            for rail in definitions {
                do {
                    let items = try await TMDBService().page(rail, page: 1, configuration: configuration)
                    try Task.checkCancellation(); guard current == generation, owner == app.library.owner else { return }
                    if rail.id == "discover-trending" { trending = items; refreshRecommendations(app: app) }
                    else { topRated = items; refreshRecommendations(app: app) }
                } catch is CancellationError { return } catch { if current == generation, owner == app.library.owner { self.error = safeMessage(error) } }
            }
        } else { trending = []; topRated = [] }
        guard current == generation, owner == app.library.owner else { return }
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
                try Task.checkCancellation(); guard current == generation, owner == app.library.owner else { return }
                awards = items.sorted { $0.0 < $1.0 }.map(\.1)
                refreshRecommendations(app: app)
            }
        } catch is CancellationError { return } catch { if current == generation, owner == app.library.owner { self.error = safeMessage(error) } }
        if !recommended.isEmpty || !awards.isEmpty { signature = currentSignature }
    }
}

struct DiscoverView: View {
    private struct VoteUndo { let media: Media; let previous: DiscoveryPreferences.Entry?; let expected: DiscoveryPreferences.Entry? }
    let app: AppModel
    @State private var model = DiscoverModel()
    @State private var kind = "movie"
    @State private var catalog = ""
    @State private var genre = ""
    @State private var length = 5
    @State private var surprise: Media?
    @State private var lastSurprise: String?
    @State private var voteUndo: VoteUndo?
    @Environment(\.scenePhase) private var scenePhase
    private var catalogs: [CatalogRow] { app.rows.filter { !$0.plan.isPlaybackHistoryCatalog && $0.plan.catalog != nil && (kind == "anime" ? $0.isAnimeCatalog : $0.plan.kind == kind && !$0.isAnimeCatalog) } }
    private var selected: CatalogRow? { catalogs.first { $0.id == catalog } ?? catalogs.first }
    private var genres: [String] { selected?.plan.catalog?.extra.first { $0.name == "genre" }?.options ?? [] }
    private var pool: [Media] { var seen = Set<String>(); return (model.recommended + model.trending + model.awards + app.rows.filter { !$0.plan.isPlaybackHistoryCatalog }.flatMap(\.metas)).filter { ["movie", "series"].contains($0.type) && !$0.id.isEmpty && seen.insert($0.identity).inserted } }
    private var queueItems: [Media] {
        let watched = Set(app.library.items.filter { $0.watched || $0.continuing }.map(\.id))
        return pool.filter { ["movie", "series"].contains($0.type) && !watched.contains($0.id) && app.library.discovery.vote(for: $0) == nil && !app.library.discovery.isQueueItemHidden($0.id) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !model.recommended.isEmpty {
                    Text(DesktopVoyage.copy("Recommended")).font(HarborTheme.displayFont(28)).padding(.horizontal)
                    DiscoverFeatured(items: model.recommended, app: app) { media, previous, expected in voteUndo = VoteUndo(media: media, previous: previous, expected: expected) }
                }
                catalogBrowser
                surpriseChooser
                voyageChooser
                if !model.trending.isEmpty { shelf(DesktopVoyage.copy("Trending This Week"), items: model.trending) }
                genreTiles
                if !model.topRated.isEmpty { shelf(DesktopVoyage.copy("Top Rated"), items: model.topRated) }
                if !queueItems.isEmpty { queue }
                if !model.awards.isEmpty { shelf("Award Winning", items: model.awards) }
                if model.loading { ProgressView().frame(maxWidth: .infinity) }
                if let error = model.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange).padding(.horizontal); Button(DesktopInterfaceText.value("Retry")) { Task { await model.load(app: app, refresh: true) } }.padding(.horizontal) }
                if let error = app.library.discovery.error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange).padding(.horizontal) }
            }.padding(.top, 20).padding(.bottom, 32)
        }.background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .accessibilityIdentifier("discover-original")
            .task(id: "\(app.storageReady)|\(app.library.owner)") { if app.storageReady { await model.load(app: app) } }
            .refreshable { await model.load(app: app, refresh: true) }
            .onChange(of: kind) { _, _ in catalog = ""; genre = "" }
            .onChange(of: catalog) { _, _ in genre = "" }
            .onChange(of: app.rows.flatMap(\.metas).map(\.identity)) { _, _ in model.refreshRecommendations(app: app) }
            .onChange(of: app.library.items.filter(\.watched).map(\.id)) { _, _ in model.refreshRecommendations(app: app) }
            .onChange(of: app.library.continuing.map(\.id)) { _, _ in model.refreshRecommendations(app: app) }
            .onChange(of: app.library.discovery.revision) { _, _ in model.refreshRecommendations(app: app) }
            .onChange(of: app.library.owner) { _, owner in voteUndo = nil; model.synchronizeOwner(owner); model.refreshRecommendations(app: app) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshRecommendations(app: app) } }
            .safeAreaInset(edge: .bottom) {
                if let change = voteUndo {
                    HStack(spacing: 12) {
                        Text(change.media.name).font(HarborTheme.font(13)).lineLimit(2)
                        Spacer(minLength: 0)
                        Button(DesktopVoyage.copy("Undo")) {
                            if app.library.discovery.restoreVote(for: change.media.id, expected: change.expected, previous: change.previous) { voteUndo = nil }
                        }.font(HarborTheme.font(13, weight: .semibold)).frame(minHeight: 44)
                    }.padding(.horizontal, 16).padding(.vertical, 4).background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 12)).padding(.horizontal).padding(.bottom, 8)
                }
            }
            .navigationDestination(item: $surprise) { DetailView(media: $0, app: app) }
    }
    private var catalogBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DesktopVoyage.copy("Browse your catalogs")).font(HarborTheme.font(17, weight: .semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Menu { ForEach([("Películas", "movie"), ("Series", "series"), ("Anime", "anime")], id: \.1) { name, value in Button(name) { kind = value } } } label: { control(DesktopVoyage.copy("Type").uppercased(), value: DesktopVoyage.copy(kind == "movie" ? "Movies" : kind == "series" ? "Series" : "Anime")) }
                    Menu { ForEach(catalogs) { row in Button(row.plan.addon.name + " · " + row.plan.title) { catalog = row.id } } } label: { control(DesktopVoyage.copy("Catalog").uppercased(), value: selected?.plan.title ?? DesktopVoyage.copy("Catalog")) }
                    Menu { Button(DesktopVoyage.copy("All genres")) { genre = "" }; ForEach(genres, id: \.self) { value in Button(DesktopVoyage.copy(value)) { genre = value } } } label: { control(DesktopVoyage.copy("Genre").uppercased(), value: genre.isEmpty ? DesktopVoyage.copy("All genres") : DesktopVoyage.copy(genre)) }
                    if let row = selected {
                        NavigationLink {
                            CatalogBrowserView(app: app, initial: withGenre(row))
                        } label: { Text(DesktopVoyage.copy("Browse")).font(HarborTheme.font(13, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 20).frame(height: 44).background(.white, in: .capsule) }.buttonStyle(.plain)
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
            Text(DesktopVoyage.copy("Can't decide?")).font(HarborTheme.font(17, weight: .semibold))
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
                        VStack(alignment: .leading, spacing: 3) { Text(DesktopVoyage.copy("Surprise me")).font(HarborTheme.font(14, weight: .semibold)); Text(DesktopVoyage.copy("Pick a random title")).font(HarborTheme.font(12)).foregroundStyle(.secondary) }
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
            Text(DesktopVoyage.copy("New voyage").uppercased()).font(HarborTheme.font(10, weight: .semibold)).tracking(2).foregroundStyle(HarborTheme.accent)
            Text(DesktopVoyage.copy("Where to today?")).font(HarborTheme.displayFont(28))
            Text(DesktopVoyage.copy("Pick a direction. You steer from there, one film at a time.")).font(HarborTheme.font(13)).foregroundStyle(.secondary)
            HStack(spacing: 6) { Text(DesktopVoyage.copy("How many films?")).font(HarborTheme.font(12)).foregroundStyle(.secondary); Spacer(); ForEach([3, 5, 7], id: \.self) { count in HarborPill(title: String(count), selected: count == length) { withAnimation(.easeInOut(duration: 0.2)) { length = count } } } }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(DesktopVoyage.all) { theme in
                    NavigationLink { VoyageRouteView(theme: theme, count: length, app: app) } label: {
                        ZStack(alignment: .bottomLeading) {
                            Artwork(url: theme.backdrop, maxPixels: 500).accessibilityHidden(true)
                            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 5) { if let genre = theme.genre { Text(DesktopVoyage.copy(genre).uppercased()).font(HarborTheme.font(9, weight: .semibold)).tracking(1).foregroundStyle(HarborTheme.accent) }; Text(DesktopVoyage.copy(theme.label)).font(HarborTheme.font(14, weight: .semibold)); Text(DesktopVoyage.copy(theme.tagline)).font(HarborTheme.font(11)).foregroundStyle(.white.opacity(0.7)).lineLimit(2) }.padding(12)
                        }.frame(height: 140).clipShape(.rect(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
        }.padding(.horizontal)
    }
    private var genreTiles: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DesktopVoyage.copy("Browse by Genre")).font(HarborTheme.font(19, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(["Action", "Drama", "Comedy", "Horror", "Sci-Fi", "Romance"], id: \.self) { name in
                    if let row = app.rows.first(where: { !$0.plan.isPlaybackHistoryCatalog && $0.plan.kind == "movie" && $0.plan.catalog?.extra.contains(where: { $0.name == "genre" && $0.options.contains(name) }) == true }) {
                        NavigationLink { CatalogBrowserView(app: app, initial: CatalogRow(plan: row.plan, metas: [], selectedGenre: name, receivedCount: 0)) } label: {
                            ZStack(alignment: .bottomLeading) { Artwork(url: row.metas.first(where: { $0.genres?.contains(name) == true })?.background, maxPixels: 500); LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom); Text(DesktopVoyage.copy(name)).font(HarborTheme.displayFont(22)).padding(14) }.frame(height: 90).clipShape(.rect(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(.horizontal)
    }
    private var queue: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { queueTitle.fixedSize(); Spacer(minLength: 16); queueCount }
                VStack(alignment: .leading, spacing: 8) { queueTitle; queueCount }
            }
            NavigationLink { DiscoveryQueueView(items: queueItems, app: app) } label: {
                ZStack {
                    GeometryReader { geometry in
                        let peek = Array(queueItems.prefix(6))
                        HStack(spacing: 0) {
                            ForEach(peek, id: \.identity) { item in
                                Artwork(url: item.background ?? item.poster, fallback: item.fallbackBackground, fallbacks: [item.poster].compactMap { $0 }, maxPixels: 350)
                                    .frame(width: geometry.size.width / CGFloat(max(1, peek.count)), height: 190).clipped()
                            }
                        }.brightness(-0.3).scaleEffect(1.12)
                    }.accessibilityHidden(true)
                    HarborTheme.background.opacity(0.44)
                    RadialGradient(colors: [HarborTheme.background.opacity(0.74), .clear], center: .center, startRadius: 0, endRadius: 220)
                    HStack(spacing: 16) {
                        Text(DesktopVoyage.copy("Explore")).font(HarborTheme.displayFont(42))
                        Image("desktop-arrow-right").resizable().scaledToFit().frame(width: 42, height: 42).accessibilityHidden(true)
                    }.foregroundStyle(HarborTheme.ink).shadow(color: .black.opacity(0.7), radius: 15, y: 4)
                }.frame(height: 190).frame(maxWidth: .infinity).clipShape(.rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
            }.buttonStyle(.plain).accessibilityIdentifier("discover-queue")
        }.padding(.horizontal)
    }
    private var queueTitle: some View { Text(DesktopVoyage.copy("Your Discovery Queue")).font(HarborTheme.displayFont(28)).fixedSize(horizontal: false, vertical: true) }
    private var queueCount: some View {
        Text(DesktopVoyage.copy("{count} picks ready").replacingOccurrences(of: "{count}", with: String(queueItems.count)).uppercased())
            .font(HarborTheme.font(12.5)).tracking(2.5).foregroundStyle(ThemePreferences.shared.color("ink-subtle")).fixedSize()
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
    let onVote: (Media, DiscoveryPreferences.Entry?, DiscoveryPreferences.Entry?) -> Void
    @State private var selected = 0
    @State private var enriched: [String: Media] = [:]
    @State private var expandedImage: String?
    @State private var voteHint: String?
    @State private var voteRevision = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var slides: [Media] { Array(items.prefix(10)).map { enriched[$0.identity] ?? $0 } }
    private var current: Media? { slides.indices.contains(selected) ? slides[selected] : slides.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    carousel.frame(minWidth: 420)
                    if let item = current { sidePanel(item).frame(width: 240).padding(.trailing, 16) }
                }
                VStack(spacing: 14) {
                    carousel
                    if let item = current { sidePanel(item).padding(.horizontal) }
                }
            }
            if let item = current { feedback(item).padding(.horizontal) }
            HarborHeroPips(count: slides.count, selected: selected) { jump($0) }
        }.onChange(of: items.map(\.identity)) { _, _ in if selected >= slides.count { selected = 0 } }
            .onChange(of: app.library.owner) { _, _ in enriched = [:]; expandedImage = nil; selected = 0 }
            .task(id: voteRevision) {
                guard voteHint != nil else { return }
                do { try await Task.sleep(for: .seconds(1.8)); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { voteHint = nil } } catch {}
            }
            .task(id: current?.identity) {
                guard let item = current, enriched[item.identity] == nil else { return }
                let owner = app.library.owner
                do {
                    let detailed = try await app.service.metadata(item, addons: app.addons)
                    try Task.checkCancellation()
                    guard owner == app.library.owner else { return }
                    enriched[item.identity] = detailed
                } catch {}
            }
            .task(id: "\(scenePhase == .active)|\(reduceMotion)|\(selected)|\(expandedImage != nil)|\(slides.map(\.identity).joined())") {
                guard scenePhase == .active, !reduceMotion, slides.count > 1, expandedImage == nil else { return }
                do { try await Task.sleep(for: .seconds(14)); try Task.checkCancellation(); jump((selected + 1) % slides.count) } catch {}
            }
            .sheet(isPresented: Binding(get: { expandedImage != nil }, set: { if !$0 { expandedImage = nil } })) {
                NavigationStack {
                    if let expandedImage {
                        Artwork(url: expandedImage, fit: .fit, maxPixels: 1800).background(.black).navigationTitle(current?.name ?? "")
                            .toolbar { Button(DesktopInterfaceText.value("Close")) { self.expandedImage = nil } }
                    }
                }
            }
    }
    private var carousel: some View {
        TabView(selection: $selected) {
            ForEach(Array(slides.enumerated()), id: \.element.identity) { index, item in
                NavigationLink(value: item) {
                    ZStack(alignment: .topLeading) {
                        Artwork(url: item.background, fallback: item.fallbackBackground, fallbacks: [item.poster].compactMap { $0 }, maxPixels: 1100).accessibilityHidden(true)
                        LinearGradient(colors: [.clear, HarborTheme.background.opacity(0.2), HarborTheme.background.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                        Text(DesktopVoyage.copy("Featured").uppercased()).font(HarborTheme.font(10, weight: .semibold)).tracking(2.2).padding(.horizontal, 10).padding(.vertical, 5).background(.black.opacity(0.55), in: .capsule).padding(20)
                        VStack(alignment: .leading, spacing: 10) {
                            Spacer()
                            HarborHeroTitle(media: item, size: 28, height: 76).frame(maxWidth: 240, alignment: .leading)
                            if let year = item.releaseInfo { Text(year).font(HarborTheme.font(13)).foregroundStyle(.white.opacity(0.8)) }
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    }.clipShape(.rect(cornerRadius: 15)).overlay { RoundedRectangle(cornerRadius: 15).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }.padding(.horizontal)
                }.buttonStyle(.plain).tag(index)
            }
        }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 300)
            .overlay {
                if slides.count > 1 {
                    HStack {
                        carouselArrow("desktop-chevron-left", label: DesktopVoyage.copy("Previous"), step: -1)
                        Spacer()
                        carouselArrow("desktop-chevron-right", label: DesktopVoyage.copy("Next"), step: 1)
                    }.padding(.horizontal, 24)
                }
            }
    }
    private func jump(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.64)) { selected = index }
    }
    private func carouselArrow(_ asset: String, label: String, step: Int) -> some View {
        Button { guard !slides.isEmpty else { return }; jump((selected + step + slides.count) % slides.count) } label: {
            Image(asset).resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44)
                .foregroundStyle(HarborTheme.ink).background(HarborTheme.background.opacity(0.65), in: .circle)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func sidePanel(_ item: Media) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: item) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).font(HarborTheme.displayFont(19)).lineLimit(2)
                    Spacer()
                    Text(String(format: "%02d / %02d", selected + 1, slides.count)).font(HarborTheme.font(12)).tracking(1.6).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            let stills = Array((item.details?.backdrops ?? []).prefix(4))
            let fallback = item.background ?? item.poster
            if !stills.isEmpty || fallback != nil {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(0..<4) { index in
                        let source = stills.indices.contains(index) ? stills[index] : fallback
                        Button { expandedImage = source } label: {
                            Artwork(url: source, maxPixels: 500).aspectRatio(16.0 / 9.0, contentMode: .fit).clipShape(.rect(cornerRadius: 7))
                        }.buttonStyle(.plain).disabled(source == nil).accessibilityLabel(item.name)
                    }
                }
            }
            if let description = item.description { Text(description).font(HarborTheme.font(13)).foregroundStyle(.secondary).lineLimit(3) }
            if let rating = item.imdbRating {
                HStack(spacing: 6) {
                    Text(item.ratingSource ?? "IMDb").font(HarborTheme.font(9, weight: .bold)).foregroundStyle(.black).padding(3).background(item.ratingSource == "TMDB" ? Color.mint : .yellow, in: .rect(cornerRadius: 2))
                    Text(rating).font(HarborTheme.font(12, weight: .semibold))
                }.padding(.horizontal, 10).padding(.vertical, 6).background(HarborTheme.background.opacity(0.4), in: .capsule)
            }
        }.padding(16).background(HarborTheme.surface.opacity(0.35), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.07), lineWidth: 1) }
    }
    private func feedback(_ media: Media) -> some View {
        VStack(alignment: .trailing, spacing: 14) {
            if !app.library.discovery.hintDismissed {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(DesktopVoyage.copy("Tune your recommendations")).font(HarborTheme.font(13, weight: .semibold))
                        Text(DesktopVoyage.copy("Thumbs down hides this title from Featured. Thumbs up helps surface similar picks.")).font(HarborTheme.font(12)).foregroundStyle(.secondary)
                    }
                    Button { app.library.discovery.dismissHint() } label: { Image("desktop-x").resizable().scaledToFit().frame(width: 13, height: 13).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(DesktopVoyage.copy("Dismiss"))
                }.padding(14).background(ThemePreferences.shared.color("elevated").opacity(0.95), in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.1), lineWidth: 1) }
            }
            HStack(spacing: 8) {
                Spacer()
                thumb(.down, media: media)
                thumb(.up, media: media)
            }
        }
    }
    private func thumb(_ vote: DiscoveryPreferences.Vote, media: Media) -> some View {
        let selected = app.library.discovery.vote(for: media) == vote
        let label = DesktopVoyage.copy(vote == .up ? "Show me more like this" : "Show me less like this")
        let color: Color = vote == .up ? .mint : .pink
        return Button {
            let previous = app.library.discovery.votes[media.id]
            if app.library.discovery.toggle(vote, for: media) {
                onVote(media, previous, app.library.discovery.votes[media.id])
                withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) { voteHint = vote.rawValue; voteRevision &+= 1 }
            }
        } label: {
            Image("ui-thumbs-up").resizable().scaledToFit().frame(width: 16, height: 16).rotationEffect(.degrees(vote == .down ? 180 : 0)).frame(width: 44, height: 44)
                .foregroundStyle(selected ? color : HarborTheme.ink.opacity(0.85))
                .background(selected ? color.opacity(0.15) : HarborTheme.background.opacity(0.55), in: .circle)
                .overlay { Circle().stroke(selected ? color.opacity(0.6) : HarborTheme.ink.opacity(0.1), lineWidth: 1) }
        }.buttonStyle(.plain).disabled(!app.library.discovery.ready).accessibilityLabel(label).accessibilityValue(selected ? "Seleccionado" : "")
            .accessibilityIdentifier("discover-vote-" + vote.rawValue)
            .modifier(HarborActionHint(id: vote.rawValue, title: label, selected: voteHint))
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
                Text(DesktopVoyage.copy(theme.label)).font(HarborTheme.displayFont(30)); Text(DesktopVoyage.copy(theme.tagline)).font(HarborTheme.font(14)).foregroundStyle(.secondary)
                ForEach(Array(items.enumerated()), id: \.element.identity) { index, item in
                    NavigationLink(value: item) { HStack(alignment: .top, spacing: 16) { Text(String(index + 1)).font(HarborTheme.displayFont(32)).foregroundStyle(HarborTheme.accent); Poster(media: item, width: 110); VStack(alignment: .leading, spacing: 8) { Text(item.name).font(HarborTheme.font(17, weight: .semibold)); if let text = item.description { Text(text).font(HarborTheme.font(13)).foregroundStyle(.secondary).lineLimit(5) } } } }.buttonStyle(.plain)
                }
                if loading { ProgressView() }; if let error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange); Button(DesktopInterfaceText.value("Retry")) { Task { await load() } } }
            }.padding()
        }.background(HarborTheme.background).navigationTitle(DesktopVoyage.copy(theme.label)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
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
        if items.count < count { error = DesktopVoyage.copy("That route wouldn't chart. Try a different direction.") }
    }
}
