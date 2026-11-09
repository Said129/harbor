import SwiftUI

struct ContentPageView: View {
    let app: AppModel
    let kind: String
    let title: String
    @State private var model: ContentPageModel
    @State private var customization: PageCustomization
    @MainActor init(app: AppModel, kind: String, title: String) {
        self.app = app; self.kind = kind; self.title = title; _model = State(initialValue: app.pageModel(kind))
        _customization = State(initialValue: app.pageCustomization(kind))
    }
    private var rails: [PageRail] {
        let curated = kind == "series" ? ShowsCatalog.visible(model.curated, heroIDs: model.seriesHeroIDs) : model.curated
        let catalogs = kind == "series" ? ShowsCatalog.visibleFallback(model.rows, heroIDs: model.seriesHeroIDs) : model.rows
        let rows = curated.map(PageRail.discovery) + catalogs.map(PageRail.catalog)
        guard kind == "anime" else { return rows }
        return PageRail.addingContinuation(to: rows, kind: kind, records: app.library.continuing,
            detectedAnime: app.animeDetection.identifiers, presentationError: app.library.presentationError != nil)
    }
    private var remainingRails: [PageRail] { kind == "anime" ? rails.filter { $0.id != "discovery-anime-picks" } : rails }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                CustomizedHero(rails: rails, defaults: model.heroes, app: app, customization: customization, animeSources: model.heroSources)
                if model.loading && model.rows.isEmpty && model.curated.isEmpty { HarborLoader().frame(maxWidth: .infinity).padding(40) }
                if let error = model.error, model.rows.isEmpty && model.curated.isEmpty {
                    ContentUnavailableView { Label(title, image: kind == "movie" ? "nav-movies" : "nav-shows") } description: { Text(error) } actions: {
                        Button("Reintentar") { Task { ArtworkRefresh.shared.retryFailedImages(); await model.load(kind: kind, app: app, refresh: true) } }
                    }
                }
                PageCustomizeButton(rails: remainingRails, customization: customization, cloud: kind == "anime" && app.harborIdentity.signedIn ? app.harborIdentity.page("anime") : nil)
                if let error = customization.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if kind == "series" { ContinueWatching(app: app, kind: kind, title: "Pick up where you left off") }
                CustomizedRails(rails: remainingRails, app: app, customization: customization,
                                seriesPagination: kind == "series" ? model : nil)
            }.padding(.bottom, 24)
        }.accessibilityIdentifier("content-\(kind)")
            .background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { PageEditingFooter(customization: customization) }
            .task(id: app.continuingDetectionSignature) { await app.detectContinuingAnime() }
            .task(id: "\(app.storageReady)|\(app.accountOperationScope)|\(app.addons.filter(\.enabled).map(\.id).joined())|\(MetadataPreferences.shared.tmdbKey)|\(MetadataPreferences.shared.region)|\(MetadataPreferences.shared.language)|\(MetadataPreferences.shared.translateTitles)") { if app.storageReady { await model.load(kind: kind, app: app) } }
            .onChange(of: app.rows.count) { _, _ in if !["movie", "series"].contains(kind) { Task { await model.load(kind: kind, app: app, refresh: true) } } }
            .onChange(of: app.library.items.map { $0.id + $0.modified }) { _, _ in if kind == "anime" { Task { await model.refreshAnimePicks(app: app) } } }
            .onChange(of: AnimePicksPreferences.shared.options) { _, _ in if kind == "anime" { Task { await model.refreshAnimePicks(app: app) } } }
            .refreshable { ArtworkRefresh.shared.retryFailedImages(); await model.load(kind: kind, app: app, refresh: true) }
    }
}

struct CinemaHero: View {
    let metas: [Media]
    let app: AppModel
    var playSquare = true
    var moreInfo = true
    var customList: CustomList? = nil
    var homeRanks: [String: HomeHeroRank]? = nil
    @State private var selected = 0
    @State private var showsRanking = false
    @State private var nearViewport = true
    @State private var hovering = false
    @GestureState private var dragging = false
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key, language: locale.identifier) }
    private let layout = HeroLayoutPreferences.shared
    private var shadeColors: [Color] {
        [.black.opacity(HeroLayoutPolicy.topStopOpacity), HarborTheme.background.opacity(HeroLayoutPolicy.middleStopOpacity(shadowPercent: layout.shadowPercent)), HarborTheme.background]
    }
    private func heroHeight(_ container: CGFloat) -> CGFloat { HeroLayoutPolicy.heroHeight(full: layout.full, container: container) }
    private var slideCount: Int { min(5, metas.count) }
    private var rotatingSlides: Int {
        CinemaHeroRotation.canAdvance(count: slideCount, visible: nearViewport, foreground: scenePhase == .active,
                                      interacting: dragging || hovering || showsRanking) ? slideCount : 0
    }

    private func move(to index: Int) {
        withAnimation(reduceMotion ? nil : .timingCurve(0.32, 0.72, 0.24, 1, duration: 0.7)) { selected = index }
    }
    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $selected) {
                ForEach(Array(metas.prefix(5).enumerated()), id: \.element.identity) { index, media in
                    GeometryReader { geometry in
                        ZStack(alignment: .bottomLeading) {
                            CustomListArtwork(media: media, url: TitleArtworkPreferences.shared.value(.backdrop, id: media.artworkID) ?? media.background ?? (media.type == "manga" ? media.poster : nil),
                                fallback: media.fallbackBackground, fallbacks: [TitleArtworkPreferences.shared.value(.poster, id: media.artworkID), media.poster].compactMap { $0 }, maxPixels: HeroLayoutPolicy.artworkMaxPixels(fullQuality: layout.fullQuality))
                                .frame(width: geometry.size.width, height: geometry.size.height).accessibilityHidden(true)
                            HeroTrailerBackdrop(videoID: HeroTrailerPolicy.trailerID(in: media.details?.trailers ?? []), placement: .hero, slideActive: selected == index && !dragging && nearViewport)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            LinearGradient(colors: shadeColors, startPoint: .top, endPoint: .bottom).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 14) {
                                if let homeRanks {
                                    HomeHeroRankBadge(rank: homeRanks[media.id] ?? .fallback(for: media, index: index),
                                                      presented: index == selected ? $showsRanking : .constant(false))
                                } else {
                                    Text(text("Featured tonight").uppercased(with: locale)).font(HarborTheme.font(9, weight: .semibold)).tracking(4).foregroundStyle(.white.opacity(0.5))
                                        .accessibilityIdentifier("hero-eyebrow")
                                }
                                HarborHeroTitle(media: media, size: 30, height: 76)
                                HStack(spacing: 14) {
                                    if let year = media.releaseInfo { Text(year).foregroundStyle(.secondary) }
                                    if let rating = media.imdbRating { HStack(spacing: 5) { Text(media.ratingSource ?? "IMDb").font(.system(size: 9, weight: .black)).foregroundStyle(.black).padding(3).background(.yellow, in: .rect(cornerRadius: 2)); Text(rating).fontWeight(.semibold) } }
                                    if let runtime = media.runtime { Text(runtime).foregroundStyle(.secondary) }
                                }.font(.caption)
                                if let description = media.description { Text(description).font(.subheadline).foregroundStyle(.white.opacity(0.72)).lineLimit(3) }
                                HStack(spacing: 10) {
                                    NavigationLink { destination(media, play: true) } label: {
                                        Group {
                                            if media.type == "manga" { Label(text("Read"), systemImage: "book") }
                                            else { Label(text("Play"), image: "ui-play-filled") }
                                        }.font(HarborTheme.font(14, weight: .semibold)).padding(.horizontal, 18).padding(.vertical, 13).foregroundStyle(.black).background(.white, in: .rect(cornerRadius: playSquare ? 8 : 24))
                                    }
                                        .buttonStyle(.plain).accessibilityIdentifier("hero-play")
                                    if moreInfo || media.type == "manga" {
                                        NavigationLink { destination(media, play: false) } label: { Label(text("More info"), image: "desktop-info").font(HarborTheme.font(14, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 13).background(.black.opacity(0.3), in: .rect(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityIdentifier("hero-more-info")
                                    } else {
                                        Button { Task { await app.library.toggleBookmark(media) } } label: { Label(text(app.library.bookmarked(media) ? "In Watchlist" : "Add to Watchlist"), image: "desktop-bookmark").font(HarborTheme.font(14, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 13) }.buttonStyle(.plain).disabled(app.library.busy || app.library.loading).accessibilityIdentifier("hero-bookmark")
                                    }
                                }
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }.tag(index).accessibilityElement(children: .contain).accessibilityIdentifier(index == 0 ? "home-hero" : "hero-page-\(index)")
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).containerRelativeFrame(.vertical) { length, _ in heroHeight(length) }
                .simultaneousGesture(DragGesture(minimumDistance: 6).updating($dragging) { value, state, _ in
                    state = abs(value.translation.width) >= abs(value.translation.height)
                }, including: slideCount > 1 ? .all : .none)
            if metas.count > 1 {
                HStack(spacing: 7) {
                    ForEach(0..<slideCount, id: \.self) { index in
                        Button { move(to: index) } label: { Capsule().fill(selected == index ? .white : .white.opacity(0.3)).frame(width: selected == index ? 24 : 7, height: 4).frame(minHeight: 24) }.accessibilityLabel("Destacado \(index + 1)")
                    }
                }
            }
            if !moreInfo, let error = app.library.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
        }
        .onHover { hovering = $0 }
        .onGeometryChange(for: Bool.self) { proxy in
            guard let bounds = proxy.bounds(of: .scrollView) else { return true }
            let viewport = CGRect(origin: .zero, size: bounds.size).insetBy(dx: -100, dy: -100)
            return proxy.frame(in: .scrollView).intersects(viewport)
        } action: { nearViewport = $0 }
        .onChange(of: metas.map(\.identity)) { _, _ in
            showsRanking = false
            if selected >= slideCount { selected = 0 }
        }
        .onChange(of: selected) { _, _ in showsRanking = false }
        .task(id: rotatingSlides) {
            let count = rotatingSlides
            guard count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: CinemaHeroRotation.interval)
                guard !Task.isCancelled, rotatingSlides == count else { return }
                move(to: CinemaHeroRotation.next(after: selected, count: count))
            }
        }
    }
    @ViewBuilder private func destination(_ media: Media, play: Bool) -> some View {
        if media.type == "manga", let customList, let item = customList.items.first(where: { $0.id == media.id }) {
            CustomListItemDestination(app: app, item: item, listID: customList.id, playImmediately: play)
        } else { DetailView(media: media, app: app, playImmediately: play) }
    }
}

private struct HomeHeroRankBadge: View {
    let rank: HomeHeroRank
    @Binding var presented: Bool
    @Environment(\.locale) private var locale

    private func text(_ key: String, variables: [String: String] = [:]) -> String {
        DesktopInterfaceText.value(key, variables: variables, language: locale.identifier)
    }

    private var title: String {
        text("#{position} in {label} Today", variables: ["position": String(rank.position), "label": text(rank.label)])
    }

    private var label: some View {
        Label(title, systemImage: "chart.line.uptrend.xyaxis")
            .font(HarborTheme.font(12, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(.white)
            .background(HarborTheme.background.opacity(0.85), in: .rect(cornerRadius: 6))
    }

    var body: some View {
        Group {
            if rank.sources.isEmpty {
                label.accessibilityElement(children: .ignore).accessibilityLabel(title)
            } else {
                Button { presented = true } label: { label }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityHint(text("Consensus ranking"))
                    .popover(isPresented: $presented, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(text("Consensus ranking")).font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(Array(rank.sources.enumerated()), id: \.offset) { _, source in
                                HStack(spacing: 14) {
                                    if let icon = icon(for: source.label) {
                                        Image(icon).resizable().scaledToFit().frame(width: 18, height: 18)
                                            .accessibilityHidden(true)
                                    }
                                    Text(text(source.label))
                                    Spacer(minLength: 8)
                                    Text("#\(source.position)").monospacedDigit()
                                }.font(HarborTheme.font(13, weight: .medium))
                            }
                        }.frame(minWidth: 160).padding(14)
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }.accessibilityIdentifier("hero-eyebrow")
    }

    private func icon(for source: String) -> String? {
        switch source {
        case "Cinemeta": "metadata-cinemeta"
        case "TMDB": "metadata-tmdb"
        case "Trakt": "tracker-trakt"
        case "Simkl": "tracker-simkl"
        default: nil
        }
    }
}
