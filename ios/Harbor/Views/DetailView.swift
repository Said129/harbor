import SwiftUI

struct DetailView: View {
    let app: AppModel
    @State private var model: DetailModel
    @State private var showStreams = false
    @State private var selectedEpisode: Episode?
    @State private var pendingEpisode: Episode?
    @State private var pendingEpisodeOwner: String?
    @State private var autoplayEpisode = false
    @State private var resolutionTask: Task<Void, Never>?
    @State private var downloading = false
    @State private var downloadMessage: String?
    @AppStorage("downloadsCellular") private var cellularDownloads = false
    private let playImmediately: Bool
    init(media: Media, app: AppModel, playImmediately: Bool = false) { self.app = app; self.playImmediately = playImmediately; _model = State(initialValue: DetailModel(media, service: app.service)) }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Artwork(url: model.media.background, fallback: model.media.fallbackBackground, fallbacks: [model.media.poster].compactMap { $0 }, maxPixels: 1400)
                    .frame(height: 220).clipped()
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.media.name).font(.largeTitle.bold()).accessibilityIdentifier("detail-title")
                    Text([model.media.releaseInfo, model.media.genres?.joined(separator: " · ")].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    Text(model.media.description ?? "").accessibilityIdentifier("detail-description")
                    HStack {
                        Button { Task { await app.library.toggleBookmark(model.media) } } label: { Label(app.library.bookmarked(model.media) ? "En mi lista" : "Añadir a mi lista", image: "ui-library") }.accessibilityIdentifier("detail-bookmark")
                        Spacer()
                        if InterfacePreferences.shared.showWatchedButton {
                            Button { Task { await app.library.toggleWatched(model.media) } } label: { Image(app.library.watched(model.media) ? "ui-mark-unwatched" : "ui-mark-watched").resizable().scaledToFit().frame(width: 26, height: 26) }.accessibilityLabel(app.library.watched(model.media) ? "Marcar como no visto" : "Marcar como visto")
                        }
                    }.disabled(app.library.busy)
                    if let error = app.library.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    if let error = model.error { Text(error).foregroundStyle(.orange) }
                    if model.loading { ProgressView() }
                    if !model.media.episodic {
                        Button { openStreams() } label: { Label("Ver streams", systemImage: "play.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).accessibilityIdentifier("detail-streams")
                    }
                    if model.media.episodic { EpisodeList(media: model.media, library: app.library, play: openStreams) }
                    if let cast = model.media.cast, !cast.isEmpty { Text("Reparto").font(.headline); Text(cast.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
                    if let directors = model.media.director, !directors.isEmpty { Text("Dirección").font(.headline); Text(directors.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
                }.padding()
            }
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
        .task { await model.load(app.addons); if playImmediately && !model.media.episodic { openStreams() } }
        .sheet(isPresented: $showStreams, onDismiss: { resolutionTask?.cancel(); model.pendingPlayback = nil; model.showResumePrompt = false; pendingEpisode = nil; pendingEpisodeOwner = nil; autoplayEpisode = false; model.clearSourceChange() }) {
            NavigationStack {
                List {
                    if model.loadingStreams { ProgressView("Consultando addons…") }
                    if let error = model.error { Text(error).foregroundStyle(.orange) }
                    if !model.warnings.isEmpty && model.offers.isEmpty && !model.loadingStreams { Text("Algunos addons no han respondido. Puedes volver a intentarlo.").font(.caption) }
                    if let downloadMessage { Text(downloadMessage).font(.caption).foregroundStyle(.secondary) }
                    ForEach(model.offers) { offer in
                        HStack(spacing: 14) {
                            Button { resolutionTask = Task { await model.play(offer, resume: app.resume, library: app.library) } } label: { VStack(alignment: .leading, spacing: 8) { Text(offer.title); Text("\(offer.source) · \(offer.quality)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }.buttonStyle(.borderless).disabled(model.resolving || model.pendingPlayback != nil).accessibilityIdentifier("stream-offer")
                            if ["movie", "series", "anime", "music"].contains(model.media.type) {
                                Button { Task { await download(offer) } } label: { Image("nav-download").resizable().scaledToFit().frame(width: 24, height: 24).frame(width: 38, height: 44) }.buttonStyle(.borderless).disabled(downloading).accessibilityLabel("Descargar esta fuente")
                            }
                        }
                    }
                }.navigationTitle(selectedEpisode.map { "T\($0.season ?? 0) · E\($0.episode ?? 0) · Streams" } ?? "Streams").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showStreams = false } } }
                .fullScreenCover(item: $model.playback, onDismiss: playerDismissed) { session in
                    PlayerView(session: session, resume: session.resumeStore ?? app.resume, title: model.media.name, media: model.media, library: app.library, changeEpisode: { episode in
                        guard session.owner == app.library.owner else { return }
                        pendingEpisode = episode; pendingEpisodeOwner = session.owner
                        model.playback = nil
                    }, changeSource: { snapshot in
                        guard session.owner == app.library.owner else { return }
                        model.prepareSourceChange(session, snapshot: snapshot)
                    })
                }
                .alert("¿Reanudar la reproducción?", isPresented: $model.showResumePrompt) {
                    Button("Reanudar") { model.chooseResume(true, owner: app.library.owner) }
                    Button("Desde el principio") { model.chooseResume(false, owner: app.library.owner) }
                    Button("Cancelar", role: .cancel) { model.pendingPlayback = nil }
                } message: {
                    Text("Continuar desde el minuto \(((model.pendingPlayback?.startMs ?? 0) / 60_000).formatted(.number.precision(.fractionLength(0)))).")
                }
                .task(id: selectedEpisode?.id ?? model.media.id) {
                    let owner = app.library.owner
                    let shouldAutoplay = autoplayEpisode
                    autoplayEpisode = false
                    await model.findStreams(app.addons, episode: selectedEpisode)
                    guard !Task.isCancelled, owner == app.library.owner, shouldAutoplay else { return }
                    if let offer = model.continuationOffer {
                        await model.play(offer, resume: app.resume, library: app.library)
                    }
                }
            }.presentationDetents([.medium, .large])
        }
    }
    private func openStreams(_ episode: Episode? = nil) {
        model.clearSourceChange()
        autoplayEpisode = false
        selectedEpisode = episode
        showStreams = true
    }
    private func playerDismissed() {
        guard let episode = pendingEpisode else { return }
        let owner = pendingEpisodeOwner
        pendingEpisode = nil; pendingEpisodeOwner = nil
        guard showStreams, owner == app.library.owner, episode.available else { return }
        // Present the next session only after the old full-screen player has
        // dismissed and released its native surface.
        autoplayEpisode = true
        selectedEpisode = episode
    }
    private func download(_ offer: StreamOffer) async {
        guard !downloading else { return }
        downloading = true; downloadMessage = nil
        defer { downloading = false }
        let owner = app.user?.id ?? "guest", media = model.media, episode = selectedEpisode
        do {
            let source = try await app.service.resolve(offer)
            guard owner == (app.user?.id ?? "guest") else { return }
            try DownloadManager.shared.start(source: source, media: media, episode: episode, owner: owner, cellular: cellularDownloads)
            downloadMessage = "Descarga añadida. Puedes verla en Descargas."
        } catch { downloadMessage = safeMessage(error) }
    }
}
