import SwiftUI

@MainActor struct MusicPersonalCollectionLinks: View {
    let library: MusicLibrary
    let playlists: MusicPlaylistStore
    let query: String
    private let collections = MusicCollections.shared
    var body: some View {
        ForEach(MusicPersonalCollection.allCases) { collection in
            if query.isEmpty || collection.title.localizedStandardContains(query) {
                let tracks = collections.tracks(collection, store: playlists, library: library.records, owner: library.owner)
                NavigationLink {
                    MusicPersonalCollectionView(collection: collection, library: library, playlists: playlists)
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            MusicCollectionCover(tracks: tracks, local: library.records, owner: library.owner).frame(width: 52, height: 52)
                            Image(systemName: collection.symbol).font(.caption.weight(.semibold)).padding(5).background(.ultraThinMaterial, in: .circle)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collection.title)
                            Text(DesktopInterfaceText.value("{count} tracks", variables: ["count": String(tracks.count)])).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.accessibilityIdentifier("music-collection-" + collection.rawValue)
                    .accessibilityValue(String(tracks.count))
                    .disabled(!collections.isReady(owner: library.owner))
            }
        }
    }
}

@MainActor struct MusicPersonalCollectionView: View {
    let collection: MusicPersonalCollection
    let library: MusicLibrary
    let playlists: MusicPlaylistStore
    @State private var filters = MusicCollectionFilters()
    @State private var model = MusicCollectionModel()
    @Environment(\.musicPlaybackSession) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let collections = MusicCollections.shared
    private var tracks: [MusicTrack] { collections.tracks(collection, store: playlists, library: library.records, owner: library.owner) }
    private var input: MusicCollectionInput {
        var selected = filters; selected.query = MusicCollectionFilters.limitedQuery(selected.query)
        return .init(tracks: tracks, filters: selected, recentFirst: collection == .recent)
    }
    var body: some View {
        List {
            if !tracks.isEmpty {
                MusicCollectionCover(tracks: tracks, local: library.records, owner: library.owner).frame(width: 120, height: 120)
                Button { if let first = model.tracks.first { play(first) } } label: { Label(DesktopInterfaceText.value("music.play"), image: "music-play") }
                    .accessibilityIdentifier("music-collection-play").disabled(model.loading || model.tracks.isEmpty)
                MusicCollectionToolsView(filters: $filters, model: model, canSortAdded: collection == .recent)
            }
            let imported = Dictionary(library.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            ForEach(model.tracks) { track in
                MusicCollectionTrackRow(track: track, record: imported[track.id], owner: library.owner) { play(track) }
                    .contextMenu {
                        if let session, session.scope.owner == library.owner { MusicRecordingActions(track: track, session: session) }
                        else if let record = imported[track.id] { MusicTrackActions(record: record, owner: library.owner, playlists: playlists) }
                    }.accessibilityIdentifier("music-collection-track-" + track.id)
            }
            if model.tracks.isEmpty, !model.loading {
                if filters.active { ContentUnavailableView.search(text: filters.query) }
                else {
                    ContentUnavailableView(collection.title, systemImage: collection.symbol,
                        description: Text(DesktopInterfaceText.value(collection == .recent ? "Your listening history will build itself here." : "Save a track and it will appear here.")))
                }
            }
            if model.failed { Button(DesktopInterfaceText.value("Retry")) { Task { await model.load(input) } } }
            if let error = collections.errors[library.owner] { Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange) }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(HarborTheme.background)
            .navigationTitle(collection.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filters.query, prompt: DesktopInterfaceText.value("music.filter.tracks"))
            .onChange(of: filters.query) { _, value in let limited = MusicCollectionFilters.limitedQuery(value); if limited != value { filters.query = limited } }
            .onAppear { collections.prepare(owner: library.owner); if collection == .recent { filters.sort = .added } }
            .task(id: input) { await model.load(input) }
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.3, 1, duration: 0.16), value: model.tracks.map(\.id))
            .accessibilityIdentifier("music-personal-collection-" + collection.rawValue)
    }
    private func play(_ track: MusicTrack) {
        if let session, session.scope.owner == library.owner {
            MusicPlayback.shared.play(track, queue: model.tracks, using: session, origin: .init(kind: collection.rawValue, id: collection.rawValue, name: collection.title))
        } else {
            let imported = Dictionary(library.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if let record = imported[track.id] { MusicPlayback.shared.play(record, queue: model.tracks.compactMap { imported[$0.id] }, owner: library.owner) }
        }
    }
}
