import SwiftUI

enum MusicNativeScreen: String, CaseIterable, Identifiable {
    case forYou, library
    var id: String { rawValue }
    var title: String { DesktopInterfaceText.value(self == .forYou ? "For you" : "Library") }
}

@MainActor struct MusicDiscoveryView: View {
    let model: MusicCatalogModel
    let library: MusicLibrary
    let query: String
    @State private var retry: Task<Void, Never>?
    private var recent: [MusicRecord] { MusicCollections.shared.records(.recent, library: library.records, owner: library.owner) }
    private var hero: (item: MusicCatalogItem, title: String)? {
        for row in model.rows {
            if let item = row.items.first(where: { if case .album = $0 { true } else { false } }) { return (item, row.displayTitle) }
        }
        return nil
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if model.activeQuery.isEmpty {
                    if let hero { MusicCatalogHero(item: hero.item, eyebrow: hero.title, client: model.client).padding(.horizontal, 18) }
                    if !recent.isEmpty { recentBand }
                    ForEach(model.rows.filter { !$0.items.isEmpty }) { MusicCatalogRail(row: $0, client: model.client) }
                    if model.rows.isEmpty, !model.loading, model.hasRequested, model.failure == nil {
                        ContentUnavailableView(DesktopInterfaceText.value("Music"), image: "nav-music", description: Text(DesktopInterfaceText.value("Nothing to show yet.")))
                    }
                } else if let result = model.result {
                    Text(DesktopInterfaceText.value("Search results")).font(.title3.weight(.semibold)).padding(.horizontal, 18)
                        .accessibilityIdentifier("music-catalog-search-ready")
                    MusicCatalogSearchSections(result: result, client: model.client)
                }
                if model.loading || !model.hasRequested { ProgressView(DesktopInterfaceText.value("Loading music")).frame(maxWidth: .infinity).accessibilityIdentifier("music-catalog-loading") }
                if let failure = model.failure {
                    VStack(spacing: 12) {
                        Text(DesktopInterfaceText.value(failure)).font(.subheadline).foregroundStyle(.secondary)
                        Button(DesktopInterfaceText.value("Retry")) {
                            retry?.cancel(); retry = Task { await model.load(query: query, refresh: true, debounce: false) }
                        }.buttonStyle(.bordered).accessibilityIdentifier("music-catalog-retry")
                    }.frame(maxWidth: .infinity).padding(.horizontal, 18).accessibilityElement(children: .contain).accessibilityIdentifier("music-catalog-error")
                }
            }.padding(.vertical, 18).padding(.bottom, 24)
        }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("music-discovery-scroll")
            .refreshable { await model.load(query: query, refresh: true, debounce: false) }
            .onChange(of: query) { _, _ in retry?.cancel() }
            .onDisappear { retry?.cancel() }
    }
    private var recentBand: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DesktopInterfaceText.value("Recently played")).font(.title3.weight(.semibold)).padding(.horizontal, 18)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(recent.prefix(10))) { record in
                        Button { MusicPlayback.shared.play(record, queue: recent, owner: library.owner) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                MusicCover(record: record, owner: library.owner).frame(width: 140, height: 140)
                                Text(record.local.track.title).font(.subheadline.weight(.medium)).lineLimit(2)
                                Text(record.local.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(width: 140, alignment: .leading).foregroundStyle(HarborTheme.ink)
                        }.buttonStyle(.plain).accessibilityIdentifier("music-for-you-recent-" + record.id)
                    }
                }.padding(.horizontal, 18)
            }.scrollIndicators(.hidden)
        }
    }
}

@MainActor private struct MusicCatalogHero: View {
    let item: MusicCatalogItem
    let eyebrow: String
    let client: any MusicCatalogCalling
    var body: some View {
        NavigationLink { MusicCatalogDetailView(item: item, client: client) } label: {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: item.artwork, maxPixels: 900, failureIcon: "nav-music").frame(height: 300)
                LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    Text(eyebrow).font(.caption.weight(.semibold)).textCase(.uppercase).tracking(2)
                    Text(item.title).font(.title.weight(.bold)).lineLimit(2)
                    if let subtitle = item.subtitle { Text(subtitle).font(.subheadline).lineLimit(1) }
                    Label(DesktopInterfaceText.value("View album"), systemImage: "arrow.up.right").font(.subheadline.weight(.semibold)).padding(.top, 6)
                }.padding(22).foregroundStyle(.white)
            }.frame(height: 300).clipShape(.rect(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("music-for-you-hero")
    }
}

@MainActor struct MusicCatalogArtistSearchView: View {
    let query: String
    @State private var model: MusicCatalogModel
    @State private var revision = 0
    @MainActor init(query: String, client: any MusicCatalogCalling) {
        self.query = query; _model = State(initialValue: MusicCatalogModel(client: client))
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if let result = model.result { MusicCatalogSearchSections(result: result, client: model.client) }
                if model.loading { ProgressView(DesktopInterfaceText.value("Loading music")) }
                if let failure = model.failure {
                    Text(DesktopInterfaceText.value(failure)).foregroundStyle(.secondary)
                    Button(DesktopInterfaceText.value("Retry")) { revision += 1 }.buttonStyle(.bordered)
                }
            }.padding(.vertical, 18)
        }.background(HarborTheme.background).navigationTitle(query).navigationBarTitleDisplayMode(.inline)
            .task(id: query + "|" + String(revision)) { await model.load(query: query, debounce: false) }
    }
}
