import SwiftUI

struct DetailView: View {
    let app: AppModel
    @State private var model: DetailModel
    @State private var showStreams = false
    @State private var selectedEpisode: Episode?
    @State private var streamSelection: MediaPlaybackSelection?
    @State private var pendingExtra: AnimeFranchiseExtra?
    @State private var resolvingExtra = false
    @State private var extraTask: Task<Void, Never>?
    @State private var pendingEpisode: Episode?
    @State private var pendingEpisodeOwner: String?
    @State private var autoplayEpisode = false
    @State private var continuingEpisode = false
    @State private var resolutionTask: Task<Void, Never>?
    @State private var franchiseSwitchTask: Task<Void, Never>?
    @State private var downloading = false
    @State private var downloadMessage: String?
    @State private var logoLoaded = false
    @State private var actionHint: String?
    @State private var actionHintRevision = 0
    @State private var showConnecting = false
    @State private var selectionRevision = 0
    @Environment(\.openURL) private var openURL
    @AppStorage("downloadsCellular") private var cellularDownloads = false
    @AppStorage("tvdbSeasonType") private var episodeOrderSetting = "aired"
    @AppStorage("tvdbOrderPanel") private var richEpisodeOrderPanel = true
    private let playImmediately: Bool
    init(media: Media, app: AppModel, playImmediately: Bool = false, metadataLoaded: Bool = false) { self.app = app; self.playImmediately = playImmediately; _model = State(initialValue: DetailModel(media, service: app.service, metadataLoaded: metadataLoaded)) }

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
                    if model.isAnimeOneOff {
                        animeMovieSection
                    } else if model.media.type != "movie" && model.media.episodic { EpisodeList(media: model.media, library: app.library,
                        animeGrouping: model.episodeOrderProjection == nil && model.allowsContinuousAnimeEpisodes ? Binding(get: { model.animeEpisodeGrouping }, set: { model.setAnimeEpisodeGrouping($0) }) : nil,
                        ordering: model.episodeOrderProjection, pool: model.episodePool, orderOptions: model.episodeOrderOptions,
                        selectOrder: { episodeOrderSetting = $0.rawValue }, richOrderPanel: richEpisodeOrderPanel, orderLoading: model.episodeOrderLoading,
                        franchise: model.franchiseChoices, activeFranchiseID: model.activeFranchiseEntryID, selectFranchise: selectFranchise,
                        franchiseLoading: model.loadingFranchise || model.loadingMetadata, loadingExtras: model.loadingExtraEntries,
                        playExtra: { openExtra($0) }, toggleExtraWatched: toggleExtraWatched,
                        play: { openStreams($0, automatic: StreamPreferences.shared.automatic) })
                        if let source = model.episodeMetadataURL {
                            Link("TheTVDB", destination: source).font(.caption).foregroundStyle(.secondary)
                                .frame(minHeight: 44).accessibilityIdentifier("episode-metadata-source")
                        }
                    } else if model.franchiseChoices.count > 1 {
                        AnimeSeasonPicker(entries: model.franchiseChoices, activeID: model.activeFranchiseEntryID, select: selectFranchise,
                            loading: model.loadingFranchise || model.loadingMetadata)
                    }
                }.padding()
                DetailMetadataView(media: model.media, app: app)
            }
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .background { PlayerOrientationAnchor(enabled: showStreams && (showConnecting || model.resolving || model.playback != nil || pendingEpisode != nil)).allowsHitTesting(false) }
        .task {
            let owner = app.library.owner
            let selected = model.media
            await model.load(app.addons, owner: owner, library: app.library) {
                try await app.continuationMetadata(selected)
            }
            guard !Task.isCancelled, owner == app.library.owner else { return }
            app.library.discovery.track(.open, media: model.media)
            if playImmediately { playTitle() }
        }
        .task(id: "related:\(model.media.identity):\(model.metadataReady)") {
            if model.metadataReady { await model.loadRelated(app.addons, owner: app.library.owner, library: app.library) }
        }
        .task(id: "franchise:\(model.media.identity):\(model.canLoadFranchise)") {
            await model.loadFranchise(owner: app.library.owner, library: app.library)
        }
        .onChange(of: model.media.logo) { _, _ in logoLoaded = false }
        .task(id: "\(model.media.identity):\(model.loadingMetadata):\(model.media.videos?.count ?? 0)") {
            await model.loadAnimeEpisodes(owner: app.library.owner, library: app.library)
        }
        .task(id: "\(model.media.identity):\(model.canLoadEpisodeOrder):\(model.episodeOrderScope):\(episodeOrderSetting):\(MetadataPreferences.shared.language)") {
            await model.loadEpisodeOrder(setting: episodeOrderSetting, language: MetadataPreferences.shared.language, owner: app.library.owner, library: app.library)
        }
        .task(id: episodePoolTaskID) {
            await model.loadFranchiseEpisodes(language: MetadataPreferences.shared.language, owner: app.library.owner, library: app.library)
        }
        .onChange(of: model.playback?.id) { _, _ in
            if let session = model.playback, session.owner == app.library.owner { app.library.discovery.track(.play, media: session.media ?? model.media) }
        }
        .onChange(of: model.franchiseSelectionRevision) { _, _ in
            selectionRevision &+= 1; actionHintRevision &+= 1
            resolutionTask?.cancel(); selectedEpisode = nil; pendingEpisode = nil; pendingEpisodeOwner = nil
            extraTask?.cancel(); streamSelection = nil; pendingExtra = nil; resolvingExtra = false
            showStreams = false; autoplayEpisode = false; continuingEpisode = false; showConnecting = false
            downloadMessage = nil; actionHint = nil
        }
        .onDisappear { franchiseSwitchTask?.cancel(); extraTask?.cancel() }
        .sheet(isPresented: $showStreams, onDismiss: { resolutionTask?.cancel(); extraTask?.cancel(); model.cancelResolution(); pendingEpisode = nil; pendingExtra = nil; pendingEpisodeOwner = nil; streamSelection = nil; resolvingExtra = false; autoplayEpisode = false; showConnecting = false; model.clearSourceChange() }) {
            NavigationStack {
                streamPicker
                .overlay {
                    if model.resolving || resolvingExtra || (showConnecting && model.loadingStreams) {
                        HarborPlaybackConnecting(media: streamSelection?.media ?? model.playbackContextMedia, cancel: chooseSourcesManually)
                    }
                }
                .fullScreenCover(item: $model.playback, onDismiss: playerDismissed) { session in
                    let source = session.media ?? model.media
                    PlayerView(session: session, resume: session.resumeStore ?? app.resume, title: source.name, media: source, library: app.library,
                        episodeOrder: streamSelection == nil ? model.episodeOrderProjection : nil, episodePool: streamSelection == nil ? model.episodePool : nil,
                        loadingExtraEntries: model.loadingExtraEntries, changeExtra: { extra in
                            guard session.owner == app.library.owner else { return }
                            pendingExtra = extra; pendingEpisode = nil; pendingEpisodeOwner = session.owner; model.playback = nil
                        }, toggleExtraWatched: toggleExtraWatched, changeEpisode: { episode in
                        guard session.owner == app.library.owner else { return }
                        pendingEpisode = episode; pendingEpisodeOwner = session.owner
                        model.playback = nil
                    }, changeSource: { snapshot in
                        guard session.owner == app.library.owner else { return }
                        model.prepareSourceChange(session, snapshot: snapshot)
                    })
                }
                .task(id: streamSelection?.key ?? selectedEpisode?.routingKey ?? model.media.id) {
                    guard !resolvingExtra else { return }
                    let owner = app.library.owner, scope = app.accountOperationScope
                    let shouldAutoplay = autoplayEpisode
                    let isContinuation = continuingEpisode
                    let revision = selectionRevision
                    autoplayEpisode = false
                    continuingEpisode = false
                    let task = Task {
                        defer { if revision == selectionRevision, model.playback == nil { showConnecting = false } }
                        await app.refreshAddons()
                        guard !Task.isCancelled, owner == app.library.owner, scope == app.accountOperationScope else { return }
                        await model.findStreams(app.addons, episode: selectedEpisode, selection: streamSelection)
                        guard !Task.isCancelled, owner == app.library.owner, scope == app.accountOperationScope, shouldAutoplay, revision == selectionRevision else { return }
                        if let offer = isContinuation ? model.continuationOffer : StreamPreferences.shared.preferred(model.automaticOffers) {
                            await model.play(offer, resume: app.resume, library: app.library)
                        }
                    }
                    resolutionTask = task
                    await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
                }
            }.presentationDetents([.large])
        }
    }
    private var episodePoolTaskID: String {
        let entries = model.franchiseChoices.map(\.id).joined(separator: ",")
        return "pool:\(model.media.identity):\(model.canLoadEpisodePool):\(model.activeFranchiseEntryID ?? ""):\(entries):\(MetadataPreferences.shared.language)"
    }
    private var streamPicker: StreamPickerView {
        StreamPickerView(model: model, addons: app.addons, episode: selectedEpisode, selection: streamSelection, downloading: downloading, downloadMessage: downloadMessage,
                         play: { offer in playOffer(offer) }, download: streamDownloadAction,
                         refresh: { refreshStreams() }, back: { showStreams = false })
    }
    private var animeMovieSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(DesktopInterfaceText.value("Movie")).font(HarborTheme.displayFont(22))
                Spacer()
                AnimeSeasonPicker(entries: model.franchiseChoices, activeID: model.activeFranchiseEntryID, select: selectFranchise,
                    loading: model.loadingFranchise || model.loadingMetadata)
            }
            AnimeMovieEntryCard(media: model.media, watched: app.library.watched(model.media) || app.library.items.first(where: { $0.id == model.media.id })?.watched == true) {
                openStreams(AnimeOneOffPresentation.playbackEpisode(model.media), automatic: StreamPreferences.shared.automatic)
            }
        }
    }
    private func openExtra(_ extra: AnimeFranchiseExtra, automatic: Bool? = nil) {
        extraTask?.cancel(); resolutionTask?.cancel(); model.cancelResolution()
        selectionRevision &+= 1
        let revision = selectionRevision, owner = app.library.owner, scope = app.accountOperationScope
        resolvingExtra = true; showConnecting = true; showStreams = true
        extraTask = Task {
            let selected = await model.resolveFranchiseExtra(extra, language: MetadataPreferences.shared.language, owner: owner, library: app.library)
            guard !Task.isCancelled, owner == app.library.owner, scope == app.accountOperationScope, revision == selectionRevision else { return }
            resolvingExtra = false
            if let selected { openStreams(selected.episode, automatic: automatic ?? StreamPreferences.shared.automatic, selection: selected) }
            else { showConnecting = false; showStreams = false }
        }
    }
    private func toggleExtraWatched(_ extra: AnimeFranchiseExtra) {
        let owner = app.library.owner, scope = app.accountOperationScope
        Task {
            guard owner == app.library.owner, scope == app.accountOperationScope else { return }
            if let selected = await model.resolveFranchiseExtra(extra, language: MetadataPreferences.shared.language, owner: owner, library: app.library), owner == app.library.owner, scope == app.accountOperationScope {
                await app.library.toggleWatched(selected.media)
            }
        }
    }
    private func selectFranchise(_ entry: AnimeFranchiseEntry) {
        franchiseSwitchTask?.cancel()
        let owner = app.library.owner
        franchiseSwitchTask = Task {
            if await model.selectFranchiseEntry(entry.id, owner: owner, library: app.library) {
                app.library.discovery.track(.open, media: model.media)
            }
        }
    }
    private var streamDownloadAction: ((StreamOffer) -> Void)? {
        guard ["movie", "series", "anime", "music"].contains(model.media.type) else { return nil }
        return { offer in startDownload(offer) }
    }
    private func playOffer(_ offer: StreamOffer) {
        guard !model.resolving, model.playback == nil else { return }
        if let url = offer.pickerExternalURL { openURL(url); return }
        let owner = app.library.owner, scope = app.accountOperationScope
        resolutionTask = Task {
            guard owner == app.library.owner, scope == app.accountOperationScope else { return }
            await model.play(offer, resume: app.resume, library: app.library)
        }
    }
    private func chooseSourcesManually() {
        selectionRevision &+= 1
        if resolvingExtra { extraTask?.cancel(); resolvingExtra = false; showStreams = false }
        autoplayEpisode = false; showConnecting = false
        if model.resolving { resolutionTask?.cancel(); model.cancelResolution() }
    }
    private func refreshStreams() {
        guard !model.loadingStreams, !model.resolving, model.playback == nil else { return }
        resolutionTask?.cancel()
        let owner = app.library.owner, scope = app.accountOperationScope
        resolutionTask = Task {
            await app.refreshAddons(force: true)
            guard owner == app.library.owner, scope == app.accountOperationScope else { return }
            await model.findStreams(app.addons, episode: selectedEpisode, selection: streamSelection)
        }
    }
    private func startDownload(_ offer: StreamOffer) { Task { await download(offer) } }
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
                    Button { Task { await app.library.toggleBookmark(model.media); if app.library.error == nil { showHint("bookmark") } } } label: { HStack(spacing: 8) { glyph(app.library.bookmarked(model.media) ? "music-check" : "music-plus", size: 16); Text(app.library.bookmarked(model.media) ? "En la lista para ver" : "Agregar a la lista de seguimiento").font(HarborTheme.font(14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85) }.padding(.horizontal, 16).frame(minHeight: 48).background(app.library.bookmarked(model.media) ? HarborTheme.accent.opacity(0.2) : HarborTheme.background.opacity(0.8), in: .capsule) }.buttonStyle(.plain).disabled(app.library.busy).accessibilityLabel(app.library.bookmarked(model.media) ? "En la lista para ver" : "Agregar a la lista de seguimiento").accessibilityIdentifier("detail-bookmark")
                        .modifier(HarborActionHint(id: "bookmark", title: app.library.bookmarked(model.media) ? "En la lista para ver" : "Agregar a la lista de seguimiento", selected: actionHint))
                }
    }
    private var secondaryActions: some View {
        HStack(spacing: 10) {
                    Button { app.library.favorites.toggle(model.media); if app.library.favorites.error == nil { showHint("favorite") } } label: {
                        glyph(app.library.favorites.contains(model.media) ? "ui-unfavorite" : "ui-favorite", size: 20).frame(width: 48, height: 48).foregroundStyle(app.library.favorites.contains(model.media) ? HarborTheme.accent : HarborTheme.ink).background(HarborTheme.background.opacity(0.8), in: .circle)
                    }.buttonStyle(.plain).disabled(!app.library.favorites.ready).accessibilityLabel(app.library.favorites.contains(model.media) ? "Quitar de favoritos" : "Agregar a favoritos").accessibilityIdentifier("detail-favorite")
                        .modifier(HarborActionHint(id: "favorite", title: app.library.favorites.contains(model.media) ? "Quitar de favoritos" : "Agregar a favoritos", selected: actionHint))
                    if InterfacePreferences.shared.showWatchedButton { Button { Task { await app.library.toggleWatched(model.media); if app.library.error == nil { showHint("watched") } } } label: { glyph(app.library.watched(model.media) ? "ui-mark-unwatched" : "ui-mark-watched", size: 21).frame(width: 48, height: 48).background(HarborTheme.background.opacity(0.8), in: .circle) }.buttonStyle(.plain).disabled(app.library.busy).accessibilityLabel(app.library.watched(model.media) ? "Marcar como no visto" : "Marcar como visto").modifier(HarborActionHint(id: "watched", title: app.library.watched(model.media) ? "Marcar como no visto" : "Marcar como visto", selected: actionHint)) }
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
    private func openStreams(_ episode: Episode? = nil, automatic: Bool = false, selection: MediaPlaybackSelection? = nil) {
        selectionRevision &+= 1
        model.clearSourceChange()
        autoplayEpisode = automatic
        showConnecting = automatic
        continuingEpisode = false
        streamSelection = selection
        selectedEpisode = selection == nil ? episode : selection?.episode
        showStreams = true
    }
    private func playerDismissed() {
        showConnecting = false
        if let extra = pendingExtra {
            let owner = pendingEpisodeOwner
            pendingExtra = nil; pendingEpisodeOwner = nil
            guard showStreams, owner == app.library.owner else { return }
            openExtra(extra, automatic: true); return
        }
        guard let episode = pendingEpisode else { return }
        let owner = pendingEpisodeOwner
        pendingEpisode = nil; pendingEpisodeOwner = nil
        guard showStreams, owner == app.library.owner, episode.available else { return }
        selectionRevision &+= 1
        // Present the next session only after the old full-screen player has
        // dismissed and released its native surface.
        autoplayEpisode = true
        showConnecting = true
        continuingEpisode = true
        selectedEpisode = episode
        if let selection = streamSelection { streamSelection = MediaPlaybackSelection(media: selection.media, episode: episode) }
    }
    private func playTitle() {
        if model.isAnimeOneOff { openStreams(AnimeOneOffPresentation.playbackEpisode(model.media), automatic: StreamPreferences.shared.automatic); return }
        if !model.media.episodic { openStreams(automatic: StreamPreferences.shared.automatic); return }
        if let pool = model.episodePool, let projection = model.episodeOrderProjection,
           let episode = pool.startingEpisode(in: app.library, presentation: projection) {
            openStreams(episode, automatic: StreamPreferences.shared.automatic); return
        }
        let record = app.library.items.first { $0.id == model.media.id }
        let watched = app.library.watchedEpisodes(model.media)
        if let episode = EpisodeSequence.startingEpisode(model.media.videos ?? [], record: record, watched: watched, presentation: model.episodeOrderProjection) {
            openStreams(episode, automatic: StreamPreferences.shared.automatic)
        }
    }
    private func download(_ offer: StreamOffer) async {
        guard !downloading else { return }
        downloading = true; downloadMessage = nil
        defer { downloading = false }
        let owner = app.personalOwner, scope = app.accountOperationScope, media = model.playbackContextMedia, episode = selectedEpisode
        do {
            let source = try await app.service.resolve(offer)
            guard owner == app.personalOwner, scope == app.accountOperationScope else { return }
            try DownloadManager.shared.start(source: source, media: media, episode: episode, owner: owner, cellular: cellularDownloads)
            if media.identity == model.playbackContextMedia.identity { downloadMessage = DesktopInterfaceText.value("Download started") }
        } catch { if owner == app.personalOwner, scope == app.accountOperationScope, media.identity == model.playbackContextMedia.identity { downloadMessage = safeMessage(error) } }
    }
}
