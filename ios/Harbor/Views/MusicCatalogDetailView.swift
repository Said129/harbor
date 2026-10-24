import SwiftUI

@MainActor struct MusicCatalogDetailView: View {
    let item: MusicCatalogItem
    let client: any MusicCatalogCalling
    @State private var model = MusicCatalogDetailModel()
    @State private var kind = MusicCatalogKind.tracks
    @State private var operation: Task<Void, Never>?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                heading
                if item.isArtist {
                    Picker(DesktopInterfaceText.value("Catalog"), selection: $kind) {
                        Text(DesktopInterfaceText.value("Tracks")).tag(MusicCatalogKind.tracks)
                        Text(DesktopInterfaceText.value("Albums")).tag(MusicCatalogKind.albums)
                    }.pickerStyle(.segmented).accessibilityIdentifier("music-artist-catalog-kind")
                    HStack {
                        Text(DesktopInterfaceText.value(kind == .tracks ? (model.scope == .top ? "Top tracks" : "Tracks") : "Albums")).font(.headline)
                        Spacer()
                        if let total = model.total { Text(DesktopInterfaceText.value("{count} results", variables: ["count": String(total)])).font(.caption).foregroundStyle(.secondary) }
                    }
                    if model.scope == .limited {
                        Text(DesktopInterfaceText.value("music.artist.limited")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if item.isArtist, kind == .albums {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180))], spacing: 18) {
                        ForEach(model.items) { entry in
                            NavigationLink { MusicCatalogDetailView(item: entry, client: client) } label: { MusicCatalogCoverCard(item: entry) }
                                .buttonStyle(.plain).accessibilityIdentifier("music-detail-item-" + entry.id)
                        }
                    }
                } else {
                    ForEach(model.items) { entry in
                        NavigationLink { MusicCatalogDetailView(item: entry, client: client) } label: { MusicCatalogCompactItem(item: entry) }
                            .buttonStyle(.plain).accessibilityIdentifier("music-detail-item-" + entry.id)
                    }
                }
                if model.loaded, !model.loading, model.failure == nil, model.items.isEmpty, showsTrackList {
                    ContentUnavailableView(DesktopInterfaceText.value("No results"), systemImage: "music.note.list")
                }
                if model.loading { ProgressView(DesktopInterfaceText.value("Loading music")).frame(maxWidth: .infinity) }
                if let failure = model.failure {
                    VStack(spacing: 12) {
                        Text(DesktopInterfaceText.value(failure)).font(.subheadline).foregroundStyle(.secondary)
                        Button(DesktopInterfaceText.value("Retry")) { start(retry: true) }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .contain).accessibilityIdentifier("music-detail-error")
                } else if model.nextCursor != nil {
                    Button(DesktopInterfaceText.value("Load more")) { start(retry: false) }.buttonStyle(.bordered)
                        .disabled(model.loading).frame(maxWidth: .infinity).accessibilityIdentifier("music-artist-load-more")
                }
            }.padding(18).frame(maxWidth: 900).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("music-catalog-detail")
            .task(id: item.id + "|" + kind.rawValue) { operation?.cancel(); await model.load(item, kind: kind, client: client) }
            .onDisappear { operation?.cancel() }
    }
    private var showsTrackList: Bool { switch item { case .album, .artist, .playlist: true; case .track, .station: false } }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 14) {
            Artwork(url: item.artwork, maxPixels: 720, failureIcon: "nav-music")
                .frame(width: 192, height: 192).clipShape(.rect(cornerRadius: item.isArtist ? 96 : 14))
            Text(item.title).font(.title.weight(.bold)).accessibilityIdentifier("music-catalog-detail-title")
            if let subtitle = item.subtitle, !subtitle.isEmpty { Text(subtitle).font(.title3).foregroundStyle(.secondary) }
            if case .album(let album) = item {
                HStack(spacing: 12) {
                    if let year = album.year { Text(String(year)) }
                    if let count = album.trackCount { Text(DesktopInterfaceText.value("{count} tracks", variables: ["count": String(count)])) }
                    if album.explicit == true { Text(DesktopInterfaceText.value("Explicit")).font(.caption.weight(.bold)).padding(4).background(.white.opacity(0.12), in: .rect(cornerRadius: 3)) }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if case .track(let track) = item {
                if let album = track.album { Text(album).font(.subheadline).foregroundStyle(.secondary) }
                Text(track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                NavigationLink { MusicCatalogArtistSearchView(query: track.artist, client: client) } label: {
                    Label(DesktopInterfaceText.value("View artist"), systemImage: "person.crop.circle")
                }.buttonStyle(.bordered).accessibilityIdentifier("music-track-find-artist")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func start(retry: Bool) {
        operation?.cancel(); operation = Task {
            if retry && (model.items.isEmpty || model.nextCursor == nil) { await model.load(item, kind: kind, client: client) }
            else { await model.loadNext(client: client) }
        }
    }
}
