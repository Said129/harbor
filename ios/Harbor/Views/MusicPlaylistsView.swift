import SwiftUI

struct MusicPlaylistsView: View {
    let library: MusicLibrary
    let store: MusicPlaylistStore
    let query: String
    @State private var creating = false
    private var lists: [MusicPlaylist] { store.playlists.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        List {
            Button { creating = true } label: { Label("Crear lista", image: "music-plus") }.disabled(!store.ready)
            if lists.isEmpty { Text(query.isEmpty ? "Crea una lista y añade canciones desde sus opciones." : "No hay listas con este nombre.").foregroundStyle(.secondary) }
            ForEach(lists) { playlist in
                NavigationLink {
                    MusicPlaylistView(id: playlist.id, library: library, store: store)
                } label: {
                    HStack(spacing: 12) {
                        MusicCover(record: library.records.first { playlist.trackIds.contains($0.id) }, owner: library.owner).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 4) { Text(playlist.name); Text("\(playlist.trackIds.count) canciones").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden)
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

private struct MusicPlaylistView: View {
    let id: String
    let library: MusicLibrary
    let store: MusicPlaylistStore
    @State private var renaming = false
    @State private var deleting = false
    @State private var filters = MusicFilters()
    @Environment(\.dismiss) private var dismiss
    private var playlist: MusicPlaylist? { store.playlists.first { $0.id == id } }
    private var available: [MusicRecord] {
        let records = Dictionary(uniqueKeysWithValues: library.records.map { ($0.id, $0) })
        let ordered = playlist?.trackIds.compactMap { records[$0] } ?? []
        return filters.apply(ordered, addedAt: playlist?.trackAddedAt ?? [:])
    }
    private var displayedIDs: [String] { filters.canReorder ? playlist?.trackIds ?? [] : available.map(\.id) }
    var body: some View {
        List {
            if let playlist {
                Section {
                    Button { if let first = available.first { MusicPlayback.shared.play(first, queue: available, owner: library.owner) } } label: { Label("Reproducir lista", image: "music-play") }.disabled(available.isEmpty)
                    MusicFilterTools(filters: $filters, count: available.count)
                }
                Section {
                    ForEach(displayedIDs, id: \.self) { trackID in
                        if let record = library.records.first(where: { $0.id == trackID }) {
                            MusicTrackRow(record: record, owner: library.owner) { MusicPlayback.shared.play(record, queue: available, owner: library.owner) }
                                .contextMenu { MusicTrackActions(record: record, owner: library.owner) }
                        } else { Text("Archivo fuera de la biblioteca").foregroundStyle(.secondary) }
                    }.onDelete { offsets in
                        let ids = displayedIDs
                        for index in offsets where ids.indices.contains(index) { store.remove(ids[index], from: id) }
                    }
                        .onMove { from, destination in
                            guard filters.canReorder, let source = from.first, playlist.trackIds.indices.contains(source) else { return }
                            store.move(playlist.trackIds[source], in: id, to: destination > source ? destination - 1 : destination)
                        }.moveDisabled(!filters.canReorder)
                    if displayedIDs.isEmpty { Text(filters.active ? "No hay canciones con estos filtros." : "Añade canciones desde sus opciones.").foregroundStyle(.secondary) }
                }
                if let error = store.error { Text(error).foregroundStyle(.orange) }
                Section { Button("Eliminar lista", role: .destructive) { deleting = true } }
            } else { Text("Esta lista ya no está disponible.") }
        }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(HarborTheme.background)
            .navigationTitle(playlist?.name ?? "Lista").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filters.query, prompt: "Filtrar canciones")
            .onChange(of: filters.query) { _, value in if value.count > 200 { filters.query = String(value.prefix(200)) } }
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button("Renombrar") { renaming = true }; EditButton() } }
            .sheet(isPresented: $renaming) { MusicPlaylistNameView(store: store, id: id) }
            .confirmationDialog("¿Eliminar esta lista?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Eliminar lista", role: .destructive) { store.delete(id); if store.error == nil { dismiss() } }
            } message: { Text("Las canciones se conservarán en tu biblioteca.") }
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
                TextField("Nombre de la lista", text: $name).textInputAutocapitalization(.sentences)
                if let error = store.error { Text(error).foregroundStyle(.orange) }
            }.navigationTitle(id == nil ? "Crear lista" : "Renombrar lista").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancelar") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { Button("Guardar") { if let id { store.rename(id, name: name) } else { store.create(name) }; if store.error == nil { dismiss() } }.disabled(!store.ready || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.onAppear { name = store.playlists.first { $0.id == id }?.name ?? "" }
    }
}
