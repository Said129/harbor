import SwiftUI

struct DetailView: View {
    let app: AppModel
    @State private var model: DetailModel
    @State private var showStreams = false
    @State private var selectedEpisode: Episode?
    @State private var pendingEpisode: Episode?
    @State private var pendingEpisodeOwner: String?
    @State private var autoplayEpisode = false
    @State private var continuingEpisode = false
    @State private var resolutionTask: Task<Void, Never>?
    @State private var downloading = false
    @State private var downloadMessage: String?
    @State private var logoLoaded = false
    @State private var actionHint: String?
    @State private var actionHintRevision = 0
    @State private var showConnecting = false
    @AppStorage("downloadsCellular") private var cellularDownloads = false
    private let playImmediately: Bool
    init(media: Media, app: AppModel, playImmediately: Bool = false) { self.app = app; self.playImmediately = playImmediately; _model = State(initialValue: DetailModel(media, service: app.service)) }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                hero
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.media.description ?? "").font(HarborTheme.font(16)).lineSpacing(5).foregroundStyle(HarborTheme.ink.opacity(0.7)).textSelection(.enabled).accessibilityIdentifier("detail-description")
                    if let error = app.library.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    if let error = model.error { Text(error).foregroundStyle(.orange) }
                    if model.loading { ProgressView() }
                    if model.media.episodic { EpisodeList(media: model.media, library: app.library, play: { openStreams($0, automatic: StreamPreferences.shared.automatic) }) }
                }.padding()
                DetailMetadataView(media: model.media, app: app)
            }
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task {
            let owner = app.library.owner
            await model.load(app.addons, owner: owner, library: app.library)
            guard !Task.isCancelled, owner == app.library.owner else { return }
            if playImmediately { playTitle() }
            await model.loadRelated(app.addons, owner: owner, library: app.library)
        }
        .onChange(of: model.media.logo) { _, _ in logoLoaded = false }
        .sheet(isPresented: $showStreams, onDismiss: { resolutionTask?.cancel(); model.pendingPlayback = nil; model.showResumePrompt = false; pendingEpisode = nil; pendingEpisodeOwner = nil; autoplayEpisode = false; showConnecting = false; model.clearSourceChange() }) {
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
                .overlay {
                    if model.resolving || (showConnecting && model.loadingStreams) {
                        HarborPlaybackConnecting(media: model.media) { resolutionTask?.cancel(); showStreams = false }
                    }
                }
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
                    let isContinuation = continuingEpisode
                    autoplayEpisode = false
                    continuingEpisode = false
                    await model.findStreams(app.addons, episode: selectedEpisode)
                    guard !Task.isCancelled, owner == app.library.owner, shouldAutoplay else { return }
                    if let offer = isContinuation ? model.continuationOffer : StreamPreferences.shared.preferred(model.offers) {
                        await model.play(offer, resume: app.resume, library: app.library)
                    }
                }
            }.presentationDetents(showConnecting ? [.large] : [.medium, .large])
        }
    }
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: model.media.background, fallback: model.media.fallbackBackground, fallbacks: [model.media.poster].compactMap { $0 }, maxPixels: 1400).frame(height: 370).clipped()
            LinearGradient(colors: [.black.opacity(0.12), HarborTheme.background.opacity(0.45), HarborTheme.background], startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 18) {
                if let tagline = model.media.details?.tagline, !tagline.isEmpty { Text(tagline.uppercased()).font(HarborTheme.font(10, weight: .medium)).tracking(2).foregroundStyle(.secondary).lineLimit(2) }
                titlePlate
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        if let year = model.media.releaseInfo { badge(year) }
                        if let rating = model.media.imdbRating { ratingBadge(rating) }
                        if let runtime = model.media.runtime { badge(runtime) }
                        ForEach(model.media.genres ?? [], id: \.self) { badge($0) }
                    }
                }.scrollIndicators(.hidden)
                primaryActions
                secondaryActions
                if let error = app.library.favorites.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.padding(20)
        }.frame(minHeight: 370)
    }
    private var titlePlate: some View {
        ZStack(alignment: .bottomLeading) {
            Text(model.media.name).font(.custom("Fraunces-9ptBlack", size: 34).weight(.medium)).lineLimit(3).foregroundStyle(logoLoaded ? Color.clear : HarborTheme.ink).accessibilityIdentifier("detail-title").accessibilityAddTraits(.isHeader)
            if let logo = model.media.logo { Artwork(url: logo, fit: .fit, maxPixels: 800, showsPlaceholder: false, onImageAvailability: { logoLoaded = $0 }).frame(maxWidth: 310).frame(height: 96).accessibilityHidden(true) }
        }.frame(minHeight: 96, alignment: .bottomLeading)
    }
    private var primaryActions: some View {
        HStack(spacing: 10) {
                    Button { playTitle() } label: { HStack(spacing: 10) { glyph("ui-play-filled", size: 15); Text("Reproducir").font(HarborTheme.font(15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85) }.padding(.horizontal, 22).frame(minHeight: 48).foregroundStyle(.black).background(.white, in: .capsule) }.buttonStyle(.plain).disabled(model.loadingMetadata || (model.media.episodic && (model.media.videos ?? []).isEmpty)).accessibilityIdentifier("detail-play")
                    Button { Task { await app.library.toggleBookmark(model.media); if app.library.error == nil { showHint("bookmark") } } } label: { HStack(spacing: 8) { glyph(app.library.bookmarked(model.media) ? "music-check" : "music-plus", size: 16); Text(app.library.bookmarked(model.media) ? "En mi lista" : "Añadir a mi lista").font(HarborTheme.font(14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85) }.padding(.horizontal, 16).frame(minHeight: 48).background(app.library.bookmarked(model.media) ? HarborTheme.accent.opacity(0.2) : HarborTheme.background.opacity(0.8), in: .capsule) }.buttonStyle(.plain).disabled(app.library.busy).accessibilityLabel(app.library.bookmarked(model.media) ? "En mi lista" : "Añadir a mi lista").accessibilityIdentifier("detail-bookmark")
                        .modifier(HarborActionHint(id: "bookmark", title: app.library.bookmarked(model.media) ? "En mi lista" : "Añadir a mi lista", selected: actionHint))
                }
    }
    private var secondaryActions: some View {
        HStack(spacing: 10) {
                    Button { app.library.favorites.toggle(model.media); if app.library.favorites.error == nil { showHint("favorite") } } label: {
                        glyph(app.library.favorites.contains(model.media) ? "ui-unfavorite" : "ui-favorite", size: 20).frame(width: 48, height: 48).foregroundStyle(app.library.favorites.contains(model.media) ? HarborTheme.accent : HarborTheme.ink).background(HarborTheme.background.opacity(0.8), in: .circle)
                    }.buttonStyle(.plain).disabled(!app.library.favorites.ready).accessibilityLabel(app.library.favorites.contains(model.media) ? "Quitar de favoritos" : "Añadir a favoritos").accessibilityIdentifier("detail-favorite")
                        .modifier(HarborActionHint(id: "favorite", title: app.library.favorites.contains(model.media) ? "Favorito" : "Añadir a favoritos", selected: actionHint))
                    if InterfacePreferences.shared.showWatchedButton { Button { Task { await app.library.toggleWatched(model.media); if app.library.error == nil { showHint("watched") } } } label: { glyph(app.library.watched(model.media) ? "ui-mark-unwatched" : "ui-mark-watched", size: 21).frame(width: 48, height: 48).background(HarborTheme.background.opacity(0.8), in: .circle) }.buttonStyle(.plain).disabled(app.library.busy).accessibilityLabel(app.library.watched(model.media) ? "Marcar como no visto" : "Marcar como visto").modifier(HarborActionHint(id: "watched", title: app.library.watched(model.media) ? "Marcado como visto" : "Marcar como visto", selected: actionHint)) }
                    if !model.media.episodic { Button { openStreams() } label: { HStack(spacing: 8) { glyph("nav-playlist", size: 18); Text("Fuentes").font(HarborTheme.font(14, weight: .medium)) }.padding(.horizontal, 16).frame(minHeight: 48).background(HarborTheme.background.opacity(0.8), in: .capsule) }.buttonStyle(.plain).accessibilityIdentifier("detail-streams") }
                }
        .task(id: actionHintRevision) {
            guard actionHint != nil else { return }
            do { try await Task.sleep(for: .seconds(1.8)); withAnimation(.easeOut(duration: 0.2)) { actionHint = nil } } catch {}
        }
    }
    private func showHint(_ action: String) { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { actionHint = action; actionHintRevision &+= 1 } }
    private func badge(_ text: String) -> some View { Text(text).font(HarborTheme.font(11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 6).background(.black.opacity(0.5), in: .capsule) }
    private func glyph(_ name: String, size: CGFloat) -> some View { Image(name).resizable().scaledToFit().frame(width: size, height: size) }
    private func ratingBadge(_ rating: String) -> some View {
        HStack(spacing: 6) { Text(model.media.ratingSource ?? "IMDb").font(.system(size: 9, weight: .black)).foregroundStyle(.black).padding(.horizontal, 3).padding(.vertical, 2).background(model.media.ratingSource == "TMDB" ? Color.mint : .yellow, in: .rect(cornerRadius: 2)); Text(rating).font(HarborTheme.font(12, weight: .semibold)) }.padding(.horizontal, 10).padding(.vertical, 5).background(HarborTheme.background.opacity(0.85), in: .capsule)
    }
    private func openStreams(_ episode: Episode? = nil, automatic: Bool = false) {
        model.clearSourceChange()
        autoplayEpisode = automatic
        showConnecting = automatic
        continuingEpisode = false
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
        continuingEpisode = true
        selectedEpisode = episode
    }
    private func playTitle() {
        if !model.media.episodic { openStreams(automatic: StreamPreferences.shared.automatic); return }
        let episodes = WatchedCodec.ordered(model.media.videos ?? []).filter(\.available)
        let record = app.library.items.first { $0.id == model.media.id }
        let coordinates = record?.playbackCoordinates
        let resumed = episodes.first { $0.id == record?.raw["state"]["video_id"].string || ($0.season == coordinates?.season && $0.episode == coordinates?.episode) }
        let watched = app.library.watchedEpisodes(model.media)
        if let episode = resumed ?? episodes.first(where: { !watched.contains($0.watchedKey) && ($0.season ?? 1) > 0 }) ?? episodes.first {
            openStreams(episode, automatic: StreamPreferences.shared.automatic)
        }
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
