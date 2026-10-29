import SwiftUI

@MainActor struct MusicPlaylistsView: View {
    let library: MusicLibrary
    let store: MusicPlaylistStore
    let query: String
    @State private var creating = false
    private var lists: [MusicPlaylist] { store.owner == library.owner ? store.playlists.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } : [] }
    var body: some View {
        List {
            MusicPersonalCollectionLinks(library: library, playlists: store, query: query)
            Button { creating = true } label: { Label(DesktopInterfaceText.value("music.playlist.create"), image: "music-plus") }.disabled(!store.ready || store.owner != library.owner)
            if lists.isEmpty { Text(DesktopInterfaceText.value(query.isEmpty ? "music.playlist.first" : "music.playlist.noMatches")).foregroundStyle(.secondary) }
            ForEach(lists) { playlist in
                NavigationLink {
                    MusicPlaylistView(id: playlist.id, library: library, store: store)
                } label: {
                    HStack(spacing: 12) {
                        MusicCollectionCover(tracks: store.recordings(in: playlist.id, local: library.records), local: library.records, owner: library.owner, playlist: playlist.id).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 4) { Text(playlist.name); Text(DesktopInterfaceText.value("music.card.trackCount", variables: ["count": String(playlist.trackIds.count)])).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden)
            .task(id: library.owner) { MusicCollections.shared.prepare(owner: library.owner) }
            .sheet(isPresented: $creating) { MusicPlaylistNameView(store: store) }
    }
}

struct MusicPlaylistChoices: View {
    let record: MusicRecord
    let store: MusicPlaylistStore
    var body: some View {
        Menu {
            if store.playlists.isEmpty { Text("Crea una lista desde Biblioteca → Listas.") }
            ForEach(store.playlists) { playlist in
                Button { store.add(record, to: playlist.id) } label: {
                    if playlist.trackIds.contains(record.id) { Label(playlist.name, image: "music-check") }
                    else { Text(playlist.name) }
                }.disabled(playlist.trackIds.contains(record.id))
            }
        } label: { Label("Añadir a una lista", image: "music-plus") }.disabled(!store.ready)
    }
}

@MainActor struct MusicPlaylistView: View {
    let id: String
    let library: MusicLibrary
    let store: MusicPlaylistStore
    @State private var renaming = false
    @State private var deleting = false
    @State private var filters = MusicCollectionFilters()
    @State private var model = MusicCollectionModel()
    @State private var adding = false
    @Environment(\.musicPlaybackSession) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private var playlist: MusicPlaylist? { store.owner == library.owner ? store.playlists.first { $0.id == id } : nil }
    private var tracks: [MusicTrack] { playlist == nil ? [] : store.recordings(in: id, local: library.records) }
    private var input: MusicCollectionInput {
        var selected = filters; selected.query = MusicCollectionFilters.limitedQuery(selected.query)
        return .init(tracks: tracks, filters: selected, addedAt: playlist?.trackAddedAt)
    }
    private var displayedIDs: [String] { filters.canReorder ? playlist?.trackIds ?? [] : model.tracks.map(\.id) }
    var body: some View {
        List {
            if let playlist {
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        MusicPlaylistCoverEditor(playlist: playlist.id, tracks: tracks, library: library, store: store).frame(width: 104)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(playlist.name).font(.title3.bold())
                            Text(DesktopInterfaceText.value("music.card.trackCount", variables: ["count": String(playlist.trackIds.count)])).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button { if let first = model.tracks.first { play(first) } } label: { Label(DesktopInterfaceText.value("music.play"), image: "music-play") }
                                Button { if let first = model.tracks.randomElement() { MusicPlayback.shared.shuffle = true; play(first) } } label: { MusicGlyph("shuffle").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("music.transport.shuffle"))
                            }.buttonStyle(.bordered).disabled(model.loading || model.tracks.isEmpty)
                        }
                    }.padding(.vertical, 6)
                    MusicCollectionToolsView(filters: $filters, model: model)
                }
                Section {
                    let lookup = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    let imported = Dictionary(library.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    ForEach(displayedIDs, id: \.self) { trackID in
                        if let track = lookup[trackID] {
                            MusicCollectionTrackRow(track: track, record: imported[trackID], owner: library.owner) { play(track) }
                                .disabled(model.loading).contextMenu {
                                    if let session, session.scope.owner == library.owner { MusicRecordingActions(track: track, session: session) }
                                    else if let record = imported[trackID] { MusicTrackActions(record: record, owner: library.owner, playlists: store) }
                                    Button(DesktopInterfaceText.value("music.playlist.remove"), role: .destructive) { store.remove(track.id, from: id) }
                                }
                        } else { Text(DesktopInterfaceText.value("music.mobile.missingFile")).foregroundStyle(.secondary) }
                    }.onDelete { offsets in
                        let ids = displayedIDs
                        for index in offsets where ids.indices.contains(index) { store.remove(ids[index], from: id) }
                    }
                        .onMove { from, destination in
                            guard filters.canReorder, !model.loading, let source = from.first, playlist.trackIds.indices.contains(source) else { return }
                            store.move(playlist.trackIds[source], in: id, to: destination > source ? destination - 1 : destination)
                        }.moveDisabled(!filters.canReorder || model.loading)
                    if displayedIDs.isEmpty, !model.loading { Text(DesktopInterfaceText.value(filters.active ? "music.searchEmpty" : "music.library.playlistEmpty")).foregroundStyle(.secondary) }
                }
                Section { Button { adding = true } label: { Label(DesktopInterfaceText.value("music.library.addTracks"), image: "music-plus") }.disabled(!store.ready) }
                Section { MusicPlaylistExportButton(playlist: playlist, tracks: tracks, library: library, store: store) }
                if model.failed { Button(DesktopInterfaceText.value("Retry")) { Task { await model.load(input) } } }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
                Section { Button(DesktopInterfaceText.value("music.playlist.delete"), role: .destructive) { deleting = true } }
            } else { Text(DesktopInterfaceText.value("music.mobile.playlistUnavailable")) }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(HarborTheme.background)
            .navigationTitle(playlist?.name ?? DesktopInterfaceText.value("music.playlist.new")).navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filters.query, prompt: DesktopInterfaceText.value("music.filter.tracks"))
            .onChange(of: filters.query) { _, value in let limited = MusicCollectionFilters.limitedQuery(value); if limited != value { filters.query = limited } }
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.3, 1, duration: 0.16), value: model.tracks.map(\.id))
            .task(id: input) { await model.load(input) }
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("music.playlist.rename")) { renaming = true }; EditButton() } }
            .sheet(isPresented: $renaming) { MusicPlaylistNameView(store: store, id: id) }
            .sheet(isPresented: $adding) { MusicPlaylistAddView(id: id, library: library, store: store) }
            .confirmationDialog(DesktopInterfaceText.value("music.playlist.deleteConfirm"), isPresented: $deleting, titleVisibility: .visible) {
                Button(DesktopInterfaceText.value("music.playlist.delete"), role: .destructive) {
                    store.delete(id)
                    if store.error == nil {
                        try? MusicPlaylistCoverStore.shared.clear(owner: library.owner, playlist: id, allowed: { true })
                        dismiss()
                    }
                }
            }.accessibilityIdentifier("music-mixed-playlist")
    }
    private func play(_ track: MusicTrack) {
        if let session, session.scope.owner == library.owner {
            MusicPlayback.shared.play(track, queue: model.tracks, using: session, origin: .init(kind: "playlist", id: id, name: playlist?.name ?? ""))
        } else if let record = library.records.first(where: { $0.id == track.id }) {
            let imported = Dictionary(library.records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            MusicPlayback.shared.play(record, queue: model.tracks.compactMap { imported[$0.id] }, owner: library.owner)
        }
    }
}

private struct MusicPlaylistNameView: View {
    let store: MusicPlaylistStore
    var id: String?
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField(DesktopInterfaceText.value("music.playlist.nameLabel"), text: $name).textInputAutocapitalization(.sentences)
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.navigationTitle(DesktopInterfaceText.value(id == nil ? "music.playlist.create" : "music.playlist.rename")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(DesktopInterfaceText.value("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("music.playlist.save")) { if let id { store.rename(id, name: name) } else { store.create(name) }; if store.error == nil { dismiss() } }.disabled(!store.ready || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.onAppear { name = store.playlists.first { $0.id == id }?.name ?? "" }
    }
}
