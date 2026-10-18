import SwiftUI

private enum DownloadFilter: String, CaseIterable, Identifiable {
    case all, active, saved, issues
    var id: String { rawValue }
    var title: String { switch self { case .all: "Todo"; case .active: "Activas"; case .saved: "Guardadas"; case .issues: "Problemas" } }
    func includes(_ item: DownloadItem) -> Bool {
        switch self { case .all: true; case .active: item.status.isActive; case .saved: item.status == .complete; case .issues: item.status == .failed }
    }
}

struct DownloadsView: View {
    let app: AppModel
    @Bindable private var downloads = DownloadManager.shared
    @AppStorage("downloadsCellular") private var cellular = false
    @State private var filter = DownloadFilter.all
    @State private var query = ""
    @State private var preparation: UUID?
    @State private var playback: PlaybackSession?
    @State private var playbackMedia: Media?
    @State private var error: String?
    private var owner: String { app.user?.id ?? "guest" }
    private var allItems: [DownloadItem] { downloads.list(owner: owner) }
    private var items: [DownloadItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return allItems.filter { filter.includes($0) && (search.isEmpty || $0.title.localizedStandardContains(search)) }
    }
    private var savedBytes: Int64 {
        var bytes: Int64 = 0
        for item in allItems where item.status == .complete {
            let (total, overflow) = bytes.addingReportingOverflow(max(0, item.received))
            if overflow { return .max }
            bytes = total
        }
        return bytes
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file) }
    private func transferSize(_ item: DownloadItem) -> String {
        item.expected > 0 && item.status.isActive ? "\(size(item.received)) / \(size(item.expected))" : size(item.received)
    }
    private func remove(_ item: DownloadItem) {
        guard downloads.list(owner: owner).contains(where: { $0.id == item.id }) else { return }
        downloads.remove(item, owner: owner)
    }
    private func toggle(_ item: DownloadItem) {
        downloads.toggle(item, owner: owner)
    }
    private func clearPresentation() {
        preparation = nil; playback = nil
        playbackMedia = nil; error = nil; query = ""; filter = .all
    }
    private func row(_ item: DownloadItem) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Artwork(url: item.media.poster, fallback: item.media.fallbackPoster, maxPixels: 260).frame(width: 52, height: 78).clipShape(.rect(cornerRadius: 6)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack { Text(item.status.title); Spacer(); Text(transferSize(item)) }.font(.caption).foregroundStyle(.secondary)
                if item.status.isActive {
                    if let fraction = item.fraction {
                        ProgressView(value: fraction).accessibilityLabel("Progreso de descarga").accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
                        Text(fraction.formatted(.percent.precision(.fractionLength(0)))).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    } else if item.status == .downloading { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                    Button(item.status == .paused ? "Reanudar" : "Pausar") { toggle(item) }.buttonStyle(.borderless).font(.caption).frame(minHeight: 44)
                }
                if let message = item.message { Text(message).font(.caption).foregroundStyle(.orange) }
                if item.status == .failed {
                    NavigationLink("Elegir otra fuente") { DetailView(media: item.media, app: app) }.font(.caption).frame(minHeight: 44)
                }
                if item.status == .complete {
                    HStack {
                        Button { Task { await play(item) } } label: { Label("Reproducir", image: "ui-play-filled") }.buttonStyle(.borderless).disabled(preparation != nil).frame(minHeight: 44)
                        Spacer()
                        if let file = try? downloads.file(item) { ShareLink(item: file) { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel("Compartir archivo") }
                    }.font(.caption)
                }
            }
        }.padding(.vertical, 5)
            .swipeActions { Button(item.status.isActive ? "Cancelar" : "Eliminar", role: .destructive) { remove(item) } }
    }
    var body: some View {
        List {
            Section {
                if !allItems.isEmpty {
                    HStack { Text("\(allItems.count) archivos"); Spacer(); Text("\(size(savedBytes)) guardados") }.font(.caption).foregroundStyle(.secondary)
                }
                Picker("Mostrar", selection: $filter) { ForEach(DownloadFilter.allCases) { value in Text("\(value.title) (\(allItems.filter { value.includes($0) }.count))").tag(value) } }
                Toggle("Permitir datos móviles", isOn: $cellular)
            } footer: { Text("Añade una descarga desde el botón junto a una fuente. Algunas fuentes requieren mantener Harbor abierto durante la transferencia.") }
            if let message = error ?? downloads.error { Section { Text(message).font(.caption).foregroundStyle(.orange) } }
            ForEach(items) { item in row(item) }
            if items.isEmpty { ContentUnavailableView(allItems.isEmpty ? "Sin descargas" : "Sin resultados", image: "nav-download", description: Text(allItems.isEmpty ? "Los archivos que guardes aparecen aquí." : "Prueba con otro filtro o búsqueda.")) }
        }.navigationTitle("Descargas").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Buscar en descargas")
            .onChange(of: owner) { _, _ in clearPresentation() }
            .fullScreenCover(item: $playback) { session in PlayerView(session: session, resume: session.resumeStore ?? app.resume, title: playbackMedia?.name ?? "Harbor", media: playbackMedia, library: app.library) }
    }
    private func play(_ item: DownloadItem) async {
        guard preparation == nil, item.status == .complete, allItems.contains(where: { $0.id == item.id && $0.status == .complete }) else { return }
        let expectedOwner = owner, store = app.resume, operation = UUID()
        preparation = operation; error = nil
        defer { if preparation == operation { preparation = nil } }
        do {
            let file = try downloads.file(item)
            guard FileManager.default.fileExists(atPath: file.path) else { throw HarborError(code: "download-missing") }
            let cloud = await app.library.resume(for: item.target, refresh: false)
            let start = try await store.position(item.target, durationMs: cloud?.durationMs ?? 0, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false, cloud: cloud?.entry)
            guard expectedOwner == owner, preparation == operation, allItems.contains(where: { $0.id == item.id && $0.status == .complete }), FileManager.default.fileExists(atPath: file.path) else { return }
            playbackMedia = item.media
            playback = PlaybackSession(source: PlaybackSource(url: file.path, headers: nil, subtitles: nil, via: "download"), target: item.target, startMs: start.ms, storageWarning: nil, progressEnabled: true, owner: expectedOwner, resumeStore: store, promptForResume: start.prompt)
        } catch { if expectedOwner == owner, preparation == operation { self.error = safeMessage(error) } }
    }
}
