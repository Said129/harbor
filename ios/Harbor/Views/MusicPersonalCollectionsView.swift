import SwiftUI

@MainActor struct MusicPersonalCollectionLinks: View {
    let library: MusicLibrary
    let playlists: MusicPlaylistStore
    let query: String
    private let collections = MusicCollections.shared
    var body: some View {
        ForEach(MusicPersonalCollection.allCases) { collection in
            if query.isEmpty || collection.title.localizedStandardContains(query) {
                let records = collections.records(collection, library: library.records, owner: library.owner)
                NavigationLink {
                    MusicPersonalCollectionView(collection: collection, library: library, playlists: playlists)
                } label: {
                    HStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            MusicCover(record: records.first, owner: library.owner).frame(width: 52, height: 52)
                            Image(systemName: collection.symbol).font(.caption.weight(.semibold)).padding(5).background(.ultraThinMaterial, in: .circle)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collection.title)
                            Text(DesktopInterfaceText.value("{count} tracks", variables: ["count": String(records.count)])).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.accessibilityIdentifier("music-collection-" + collection.rawValue)
                    .accessibilityValue(String(records.count))
                    .disabled(!collections.isReady(owner: library.owner))
            }
        }
    }
}

@MainActor private struct MusicPersonalCollectionView: View {
    let collection: MusicPersonalCollection
    let library: MusicLibrary
    let playlists: MusicPlaylistStore
    @State private var query = ""
    private let collections = MusicCollections.shared
    private var records: [MusicRecord] {
        collections.records(collection, library: library.records, owner: library.owner).filter {
            query.isEmpty || ($0.local.track.title + " " + $0.local.track.artist + " " + ($0.local.track.album ?? "")).localizedStandardContains(query)
        }
    }
    var body: some View {
        List {
            if !records.isEmpty {
                Button { if let first = records.first { MusicPlayback.shared.play(first, queue: records, owner: library.owner) } } label: { Label(DesktopInterfaceText.value("Play"), image: "music-play") }
                    .accessibilityIdentifier("music-collection-play")
            }
            ForEach(records) { record in
                MusicTrackRow(record: record, owner: library.owner) { MusicPlayback.shared.play(record, queue: records, owner: library.owner) }
                    .contextMenu { MusicTrackActions(record: record, owner: library.owner, playlists: playlists) }
                    .accessibilityIdentifier("music-collection-track-" + record.id)
            }
            if records.isEmpty {
                if !query.isEmpty { ContentUnavailableView.search(text: query) }
                else {
                    ContentUnavailableView(collection.title, systemImage: collection.symbol,
                        description: Text(DesktopInterfaceText.value(collection == .recent ? "Your listening history will build itself here." : "Save a track and it will appear here.")))
                }
            }
            if let error = collections.errors[library.owner] { Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange) }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(HarborTheme.background)
            .navigationTitle(collection.title).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: DesktopInterfaceText.value("Search music"))
            .accessibilityIdentifier("music-personal-collection-" + collection.rawValue)
    }
}
