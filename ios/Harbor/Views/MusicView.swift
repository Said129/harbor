import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MusicView: View {
    let app: AppModel
    private let workspace: MusicWorkspace
    @State private var library: MusicLibrary
    @State private var playlists: MusicPlaylistStore
    @State private var filters = MusicFilters(sort: .title)
    @State private var category = "Canciones"
    @State private var importFiles = false
    @State private var selectFolder = false
    @AppStorage("harbor.music.tab") private var screen = MusicNativeScreen.forYou
    @State private var catalog: MusicCatalogModel
    @State private var explore: MusicExploreModel
    @State private var billboard: MusicBillboardClient
    @State private var artistMetadata: MusicArtistClient
    @State private var metadataSettings = false
    @State private var serverSettings = false
    @State private var serverRevision = UUID()
    @State private var server: SubsonicMusicService
    @AppStorage("harbor.music.genres.explore.v1") private var genreFiltersRaw = "{}"
    @MainActor init(app: AppModel) {
        self.app = app
        let workspace = app.musicWorkspaceForCurrentProfile(); self.workspace = workspace
        let scope = workspace.scope
        _library = State(initialValue: workspace.library)
        _playlists = State(initialValue: workspace.playlists)
        _server = State(initialValue: workspace.server)
        _catalog = State(initialValue: workspace.catalog)
        _explore = State(initialValue: MusicExploreModel(client: MusicExploreClient(scope: scope, currentScope: { [weak app] in
            app?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation)
        })))
        _billboard = State(initialValue: MusicBillboardClient(scope: scope, currentScope: { [weak app] in
            app?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation)
        }))
        _artistMetadata = State(initialValue: MusicArtistClient(scope: scope, currentScope: { [weak app] in
            app?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation)
        }))
        MusicCollections.shared.prepare(owner: app.personalOwner)
    }
    private var query: String { filters.query }
    private var genreFilters: Binding<MusicGenreFilters> {
        Binding(get: { MusicGenreFilters.read(genreFiltersRaw, definitions: explore.asset?.definitions) }, set: { genreFiltersRaw = $0.encoded })
    }
    private var search: Binding<String> {
        Binding(get: { screen == .explore ? genreFilters.wrappedValue.query : filters.query }, set: { value in
            if screen == .explore { var next = genreFilters.wrappedValue; next.query = String(value.prefix(120)); genreFilters.wrappedValue = next }
            else { filters.query = value }
        })
    }
    private var records: [MusicRecord] { filters.apply(library.records) }
    private var groups: [(String, String, [MusicRecord])] {
        let grouped = Dictionary(grouping: records) { record in
            category == "Álbumes" ? record.local.albumKey ?? record.id : record.local.artistKey
        }
        return grouped.map { key, values in
            let first = values[0].local
            let title = category == "Álbumes" ? first.track.album ?? first.track.title : first.albumArtist ?? first.track.artist
            let ordered = values.sorted {
                if ($0.local.discNo ?? 1) != ($1.local.discNo ?? 1) { return ($0.local.discNo ?? 1) < ($1.local.discNo ?? 1) }
                if ($0.local.trackNo ?? UInt32.max) != ($1.local.trackNo ?? UInt32.max) { return ($0.local.trackNo ?? UInt32.max) < ($1.local.trackNo ?? UInt32.max) }
                return $0.local.track.title.localizedStandardCompare($1.local.track.title) == .orderedAscending
            }
            return (key, title, ordered)
        }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
    var body: some View {
        VStack(spacing: 12) {
            Picker(DesktopInterfaceText.value("Music"), selection: $screen) {
                ForEach(MusicNativeScreen.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal).accessibilityIdentifier("music-screen")
            if screen == .forYou { MusicDiscoveryView(model: catalog, library: library, query: filters.query) }
            else if screen == .explore { MusicExploreView(model: explore, catalog: catalog.client, billboard: billboard, filters: genreFilters) }
            else { localLibrary }
        }.background(HarborTheme.background).navigationTitle("Música").navigationBarTitleDisplayMode(.inline)
            .searchable(text: search, prompt: screen == .forYou ? DesktopInterfaceText.value("Search music") : screen == .explore ? DesktopInterfaceText.value("music.taste.search") : DesktopInterfaceText.value("music.searchPlaceholder"))
            .task(id: screen.rawValue + "|" + query + "|" + serverRevision.uuidString) {
                MusicPlayback.shared.attach(workspace.playback)
                if screen == .forYou { await catalog.load(query: query) }
            }
            .onChange(of: filters.query) { _, value in if value.count > 200 { filters.query = String(value.prefix(200)) } }
            .onSubmit(of: .search) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { serverSettings = true } label: { Label(DesktopInterfaceText.value("music.connections.server"), systemImage: "server.rack") }.accessibilityIdentifier("music-server-open")
                    Button { metadataSettings = true } label: { Label(DesktopInterfaceText.value("Metadata"), systemImage: "info.circle") }.accessibilityIdentifier("music-metadata-open")
                    Button { openImport(folder: false) } label: { Label(DesktopInterfaceText.value("Import files"), image: "music-plus") }.disabled(!library.ready || library.importing)
                    Button { openImport(folder: true) } label: { Label(DesktopInterfaceText.value("Import folder"), image: "music-folder-open") }.disabled(!library.ready || library.importing)
                } label: { MusicGlyph("plus").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value("Options")).accessibilityIdentifier("music-actions")
            } }
            .sheet(isPresented: $metadataSettings) { MusicMetadataSettingsView(client: artistMetadata) }
            .sheet(isPresented: $serverSettings) {
                MusicServerConnectionView(service: server) {
                    catalog.invalidatePrivateServer()
                    serverRevision = UUID()
                }
            }
            .environment(\.musicArtistMetadata, artistMetadata)
            .environment(\.musicPlaybackSession, workspace.playback)
            .fileImporter(isPresented: $importFiles, allowedContentTypes: selectFolder ? [.folder] : [.audio, .data], allowsMultipleSelection: !selectFolder) { result in
                switch result {
                case .success(let urls):
                    screen = .library
                    if selectFolder { if let folder = urls.first { library.importFolder(folder) } }
                    else { library.importFiles(urls) }
                case .failure: library.error = "No se pudo abrir la selección de archivos."
                }
            }
            .onDisappear { if artistMetadata.scope != app.pluginExecutionScope { workspace.dispose(); explore.dispose(); billboard.dispose(); artistMetadata.dispose() } }
            .accessibilityElement(children: .contain).accessibilityIdentifier("music-library")
    }
    private var localLibrary: some View {
        VStack(spacing: 12) {
            Picker("Biblioteca", selection: $category) { Text("Canciones").tag("Canciones"); Text("Álbumes").tag("Álbumes"); Text("Artistas").tag("Artistas"); Text("Listas").tag("Listas") }.pickerStyle(.segmented).padding(.horizontal).accessibilityIdentifier("music-library-category")
            if category == "Canciones", !library.records.isEmpty { MusicFilterTools(filters: $filters, count: records.count).padding(.horizontal) }
            if let error = library.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if let error = playlists.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if let error = MusicCollections.shared.errors[library.owner] {
                HStack {
                    Text(DesktopInterfaceText.value(error)).font(.caption).foregroundStyle(.orange)
                    Button(DesktopInterfaceText.value("Retry")) { MusicCollections.shared.retry(owner: library.owner) }
                }.padding(.horizontal).accessibilityIdentifier("music-collections-error")
            }
            importStatus; libraryContent
        }
    }
    @ViewBuilder private var importStatus: some View {
        if library.importing {
            VStack(spacing: 6) {
                if library.scanning { ProgressView("Buscando música en la carpeta…") }
                else { ProgressView("Importando \(library.importCompleted) de \(library.importTotal)", value: Double(library.importCompleted), total: Double(max(library.importTotal, 1))) }
                Button("Cancelar importación") { library.cancelImport() }.font(.caption)
            }.padding(.horizontal).accessibilityIdentifier("music-import-progress")
        } else if let message = library.importMessage { Text(message).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
    }
    @ViewBuilder private var libraryContent: some View {
        if category == "Listas" { MusicPlaylistsView(library: library, store: playlists, query: query) }
        else if library.records.isEmpty {
            ContentUnavailableView { Label(DesktopInterfaceText.value("music.home.yourFiles"), image: "nav-music") } description: { Text(DesktopInterfaceText.value("music.home.filesBody")) } actions: {
                Button { openImport(folder: false) } label: { Label(DesktopInterfaceText.value("Import files"), image: "music-plus") }
                Button { openImport(folder: true) } label: { Label(DesktopInterfaceText.value("Import folder"), image: "music-folder-open") }
            }.disabled(!library.ready || library.importing)
        } else if records.isEmpty {
            if !query.isEmpty { ContentUnavailableView.search(text: query) }
            else { ContentUnavailableView("No hay canciones con estos filtros", image: "nav-music") }
        }
        else if category == "Canciones" {
            List {
                ForEach(records) { record in
                    MusicTrackRow(record: record, owner: library.owner) { MusicPlayback.shared.play(record, queue: records, owner: library.owner) }
                        .contextMenu { MusicTrackActions(record: record, owner: library.owner, playlists: playlists) }
                        .swipeActions { Button("Eliminar", role: .destructive) { remove(record) } }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
        } else {
            List {
                ForEach(groups, id: \.0) { group in
                    NavigationLink {
                        MusicGroupView(title: group.1, records: group.2, owner: library.owner, playlists: playlists)
                    } label: {
                        HStack(spacing: 12) {
                            MusicCover(record: group.2.first, owner: library.owner).frame(width: 52, height: 52)
                            VStack(alignment: .leading, spacing: 4) { Text(group.1); Text("\(group.2.count) canciones").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
    private func openImport(folder: Bool) { selectFolder = folder; importFiles = true }
    private func remove(_ record: MusicRecord) {
        MusicPlayback.shared.remove(record)
        Task { await library.remove(record) }
    }
}

private struct MusicGroupView: View {
    let title: String
    let records: [MusicRecord]
    let owner: String
    let playlists: MusicPlaylistStore
    var body: some View {
        List {
            Button { if let first = records.first { MusicPlayback.shared.play(first, queue: records, owner: owner) } } label: { Label("Reproducir", image: "music-play") }
            ForEach(records) { record in MusicTrackRow(record: record, owner: owner) { MusicPlayback.shared.play(record, queue: records, owner: owner) }.contextMenu { MusicTrackActions(record: record, owner: owner, playlists: playlists) } }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(HarborTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
struct MusicTrackActions: View {
    let record: MusicRecord
    let owner: String
    var playlists: MusicPlaylistStore?
    var body: some View {
        let collections = MusicCollections.shared
        let liked = collections.isLiked(record.id, owner: owner)
        Button { collections.setLiked(record.id, liked: !liked, owner: owner) } label: {
            Label(DesktopInterfaceText.value(liked ? "Remove from saved tracks" : "Save track"), systemImage: liked ? "heart.slash" : "heart")
        }.disabled(!collections.isReady(owner: owner)).accessibilityIdentifier("music-track-like")
        if let playlists { MusicPlaylistChoices(record: record, store: playlists) }
        Button { MusicPlayback.shared.enqueue(record, owner: owner, next: true) } label: { Label("Reproducir después", image: "music-queue-next") }
        Button { MusicPlayback.shared.enqueue(record, owner: owner) } label: { Label("Añadir a la cola", image: "music-queue") }
        Button { UIPasteboard.general.string = record.local.track.title + " - " + record.local.track.artist } label: { Label("Copiar título", image: "music-copy") }
    }
}
struct MusicCover: View {
    var record: MusicRecord?
    var owner = "guest"
    var cornerRadius: CGFloat = 8
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            if let image { BoundedArtworkImage(image: image, fit: .fill) }
            else { Image("music-music").resizable().scaledToFit().padding(12).background(HarborTheme.surface) }
        }.clipShape(.rect(cornerRadius: cornerRadius)).accessibilityHidden(true).task(id: owner + "|" + (record?.filename ?? "")) {
            image = nil
            if let record, let data = try? await MusicFileService.shared.artwork(record, owner: owner) { image = UIImage(data: data) }
        }
    }
}
struct MusicTrackRow: View {
    let record: MusicRecord
    let owner: String
    let play: () -> Void
    @AppStorage("harbor.music.playlistView") private var layout = "list"
    private var compact: Bool { layout == "compact" }
    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                MusicCover(record: record, owner: owner).frame(width: compact ? 32 : 44, height: compact ? 32 : 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.local.track.title).font(compact ? .subheadline : .body).lineLimit(1)
                    Text(record.local.track.artist + (record.local.track.album.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if MusicCollections.shared.isLiked(record.id, owner: owner) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(HarborTheme.accent) }
                if MusicPlayback.shared.owner == owner && MusicPlayback.shared.current?.id == record.id { MusicGlyph(MusicPlayback.shared.paused ? "pause" : "waveform").foregroundStyle(HarborTheme.accent) }
                Text(record.local.track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.frame(minHeight: 44).contentShape(.rect)
        }.buttonStyle(.plain).accessibilityLabel(record.local.track.title + ", " + record.local.track.artist)
            .accessibilityValue(MusicCollections.shared.isLiked(record.id, owner: owner) ? DesktopInterfaceText.value("Saved") : "")
            .accessibilityIdentifier("music-track-" + record.id)
    }
}

struct MusicGlyph: View {
    let name: String
    let size: CGFloat
    init(_ name: String, size: CGFloat = 20) { self.name = name; self.size = size }
    var body: some View {
        Image("music-" + name).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}
