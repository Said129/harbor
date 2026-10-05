import SwiftUI

struct DownloadsView: View {
    let app: AppModel
    @Bindable private var downloads = DownloadManager.shared
    @AppStorage("downloadsCellular") private var cellular = false
    @State private var filter = "all"
    @State private var playback: PlaybackSession?
    @State private var pending: PlaybackSession?
    @State private var showResume = false
    @State private var playbackMedia: Media?
    @State private var error: String?
    private var items: [DownloadItem] {
        downloads.list(owner: app.user?.id ?? "guest").filter {
            switch filter {
            case "active": $0.status == .downloading || $0.status == .paused
            case "saved": $0.status == .complete
            case "issues": $0.status == .failed
            default: true
            }
        }
    }
    var body: some View {
        List {
            Section {
                Picker("Mostrar", selection: $filter) {
                    Text("Todo").tag("all"); Text("Activas").tag("active")
                    Text("Guardadas").tag("saved"); Text("Problemas").tag("issues")
                }
                Toggle("Permitir datos móviles", isOn: $cellular)
            } footer: { Text("Añade una descarga desde el botón junto a una fuente. Algunas fuentes requieren mantener Harbor abierto durante la transferencia.") }
            if let message = error ?? downloads.error { Section { Text(message).font(.caption).foregroundStyle(.orange) } }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 13) {
                    Artwork(url: item.media.poster, fallback: item.media.fallbackPoster, maxPixels: 260).frame(width: 52, height: 78).clipShape(.rect(cornerRadius: 6)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        HStack { Text(item.status.title); Spacer(); Text(ByteCountFormatter.string(fromByteCount: item.received, countStyle: .file)) }.font(.caption).foregroundStyle(.secondary)
                        if item.status == .downloading || item.status == .paused {
                            if let fraction = item.fraction { ProgressView(value: fraction) } else { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                            Button(item.status == .paused ? "Reanudar" : "Pausar") { downloads.toggle(item) }.buttonStyle(.borderless).font(.caption)
                        }
                        if let message = item.message { Text(message).font(.caption).foregroundStyle(.orange) }
                        if item.status == .complete {
                            HStack {
                                Button { Task { await play(item) } } label: { Label("Reproducir", image: "ui-play-filled") }.buttonStyle(.borderless)
                                Spacer()
                                if let file = try? downloads.file(item) { ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }.buttonStyle(.borderless).accessibilityLabel("Compartir archivo") }
                            }.font(.caption)
                        }
                    }
                }.padding(.vertical, 5)
                    .swipeActions { Button("Eliminar", role: .destructive) { downloads.remove(item) } }
            }
            if items.isEmpty { ContentUnavailableView("Sin descargas", image: "nav-downloads", description: Text("Los archivos que guardes aparecen aquí.")) }
        }.navigationTitle("Descargas").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $playback) { session in PlayerView(session: session, resume: session.resumeStore ?? app.resume, title: playbackMedia?.name ?? "Harbor", media: playbackMedia, library: app.library) }
            .alert("¿Reanudar la reproducción?", isPresented: $showResume) {
                Button("Reanudar") { playback = pending; pending = nil }
                Button("Desde el principio") {
                    if let session = pending { playback = PlaybackSession(source: session.source, target: session.target, startMs: 0, storageWarning: session.storageWarning, progressEnabled: session.progressEnabled, owner: session.owner, resumeStore: session.resumeStore) }
                    pending = nil
                }
                Button("Cancelar", role: .cancel) { pending = nil }
            } message: { Text("Continuar desde el minuto \(((pending?.startMs ?? 0) / 60_000).formatted(.number.precision(.fractionLength(0)))).") }
    }
    private func play(_ item: DownloadItem) async {
        let owner = app.user?.id ?? "guest", store = app.resume
        do {
            let file = try downloads.file(item)
            guard FileManager.default.fileExists(atPath: file.path) else { throw HarborError(code: "download-missing") }
            let cloud = await app.library.resume(for: item.target, refresh: false)
            let start = try await store.position(item.target, durationMs: cloud?.durationMs ?? 0, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false, cloud: cloud?.entry)
            guard owner == (app.user?.id ?? "guest") else { return }
            playbackMedia = item.media
            let session = PlaybackSession(source: PlaybackSource(url: file.path, headers: nil, subtitles: nil, via: "download"), target: item.target, startMs: start.ms, storageWarning: nil, progressEnabled: true, owner: owner, resumeStore: store)
            if start.prompt { pending = session; showResume = true } else { playback = session }
        } catch { self.error = safeMessage(error) }
    }
}
