import SwiftUI

@MainActor struct MusicExploreView: View {
    let model: MusicExploreModel
    let catalog: any MusicCatalogCalling
    let billboard: any MusicBillboardCalling
    @Binding var filters: MusicGenreFilters
    @AppStorage("uiLanguage") private var language = "es"
    @State private var revision = 0
    private var locale: Locale { Locale(identifier: InterfaceLanguage.resolve(language)) }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text(text("music.discover")).font(.largeTitle.bold()).padding(.horizontal, 18)
                NavigationLink { MusicBillboardView(client: billboard, catalog: catalog) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) { Text("Billboard").font(.title2.bold()); Text(text("music.row.charts")).font(.subheadline).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "chevron.right")
                    }.padding(18).background(HarborTheme.surface, in: .rect(cornerRadius: 14))
                }.buttonStyle(.plain).padding(.horizontal, 18).accessibilityIdentifier("music-explore-billboard")
                if let chart = model.chart, !chart.tracks.isEmpty {
                    MusicCatalogRail(row: .init(id: "explore:chart", title: "music.row.charts", titleLiteral: false, subtitle: "Deezer", layout: .trackGrid, source: "catalog", items: chart.tracks.map(MusicCatalogItem.track)), client: catalog)
                }
                if model.loading { ProgressView(text("Loading music")).frame(maxWidth: .infinity) }
                if model.chartFailure {
                    Button(text("Retry")) { revision += 1 }.buttonStyle(.bordered).padding(.horizontal, 18)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(text("music.explore.genres")).font(.title2.bold())
                    Text(text("music.explore.sceneHint")).font(.subheadline).foregroundStyle(.secondary)
                    controls
                    HStack {
                        Text(DesktopInterfaceText.value("music.explore.genreCount", variables: ["count": String(model.genres.count)])).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("music-genre-count")
                        Spacer()
                        if model.filtering { ProgressView().controlSize(.small) }
                        if filters.active { Button(text("music.explore.reset")) { filters = .init() }.font(.caption).accessibilityIdentifier("music-genre-reset") }
                    }
                    if !filters.countries.isEmpty { countryChips }
                    if model.filterFailure || model.asset == nil {
                        Text(text("Music is unavailable right now.")).foregroundStyle(.secondary)
                        Button(text("Retry")) { revision += 1 }.buttonStyle(.bordered)
                    } else if model.genres.isEmpty, !model.filtering {
                        Text(text("music.explore.noGenres")).foregroundStyle(.secondary).padding(.vertical)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200))], spacing: 16) {
                        ForEach(model.genres) { genre in
                            NavigationLink { MusicGenreDetailView(genre: genre, explore: model, catalog: catalog) } label: { genreCard(genre) }
                                .buttonStyle(.plain).accessibilityIdentifier("music-genre-" + String(genre.id))
                        }
                    }
                }.padding(.horizontal, 18).frame(maxWidth: 1100).frame(maxWidth: .infinity)
            }.padding(.vertical, 18).padding(.bottom, 30)
        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("music-explore-scroll")
            .task(id: revision) { await model.loadChart(refresh: revision != 0) }
            .task(id: filters.encoded + "|" + language + "|" + String(revision)) { await model.filter(filters, locale: locale) }
            .refreshable { await model.loadChart(refresh: true) }
    }
    private var controls: some View {
        HStack(spacing: 12) {
            Menu {
                Button(text("music.explore.allCountries")) { filters.countries = [] }
                ForEach((model.asset?.definitions.countries ?? []).sorted { country($0).localizedStandardCompare(country($1)) == .orderedAscending }, id: \.self) { code in
                    Toggle(country(code), isOn: Binding(get: { filters.countries.contains(code) }, set: { selected in
                        if selected { if !filters.countries.contains(code) { filters.countries.append(code) } }
                        else { filters.countries.removeAll { $0 == code } }
                    }))
                }
            } label: {
                Label(filters.countries.isEmpty ? text("music.explore.allCountries") : DesktopInterfaceText.value("music.explore.countryCount", variables: ["count": String(filters.countries.count)]), systemImage: "globe")
            }.accessibilityIdentifier("music-genre-countries")
            Picker(text("music.explore.styles"), selection: $filters.family) {
                Text(text("music.explore.allStyles")).tag("")
                ForEach(model.asset?.definitions.families ?? [], id: \.self) { Text(text("music.explore.family." + $0)).tag($0) }
            }.accessibilityIdentifier("music-genre-style")
        }.font(.subheadline).tint(HarborTheme.ink)
    }
    private var countryChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(filters.countries, id: \.self) { code in
                    Button { filters.countries.removeAll { $0 == code } } label: {
                        HStack { Text(country(code)); Image(systemName: "xmark").font(.caption2) }.padding(10).background(HarborTheme.surface, in: Capsule())
                    }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("music.explore.removeCountry", variables: ["country": country(code)]))
                        .accessibilityIdentifier("music-genre-country-" + code)
                }
            }
        }.scrollIndicators(.hidden)
    }
    private func country(_ code: String) -> String { locale.localizedString(forRegionCode: code) ?? code }
    private func genreCard(_ genre: MusicGenre) -> some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: model.asset?.definitions.artwork[String(genre.id)], maxPixels: 480, failureIcon: "nav-music")
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Image("music-genre-" + String(genre.id)).resizable().scaledToFit().frame(width: 34, height: 34)
                Text(genre.displayName).font(.headline).lineLimit(2)
                Text(genre.countries.isEmpty ? text("music.explore.global") : genre.countries.prefix(2).map(country).joined(separator: " · ")).font(.caption).lineLimit(2)
            }.padding(13).foregroundStyle(.white)
        }.aspectRatio(1, contentMode: .fit).clipShape(.rect(cornerRadius: 14)).contentShape(.rect)
    }
}

@MainActor struct MusicGenreDetailView: View {
    let genre: MusicGenre
    let explore: MusicExploreModel
    let catalog: any MusicCatalogCalling
    @Environment(\.musicArtistMetadata) private var artistMetadata
    @State private var model = MusicGenreModel()
    @State private var revision = 0
    @State private var moreTask: Task<Void, Never>?
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomLeading) {
                    Artwork(url: explore.asset?.definitions.artwork[String(genre.id)], maxPixels: 960, failureIcon: "nav-music")
                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 12) {
                        Image("music-genre-" + String(genre.id)).resizable().scaledToFit().frame(width: 48, height: 48)
                        Text(genre.displayName).font(.largeTitle.bold()).accessibilityIdentifier("music-genre-detail-title")
                        Text(text(sourceLabel)).font(.caption)
                    }.foregroundStyle(.white).padding(22)
                }.frame(height: 280).clipShape(.rect(cornerRadius: 16)).padding(.horizontal, 18)
                if !model.related.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(text("music.explore.subgenres")).font(.title3.bold())
                        ScrollView(.horizontal) {
                            HStack(spacing: 12) {
                                ForEach(model.related) { related in
                                    NavigationLink(related.displayName) { MusicGenreDetailView(genre: related, explore: explore, catalog: catalog) }
                                        .buttonStyle(.bordered).accessibilityIdentifier("music-related-genre-" + String(related.id))
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }.padding(.horizontal, 18)
                }
                if let selection = model.selection {
                    if !selection.tracks.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text(genre.deezerId != nil ? "music.row.charts" : "music.explore.selections")).font(.title2.bold())
                            ForEach(Array(selection.tracks.enumerated()), id: \.element.id) { index, track in
                                NavigationLink { MusicCatalogDetailView(item: .track(track), client: catalog) } label: {
                                    HStack(spacing: 12) {
                                        if selection.positions.indices.contains(index), let position = selection.positions[index] { Text(String(position)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 18) }
                                        MusicCatalogCompactItem(item: .track(track))
                                    }
                                }.buttonStyle(.plain).accessibilityIdentifier("music-genre-track-" + track.id)
                            }
                        }.padding(.horizontal, 18)
                    }
                    if let artistMetadata {
                        MusicGenreArtistsView(genre: genre, known: selection.artists.compactMap { if case .artist(let artist) = $0 { artist } else { nil } }, metadata: artistMetadata, catalog: catalog)
                    } else { rail(selection.artists, title: "music.explore.sceneArtists", layout: .circles) }
                    rail(selection.albums ?? [], title: "music.explore.sceneAlbums", layout: .covers)
                    rail(selection.playlists ?? [], title: "music.search.playlists", layout: .covers)
                    if selection.tracks.isEmpty && selection.artists.isEmpty && (selection.playlists ?? []).isEmpty && !model.loading {
                        Text(text("No results")).foregroundStyle(.secondary).padding(.horizontal, 18)
                    }
                    if model.more {
                        Button(text(model.failure ? "Retry" : "Load more")) { moreTask?.cancel(); moreTask = Task { await model.loadNext(client: explore.client) } }
                            .buttonStyle(.bordered).disabled(model.loading).frame(maxWidth: .infinity).accessibilityIdentifier("music-genre-load-more")
                    }
                }
                if model.loading { ProgressView(text("Loading music")).frame(maxWidth: .infinity) }
                if model.failure, model.selection == nil {
                    VStack(spacing: 12) { Text(text("Music is unavailable right now.")); Button(text("Retry")) { revision += 1 }.buttonStyle(.bordered) }.frame(maxWidth: .infinity)
                }
            }.padding(.vertical, 18).padding(.bottom, 30).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).navigationTitle(genre.displayName).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("music-genre-detail-scroll")
            .task(id: String(genre.id) + "|" + String(revision)) { moreTask?.cancel(); await model.load(genre.id, client: explore.client) }
            .onDisappear { moreTask?.cancel() }
    }
    @ViewBuilder private func rail(_ items: [MusicCatalogItem], title: String, layout: MusicCatalogLayout) -> some View {
        if !items.isEmpty { MusicCatalogRail(row: .init(id: "genre:\(genre.id):" + title, title: title, titleLiteral: false, subtitle: nil, layout: layout, source: "catalog", items: items), client: catalog) }
    }
    private var sourceLabel: String {
        if genre.deezerId != nil { return "music.explore.chartSource" }
        if explore.asset?.definitions.editorialScenes.contains(genre.slug) == true,
           explore.asset?.definitions.playlistScenes.contains(genre.slug) != true { return "music.explore.editorialSource" }
        return "music.explore.selectionSource"
    }
}
