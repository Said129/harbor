import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct MusicView: View {
    let app: AppModel
    @State private var library: MusicLibrary
    @State private var query = ""
    @State private var category = "Canciones"
    @State private var importFiles = false
    @MainActor init(app: AppModel) {
        self.app = app
        _library = State(initialValue: MusicLibrary(owner: app.user?.id ?? "guest"))
    }
    private var records: [MusicRecord] {
        library.records.filter { query.isEmpty || $0.local.track.title.localizedCaseInsensitiveContains(query) || $0.local.track.artist.localizedCaseInsensitiveContains(query) || ($0.local.track.album?.localizedCaseInsensitiveContains(query) ?? false) }
            .sorted { $0.local.track.title.localizedStandardCompare($1.local.track.title) == .orderedAscending }
    }
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
            Picker("Biblioteca", selection: $category) { Text("Canciones").tag("Canciones"); Text("Álbumes").tag("Álbumes"); Text("Artistas").tag("Artistas") }.pickerStyle(.segmented).padding(.horizontal)
            if let error = library.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
            if library.importing { ProgressView("Importando música…") }
            if library.records.isEmpty {
                ContentUnavailableView { Label("Tu música", image: "nav-music") } description: { Text("Importa archivos de audio desde Archivos para escucharlos en Harbor.") } actions: { Button("Importar archivos") { importFiles = true }.disabled(!library.ready || library.importing) }
            } else if records.isEmpty { ContentUnavailableView.search(text: query) }
            else if category == "Canciones" {
                List {
                    ForEach(records) { record in MusicTrackRow(record: record, owner: library.owner) { MusicPlayback.shared.play(record, queue: records, owner: library.owner) }.swipeActions { Button("Eliminar", role: .destructive) { remove(record) } } }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            } else {
                List {
                    ForEach(groups, id: \.0) { group in
                        NavigationLink {
                            MusicGroupView(title: group.1, records: group.2, owner: library.owner)
                        } label: {
                            HStack(spacing: 12) {
                                MusicCover(record: group.2.first, owner: library.owner).frame(width: 52, height: 52)
                                VStack(alignment: .leading, spacing: 4) { Text(group.1); Text("\(group.2.count) canciones").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden)
            }
        }.background(HarborTheme.background).navigationTitle("Música").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Canciones, álbumes o artistas")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { importFiles = true } label: { MusicGlyph("plus") }.accessibilityLabel("Importar música").disabled(!library.ready || library.importing) } }
            .fileImporter(isPresented: $importFiles, allowedContentTypes: [.audio, .data], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await library.importFiles(urls) }
                case .failure: library.error = "No se pudo abrir la selección de archivos."
                }
            }
            .accessibilityIdentifier("music-library")
    }
    private func remove(_ record: MusicRecord) {
        MusicPlayback.shared.remove(record)
        Task { await library.remove(record) }
    }
}

private struct MusicGroupView: View {
    let title: String
    let records: [MusicRecord]
    let owner: String
    var body: some View {
        List {
            Button { if let first = records.first { MusicPlayback.shared.play(first, queue: records, owner: owner) } } label: { Label("Reproducir", image: "music-play") }
            ForEach(records) { record in MusicTrackRow(record: record, owner: owner) { MusicPlayback.shared.play(record, queue: records, owner: owner) } }
        }.listStyle(.plain).scrollContentBackground(.hidden).background(HarborTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
struct MusicCover: View {
    var record: MusicRecord?
    var owner = "guest"
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            if let image { BoundedArtworkImage(image: image, fit: .fill) }
            else { Image("music-music").resizable().scaledToFit().padding(12).background(HarborTheme.surface) }
        }.clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true).task(id: owner + "|" + (record?.filename ?? "")) {
            image = nil
            if let record, let data = try? await MusicFileService.shared.artwork(record, owner: owner) { image = UIImage(data: data) }
        }
    }
}
private struct MusicTrackRow: View {
    let record: MusicRecord
    let owner: String
    let play: () -> Void
    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                MusicCover(record: record, owner: owner).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.local.track.title).lineLimit(1)
                    Text(record.local.track.artist + (record.local.track.album.map { " · " + $0 } ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if MusicPlayback.shared.owner == owner && MusicPlayback.shared.current?.id == record.id { MusicGlyph(MusicPlayback.shared.paused ? "pause" : "waveform").foregroundStyle(HarborTheme.accent) }
                Text(record.local.track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.contentShape(.rect)
        }.buttonStyle(.plain).accessibilityLabel(record.local.track.title + ", " + record.local.track.artist)
    }
}

struct MusicMiniPlayer: View {
    @Bindable private var player = MusicPlayback.shared
    @State private var expanded = false
    var body: some View {
        if let record = player.current {
            HStack(spacing: 12) {
                Button { expanded = true } label: {
                    HStack(spacing: 10) {
                        MusicCover(record: record, owner: player.owner).frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.local.track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(player.pausedForVideo ? "Reanudar música" : record.local.track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain).accessibilityLabel("Abrir reproductor de Música")
                Button { player.togglePause() } label: { MusicGlyph(player.paused ? "play" : "pause").frame(width: 44, height: 44) }.accessibilityLabel(player.paused ? "Reproducir música" : "Pausar música")
                Button { player.next() } label: { MusicGlyph("next").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente canción")
            }.padding(.horizontal, 14).padding(.vertical, 7).background(HarborTheme.surface)
                .sheet(isPresented: $expanded) { NavigationStack { MusicPlayerView().toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { expanded = false } } } } }
        }
    }
}

struct MusicPlayerView: View {
    @Bindable private var player = MusicPlayback.shared
    @State private var seek = 0.0
    @State private var editing = false
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let record = player.current {
                    MusicCover(record: record, owner: player.owner).frame(width: 180, height: 180)
                    VStack(spacing: 5) { Text(record.local.track.title).font(.title2.bold()); Text(record.local.track.artist).foregroundStyle(.secondary); if let album = record.local.track.album { Text(album).font(.caption).foregroundStyle(.secondary) } }.multilineTextAlignment(.center)
                    transport
                    if let error = player.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Cola de reproducción", image: "music-queue").font(.headline)
                        ForEach(player.queue) { record in
                            MusicTrackRow(record: record, owner: player.owner) { player.play(record, queue: player.queue, owner: player.owner) }
                        }
                    }
                    Button("Detener reproducción", role: .destructive) { player.stop() }
                } else { ContentUnavailableView("Sin reproducción", image: "nav-music") }
            }.padding(24)
        }.background(HarborTheme.background).navigationTitle("Música").navigationBarTitleDisplayMode(.inline)
            .onChange(of: player.position) { _, value in if !editing { seek = value } }
            .onChange(of: player.current?.id) { _, _ in editing = false; seek = 0 }
    }
    private var transport: some View {
        VStack(spacing: 14) {
            Slider(value: $seek, in: 0...max(player.duration, 1)) { edit in editing = edit; if !edit { player.seek(seek) } }.accessibilityLabel("Posición de la canción")
            HStack { Text(time(editing ? seek : player.position)); Spacer(); Text(time(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { player.shuffle.toggle() } label: { MusicGlyph("shuffle").foregroundStyle(player.shuffle ? HarborTheme.accent : .secondary).frame(width: 44, height: 44) }.accessibilityLabel("Aleatorio").accessibilityValue(player.shuffle ? "Activado" : "Desactivado")
                Button { player.previous() } label: { MusicGlyph("previous").frame(width: 44, height: 44) }.accessibilityLabel("Canción anterior")
                Button { player.togglePause() } label: { MusicGlyph(player.paused ? "play" : "pause", size: 28).foregroundStyle(HarborTheme.background).frame(width: 54, height: 54).background(HarborTheme.ink, in: .circle) }.accessibilityLabel(player.paused ? "Reproducir" : "Pausar")
                Button { player.next() } label: { MusicGlyph("next").frame(width: 44, height: 44) }.accessibilityLabel("Siguiente canción")
                Menu { Picker("Repetición", selection: $player.repeatMode) { ForEach(MusicRepeat.allCases) { Text($0.title).tag($0) } } } label: { MusicGlyph(player.repeatMode == .one ? "repeat-one" : "repeat").foregroundStyle(player.repeatMode == .off ? .secondary : HarborTheme.accent).frame(width: 44, height: 44) }.accessibilityLabel(player.repeatMode.title)
            }.buttonStyle(.plain)
            Slider(value: Binding(get: { player.volume }, set: { player.changeVolume($0) }), in: 0...100) { Text("Volumen") } minimumValueLabel: { MusicGlyph("volume-low") } maximumValueLabel: { MusicGlyph("volume-high") }
        }
    }
    private func time(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(max(0, min(seconds, 31_536_000))) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

private struct MusicGlyph: View {
    let name: String
    let size: CGFloat
    init(_ name: String, size: CGFloat = 20) { self.name = name; self.size = size }
    var body: some View {
        Image("music-" + name).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
    }
}
