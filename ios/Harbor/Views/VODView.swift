import SwiftUI

struct VODView: View {
    let app: AppModel
    @State private var preferences: LiveTVPreferences
    @State private var library = VODLibrary()
    @State private var series = false
    @State private var source = "all"
    @State private var category = "all"
    @State private var query = ""
    @State private var visibleCount = 100
    @State private var configuring = false
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    @MainActor init(app: AppModel) { self.app = app; _preferences = State(initialValue: LiveTVPreferences(owner: app.user?.id ?? "guest")) }
    private var groups: [String] {
        let names: [String] = series ? library.series.compactMap(\.group) : library.movies.compactMap { $0.channel.group }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var movies: [VODMovie] {
        let needle = VODTitles.searchKey(query)
        return library.movies.filter { (category == "all" || $0.channel.group == category) && (needle.isEmpty || $0.searchKey.contains(needle)) }
    }
    private var shows: [VODSeries] {
        let needle = VODTitles.searchKey(query)
        return library.series.filter { (category == "all" || $0.group == category) && (needle.isEmpty || $0.searchKey.contains(needle)) }
    }
    private var signature: String { [source, String(series), preferences.sources.map(\.id).joined(separator: "|")].joined(separator: "|") }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Picker("Contenido", selection: $series) { Text("Películas").tag(false); Text("Series").tag(true) }.pickerStyle(.segmented)
                HStack {
                    Picker("Fuente", selection: $source) { Text("Todas las fuentes").tag("all"); ForEach(preferences.sources) { Text($0.name).tag($0.id) } }
                    Spacer()
                    Picker("Categoría", selection: $category) { Text("Todas las categorías").tag("all"); ForEach(groups, id: \.self) { Text($0).tag($0) } }
                }.font(.subheadline)
                if loading { ProgressView("Cargando VOD…").frame(maxWidth: .infinity) }
                if let error = error ?? preferences.error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load(refresh: true) } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], alignment: .leading, spacing: 22) {
                    if series {
                        ForEach(Array(shows.prefix(visibleCount))) { show in NavigationLink { VODDetailView(movie: nil, series: show, source: preferences.sources.first { $0.id == show.source }, app: app) } label: { VODPoster(media: show.media, owner: preferences.owner) }.buttonStyle(.plain) }
                    } else {
                        ForEach(Array(movies.prefix(visibleCount))) { movie in NavigationLink { VODDetailView(movie: movie, series: nil, source: preferences.sources.first { $0.id == movie.channel.source }, app: app) } label: { VODPoster(media: movie.media, owner: preferences.owner) }.buttonStyle(.plain) }
                    }
                }
                if (series ? shows.count : movies.count) > visibleCount { Button("Mostrar más títulos") { visibleCount += 100 }.frame(maxWidth: .infinity) }
                if !loading && (series ? shows.isEmpty : movies.isEmpty) {
                    ContentUnavailableView("Sin \(series ? "series" : "películas")", image: "nav-playlist", description: Text(preferences.sources.isEmpty ? "Añade una lista M3U o tu servidor Xtream para cargar su catálogo." : "No hay títulos de este tipo que coincidan con la categoría y la búsqueda."))
                }
            }.padding(16)
        }.background(HarborTheme.background).navigationTitle("VOD").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Películas y series de tus fuentes")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { configuring = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Fuentes de VOD") } }
            .sheet(isPresented: $configuring) { LiveSourcesView(preferences: preferences) }
            .task(id: signature) { await load(refresh: false) }
            .onChange(of: source) { _, _ in category = "all"; visibleCount = 100 }
            .onChange(of: series) { _, _ in category = "all"; visibleCount = 100 }
            .onChange(of: category) { _, _ in visibleCount = 100 }
            .onChange(of: query) { _, _ in visibleCount = 100 }
            .refreshable { await load(refresh: true) }
    }
    private func load(refresh: Bool) async {
        guard preferences.ready else { return }
        let token = UUID(); generation = token; loading = true; error = nil
        defer { if generation == token { loading = false } }
        let sources = preferences.sources.filter { source == "all" || $0.id == source }, owner = preferences.owner, isSeries = series
        let result = await withTaskGroup(of: (String, VODLibrary?).self, returning: ([String: VODLibrary], Bool, Bool).self) { group in
            var iterator = sources.makeIterator(), output: [String: VODLibrary] = [:], failed = false, limited = false
            func submit(_ item: LivePlaylistSource) {
                group.addTask {
                    do {
                        let channels: [LiveChannel]
                        if item.xtream != nil { channels = try await XtreamClient(source: item, owner: owner).vod(series: isSeries, refresh: refresh) }
                        else { channels = try await LivePlaylistService.shared.load(item, owner: owner, refresh: refresh) }
                        return (item.id, try VODLibrary.build(channels))
                    } catch { return (item.id, nil) }
                }
            }
            for _ in 0..<2 { if let item = iterator.next() { submit(item) } }
            for await (id, value) in group {
                if let value {
                    output[id] = VODLibrary(movies: isSeries ? [] : value.movies, series: isSeries ? value.series : [])
                    var remaining = 100_000
                    for item in sources {
                        guard var current = output[item.id] else { continue }
                        let count = current.movies.count + current.series.count
                        if count > remaining {
                            current.movies = Array(current.movies.prefix(remaining))
                            current.series = Array(current.series.prefix(max(0, remaining - current.movies.count)))
                            output[item.id] = current; limited = true
                        }
                        remaining = max(0, remaining - count)
                    }
                } else { failed = true }
                if !Task.isCancelled, let item = iterator.next() { submit(item) }
            }
            return (output, failed, limited)
        }
        guard !Task.isCancelled, generation == token else { return }
        var next = VODLibrary()
        for source in sources {
            guard let value = result.0[source.id] else { continue }
            next.movies.append(contentsOf: value.movies); next.series.append(contentsOf: value.series)
        }
        library = next
        if result.1 { error = "No se pudieron cargar algunas fuentes. Los catálogos disponibles siguen accesibles." }
        if result.2 { error = "Hay más de 100.000 títulos entre tus fuentes. Selecciona una fuente para ver su catálogo completo." }
    }
}

private struct VODPoster: View {
    let media: Media
    let owner: String
    @State private var enriched: Media?
    private var signature: String { vodMetadataSignature(media, owner: owner) }
    var body: some View {
        Poster(media: enriched ?? media, width: nil, artworkFallbacks: [media.poster, media.background].compactMap { $0 }).task(id: signature) {
            enriched = nil
            let result = try? await VODMetadataService.shared.enrich(media, configuration: MetadataPreferences.shared.configuration(), owner: owner)
            guard !Task.isCancelled else { return }
            enriched = result
        }
    }
}

@MainActor private func vodMetadataSignature(_ media: Media, owner: String) -> String {
    let configuration = MetadataPreferences.shared.configuration()
    let parts = [owner, media.id, configuration.tmdbKey, configuration.region, configuration.language, String(configuration.translateTitles)]
    return EBookShelf.hash(parts.joined(separator: "|"))
}

private struct VODDetailView: View {
    let movie: VODMovie?
    let series: VODSeries?
    let source: LivePlaylistSource?
    let app: AppModel
    @State private var episodes: [VODEpisode] = []
    @State private var season = 1
    @State private var loading = false
    @State private var resolving = false
    @State private var downloading = false
    @State private var playback: PlaybackSession?
    @State private var currentEpisode: VODEpisode?
    @State private var error: String?
    @State private var downloadMessage: String?
    @State private var enriched: Media?
    @State private var progressRevision = UUID()
    @AppStorage("downloadsCellular") private var cellularDownloads = false
    private var original: Media { movie?.media ?? series?.media ?? Media(id: "vod", type: "movie", name: "VOD") }
    private var media: Media { enriched ?? original }
    private var owner: String { app.user?.id ?? "guest" }
    private var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
    private var metadataSignature: String { vodMetadataSignature(original, owner: owner) }
    private var cover: some View {
        HStack(alignment: .top, spacing: 20) {
            Artwork(url: media.poster, fallbacks: [original.poster, media.background].compactMap { $0 }, maxPixels: 600).frame(width: 116, height: 174).clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 14) {
                Text(media.name).font(.title2.bold())
                if let year = media.releaseInfo { Text(year).foregroundStyle(.secondary) }
                if let group = original.description { Text(group).font(.subheadline).foregroundStyle(.secondary) }
                if let source { Text(source.name).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var seriesContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Picker("Temporada", selection: $season) { ForEach(seasons, id: \.self) { Text("Temporada \($0)").tag($0) } }
            LazyVStack(spacing: 14) { ForEach(episodes.filter { $0.season == season }) { episode in episodeRow(episode) } }
            if !loading && episodes.isEmpty { Text("Esta serie no tiene episodios disponibles.").foregroundStyle(.secondary) }
            Button("Actualizar episodios") { Task { await load(refresh: true) } }.disabled(loading)
        }
    }
    private func episodeRow(_ episode: VODEpisode) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { Task { await play(episode.channel, episode: episode) } } label: {
                VODEpisodeRow(episode: episode, media: media, resume: app.resume, revision: progressRevision)
            }.buttonStyle(.plain).disabled(resolving)
            Button { Task { await download(episode.channel, episode: episode) } } label: {
                Image("nav-download").resizable().scaledToFit().frame(width: 20, height: 20).frame(width: 32, height: 44)
            }.disabled(downloading).accessibilityLabel("Descargar episodio \(episode.episode)")
        }.padding(12).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                cover
                if let overview = enriched?.description, overview != original.description { Text(overview).font(.subheadline).foregroundStyle(.secondary) }
                if let movie {
                    Button { Task { await play(movie.channel) } } label: { Label("Reproducir", image: "ui-play-filled").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent).disabled(resolving)
                    Button { Task { await download(movie.channel) } } label: { Label("Descargar", image: "nav-download") }.disabled(downloading)
                }
                if loading || resolving { ProgressView() }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                if let downloadMessage { Text(downloadMessage).font(.caption).foregroundStyle(.secondary) }
                if series != nil { seriesContent }
            }.padding(16)
        }.background(HarborTheme.background).navigationTitle("VOD").navigationBarTitleDisplayMode(.inline).task { await load(refresh: false) }
            .task(id: metadataSignature) {
                enriched = nil
                let selectedOwner = owner
                let result = try? await VODMetadataService.shared.enrich(original, configuration: MetadataPreferences.shared.configuration(), owner: selectedOwner)
                guard !Task.isCancelled, selectedOwner == owner else { return }
                enriched = result
            }
            .fullScreenCover(item: $playback, onDismiss: { progressRevision = UUID() }) { session in PlayerView(session: session, resume: session.resumeStore ?? app.resume, title: currentEpisode.map { media.name + " · " + $0.title } ?? media.name, media: media) }
            .onChange(of: owner) { _, _ in playback = nil; currentEpisode = nil }
    }
    private func load(refresh: Bool) async {
        guard let series, !loading else { return }; loading = true; error = nil; defer { loading = false }
        let owner = app.user?.id ?? "guest"
        do {
            let next: [VODEpisode]
            if series.xtreamID != nil, let source { next = try await XtreamClient(source: source, owner: owner).episodes(series, refresh: refresh) }
            else { next = series.episodes }
            try Task.checkCancellation(); guard owner == (app.user?.id ?? "guest") else { return }
            episodes = next; if !seasons.contains(season) { season = seasons.first ?? 1 }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
    private func resolve(_ channel: LiveChannel) async throws -> PlaybackSource {
        guard !channel.drm else { throw HarborError(code: "iptv-drm") }
        let value: JSONValue = .object(["addonId": .string("vod:" + channel.source), "addonName": .string("VOD"), "url": .string(channel.url), "behaviorHints": .object(["proxyHeaders": .object(["request": .object(channel.headers.mapValues(JSONValue.string))])])])
        return try await app.service.resolve(StreamOffer(id: 0, raw: value))
    }
    private func play(_ channel: LiveChannel, episode: VODEpisode? = nil) async {
        guard !resolving else { return }; resolving = true; error = nil; defer { resolving = false }
        let owner = app.user?.id ?? "guest", resume = app.resume
        do {
            let resolved = try await resolve(channel)
            let target = vodResumeTarget(media.id, episode: episode)
            var start = ResumeStart(ms: 0, prompt: false), warning: String?
            do { start = try await resume.position(target, durationMs: channel.duration.flatMap { $0.isFinite ? $0 * 1_000 : nil } ?? 0, playback: UserDefaults.standard.object(forKey: "resumePlayback") as? Bool ?? true, prompt: UserDefaults.standard.object(forKey: "resumePrompt") as? Bool ?? false) }
            catch { warning = safeMessage(error) }
            try Task.checkCancellation(); guard owner == (app.user?.id ?? "guest") else { return }
            currentEpisode = episode
            playback = PlaybackSession(source: resolved, target: target, startMs: start.ms, storageWarning: warning, progressEnabled: true, owner: owner, resumeStore: resume, promptForResume: start.prompt)
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
    private func download(_ channel: LiveChannel, episode: VODEpisode? = nil) async {
        guard !downloading else { return }; downloading = true; downloadMessage = nil; defer { downloading = false }
        let owner = app.user?.id ?? "guest"
        do {
            let resolved = try await resolve(channel); guard owner == (app.user?.id ?? "guest") else { return }
            let selected = episode.map { Episode(id: "vod-episode:" + EBookShelf.hash($0.id), season: $0.season, episode: $0.episode, title: $0.title, thumbnail: $0.channel.logo, overview: $0.plot) }
            try DownloadManager.shared.start(source: resolved, media: media, episode: selected, owner: owner, cellular: cellularDownloads)
            downloadMessage = "Descarga añadida. Puedes verla en Descargas."
        } catch { self.error = safeMessage(error) }
    }
}

private func vodResumeTarget(_ mediaID: String, episode: VODEpisode?) -> ResumeTarget {
    ResumeTarget(id: mediaID, season: episode?.season, episode: episode?.episode, videoId: episode.map { "vod-episode:" + EBookShelf.hash($0.id) })
}

private struct VODEpisodeRow: View {
    let episode: VODEpisode
    let media: Media
    let resume: ResumeStore
    let revision: UUID
    @State private var entry: ResumeEntry?
    private var signature: String { episode.id + "|" + revision.uuidString }
    private var progress: Double {
        guard let duration = episode.channel.duration, duration.isFinite, duration > 0, let entry else { return 0 }
        return min(1, max(0, entry.ms / (duration * 1_000)))
    }
    private var minutes: Int? {
        guard let duration = episode.channel.duration, duration.isFinite, duration > 0, duration < Double(Int.max / 1_000) else { return nil }
        return Int(max(0, duration - (entry?.ms ?? 0) / 1_000) / 60)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Artwork(url: episode.channel.logo, fallbacks: [media.background, media.poster].compactMap { $0 }, maxPixels: 360)
                .frame(width: 92, height: 58).clipShape(.rect(cornerRadius: 7))
                .overlay(alignment: .bottom) { if progress > 0 { GeometryReader { geometry in Rectangle().fill(HarborTheme.accent).frame(width: geometry.size.width * progress) }.frame(height: 3) } }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(episode.episode). \(episode.title)").font(.subheadline.weight(.medium))
                    if progress >= 0.9 { Image(systemName: "checkmark.circle.fill").foregroundStyle(HarborTheme.accent).accessibilityLabel("Visto") }
                }
                if let plot = episode.plot { Text(plot).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                if let minutes { Text(progress > 0 && progress < 0.9 ? "\(minutes) min restantes" : "\(Int((episode.channel.duration ?? 0) / 60)) min").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }.foregroundStyle(HarborTheme.ink).frame(maxWidth: .infinity, alignment: .leading)
            .task(id: signature) {
                entry = nil
                let saved = try? await resume.entry(vodResumeTarget(media.id, episode: episode))
                guard !Task.isCancelled else { return }
                entry = saved
            }
    }
}
