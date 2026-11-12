import SwiftUI
import UniformTypeIdentifiers

struct LiveTVView: View {
    let app: AppModel
    @State private var preferences: LiveTVPreferences
    @State private var channels: [LiveChannel] = []
    @State private var query: String
    @State private var source = "all"
    @State private var category = "all"
    @State private var favorites = false
    @State private var providers = false
    @State private var configuring = false
    @State private var loading = false
    @State private var visibleCount = 100
    @State private var error: String?
    @State private var generation = UUID()
    @State private var playback: PlaybackSession?
    @State private var playbackRequest = UUID()
    @State private var managingCategories = false
    @State private var guidePrograms: [String: [LiveProgram]] = [:]
    @MainActor init(app: AppModel, initialQuery: String = "") {
        self.app = app; _preferences = State(initialValue: LiveTVPreferences(owner: app.settingsOwner)); _query = State(initialValue: initialQuery)
    }
    private var selectedChannels: [LiveChannel] { channels.filter { source == "all" || $0.source == source } }
    private var groups: [String] { LiveTVCatalogOrder.groups(LiveTVGroupOrder.sortedGroups(Array(Set(selectedChannels.compactMap(\.group))), region: MetadataPreferences.shared.region, preferredLanguages: StreamSourceSettings.names(StreamPreferences.shared.streamLanguages)), prefs: groupPrefs) }
    /// Desktop's category pins and hidden categories belong to one playlist, so they apply only when a single list is selected.
    private var groupPrefs: LiveGroupPrefs { source == "all" ? LiveGroupPrefs() : preferences.groupPrefs(for: source) }
    private var sourceGroups: [String] { LiveTVGroupOrder.sortedGroups(Array(Set(channels.filter { $0.source == source }.compactMap(\.group))), region: MetadataPreferences.shared.region, preferredLanguages: StreamSourceSettings.names(StreamPreferences.shared.streamLanguages)) }
    private var catalog: [LiveChannel] { LiveTVCatalogOrder.catalog(selectedChannels, region: MetadataPreferences.shared.region, preferredLanguages: StreamSourceSettings.names(StreamPreferences.shared.streamLanguages), pinnedChannels: preferences.pinnedChannels, prefs: groupPrefs, plays: preferences.channelPlayCounts) }
    /// Channels per category in the selected list, for the category sheet's counts.
    private var sourceGroupCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for channel in channels where channel.source == source {
            if let group = channel.group { counts[group, default: 0] += 1 }
        }
        return counts
    }
    private var sourceNames: [String: String] { Dictionary(preferences.sources.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }) }
    /// Desktop's Favorites group ignores the list and category pickers and shows the saved favourites, loaded or not.
    private var filtered: [LiveChannel] {
        if favorites { return LiveTVCatalogOrder.favoriteChannels(preferences.favoriteItems, sourceNames: sourceNames).filter { LiveTVSearch.channelMatches($0, query: query) } }
        return catalog.filter { (category == "all" || $0.group == category) && LiveTVSearch.channelMatches($0, query: query) }
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("Contenido", selection: $providers) { Text("Mis canales").tag(false); Text("Addons").tag(true) }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 10)
            if providers { ContentPageView(app: app, kind: "tv", title: "Live TV") }
            else { channelList }
        }.background(HarborTheme.background).navigationTitle("Live TV").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Canales y categorías")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { configuring = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Listas de Live TV") } }
            .sheet(isPresented: $configuring) { LiveSourcesView(preferences: preferences) }
            .sheet(isPresented: $managingCategories) { LiveCategoryManageView(preferences: preferences, sourceID: source, groups: sourceGroups, counts: sourceGroupCounts) }
            .task(id: preferences.sources) { await load(refresh: false) }
            .onChange(of: query) { _, _ in visibleCount = 100 }
            .onChange(of: category) { _, _ in visibleCount = 100 }
            .onChange(of: favorites) { _, _ in visibleCount = 100 }
            .onChange(of: source) { _, _ in category = "all"; visibleCount = 100 }
            .onChange(of: preferences.sources.count) { previous, next in if next > previous { providers = false } }
            .fullScreenCover(item: $playback) { session in
                PlayerView(session: session, resume: app.resume, title: session.media?.name ?? "Live TV", media: session.media)
            }
    }
    private var channelList: some View {
        let rows = filtered
        return List {
            Section {
                Picker("Lista", selection: $source) { Text("Todas las listas").tag("all"); ForEach(preferences.sources) { Text($0.name).tag($0.id) } }
                Picker("Categoría", selection: $category) { Text("Todas las categorías").tag("all"); ForEach(groups, id: \.self) { Text($0).tag($0) } }
                Toggle("Sólo favoritos", isOn: $favorites)
                if source != "all" {
                    Button { managingCategories = true } label: { HStack { Text(DesktopInterfaceText.value("Channel categories")); Spacer(); Text(DesktopInterfaceText.value("Manage")).foregroundStyle(.secondary) } }
                }
            }
            LiveTVTopNetworksRow(region: MetadataPreferences.shared.region, channels: selectedChannels, active: category == "all" && query.isEmpty, onPlay: { channel in Task { await play(channel) } })
            if loading { ProgressView("Cargando canales…") }
            if let error = error ?? preferences.error { Text(error).font(.caption).foregroundStyle(.orange) }
            ForEach(Array(rows.prefix(visibleCount))) { channel in
                Button { Task { await play(channel) } } label: {
                    HStack(spacing: 14) {
                        if let logo = channel.logo { Artwork(url: logo, fit: .fit, maxPixels: 180).frame(width: 48, height: 44) }
                        else { Image("nav-livetv").resizable().scaledToFit().frame(width: 32, height: 32).frame(width: 48, height: 44).foregroundStyle(.secondary) }
                        VStack(alignment: .leading, spacing: 5) { Text(channel.name).font(.subheadline.weight(.medium)).lineLimit(2); if let group = channel.group { Text(group).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; LiveTVNowNextLine(programs: guidePrograms[channel.id] ?? []) }
                        Spacer(); if preferences.favorites.contains(channel.id) { Image(systemName: "star.fill").font(.caption).foregroundStyle(HarborTheme.accent) }
                    }.foregroundStyle(HarborTheme.ink).padding(.vertical, 4)
                }.buttonStyle(.plain).contextMenu {
                    Button(preferences.favorites.contains(channel.id) ? "Quitar de favoritos" : "Añadir a favoritos") { do { try preferences.toggle(channel) } catch { self.error = safeMessage(error) } }
                    Button(DesktopInterfaceText.value(preferences.pinnedChannels.contains(channel.id) ? "Unpin channel" : "Pin to top")) { do { try preferences.togglePinned(channel) } catch { self.error = safeMessage(error) } }
                    if let list = preferences.sources.first(where: { $0.id == channel.source }), list.xtream != nil || !(guidePrograms[channel.id]?.isEmpty ?? true) {
                        NavigationLink("Programación") {
                            LiveProgramView(channel: channel, source: list, owner: preferences.owner, guideChannels: channels, initialPrograms: guidePrograms[channel.id] ?? []) { program in
                                Task { await play(channel, program: program, sourceSnapshot: list) }
                            }
                        }.accessibilityIdentifier("live-tv-program-guide-\(channel.id)")
                    }
                }
            }
            if rows.count > visibleCount { Button("Mostrar más canales") { visibleCount += 100 }.frame(maxWidth: .infinity) }
            if rows.isEmpty && !loading {
                ContentUnavailableView("Sin canales", image: "nav-livetv", description: Text(preferences.sources.isEmpty ? "Añade una lista M3U desde una URL o un archivo. Los canales de tus addons están en la otra pestaña." : "No hay canales que coincidan con estos filtros."))
            }
        }.scrollContentBackground(.hidden).refreshable { await load(refresh: true) }
    }
    private func load(refresh: Bool) async {
        guard preferences.ready else { return }
        let token = UUID(); generation = token; loading = true; error = nil
        defer { if generation == token { loading = false } }
        let sources = preferences.sources, owner = preferences.owner
        let result = await withTaskGroup(of: ([LiveChannel], Bool).self, returning: [([LiveChannel], Bool)].self) { group in
            var iterator = sources.makeIterator(), output: [([LiveChannel], Bool)] = []
            func submit(_ source: LivePlaylistSource) { group.addTask { do { let entries = try await LivePlaylistService.shared.load(source, owner: owner, refresh: refresh); return (entries.filter { VODTitles.kind($0) == "live" }, false) } catch { return ([], true) } } }
            for _ in 0..<2 { if let item = iterator.next() { submit(item) } }
            for await value in group { output.append(value); if !Task.isCancelled, let item = iterator.next() { submit(item) } }
            return output
        }
        guard generation == token, app.settingsOwner == owner, preferences.sources == sources, !Task.isCancelled else { return }
        let bySource = Dictionary(grouping: result.flatMap { $0.0 }, by: \.source)
        channels = sources.flatMap { bySource[$0.id] ?? [] }
        // The guide loads after the channel list is on screen: it can take a long download or many Xtream requests.
        let guideChannels = channels
        Task {
            let programs = await LiveTVGuideBuilder.programsByChannel(channels: guideChannels, sources: sources, owner: owner, refresh: refresh)
            guard generation == token, app.settingsOwner == owner, preferences.sources == sources, !Task.isCancelled else { return }
            guidePrograms = programs
        }
        preferences.rememberFavorites(channels)
        if result.contains(where: { $0.1 }) { error = "No se pudieron cargar algunas listas. Los canales disponibles siguen accesibles." }
        if sources.isEmpty { providers = true }
    }
    private func play(_ channel: LiveChannel, program: LiveProgram? = nil, sourceSnapshot expectedSource: LivePlaylistSource? = nil) async {
        guard let sourceSnapshot = expectedSource ?? preferences.sources.first(where: { $0.id == channel.source }) else { return }
        guard app.settingsOwner == preferences.owner,
              sourceSnapshot.id == channel.source,
              preferences.sources.contains(sourceSnapshot) else { return }
        let owner = app.accountOperationScope
        let request = UUID()
        playbackRequest = request
        do {
            guard !channel.drm else { throw HarborError(code: "iptv-drm") }
            let streamURL: String
            if let program {
                guard program.start.timeIntervalSince1970.isFinite,
                      program.end.timeIntervalSince1970.isFinite,
                      program.end > program.start,
                      program.end <= Date(),
                      let catchup = LiveTVCatchup.url(for: channel, start: program.start, end: program.end) else { return }
                streamURL = catchup
            } else {
                streamURL = channel.url
            }
            let headers = JSONValue.object(channel.headers.mapValues(JSONValue.string))
            let stream: JSONValue = .object(["addonId": .string("iptv:" + sourceSnapshot.id), "addonName": .string("Live TV"), "url": .string(streamURL), "behaviorHints": .object(["proxyHeaders": .object(["request": headers])])])
            let resolved = try await app.service.resolve(StreamOffer(id: 0, raw: stream))
            guard playbackRequest == request, owner == app.accountOperationScope,
                  app.settingsOwner == preferences.owner, preferences.sources.contains(sourceSnapshot) else { return }
            var sessionMedia = channel.media
            if let program {
                sessionMedia.name = program.title
                sessionMedia.description = channel.name + " · catch up"
            }
            playback = PlaybackSession(source: resolved, target: ResumeTarget(id: "iptv:" + channel.id), startMs: 0, storageWarning: nil, progressEnabled: false, owner: owner, media: sessionMedia)
            // Desktop counts live starts only (`recordChannelPlay`); a catch-up replay is not counted.
            if program == nil { try? preferences.recordPlay(channel) }
        } catch {
            guard playbackRequest == request, owner == app.accountOperationScope,
                  app.settingsOwner == preferences.owner, preferences.sources.contains(sourceSnapshot) else { return }
            self.error = safeMessage(error)
        }
    }
}

struct LiveSourcesView: View {
    let preferences: LiveTVPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var importing = false
    @State private var saving = false
    @State private var error: String?
    @State private var kind = "m3u"
    @State private var username = ""
    @State private var password = ""
    @State private var container = "ts"
    @State private var guideURL = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Tus listas") {
                    ForEach(preferences.sources) { source in
                        HStack { VStack(alignment: .leading, spacing: 4) { Text(source.name); Text(source.xtream != nil ? "Servidor Xtream" : source.url == nil ? "Archivo M3U" : "Lista remota").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(role: .destructive) { remove(source) } label: { Image(systemName: "trash") }.accessibilityLabel("Eliminar \(source.name)") }
                    }
                }
                Section("Añadir fuente") {
                    Picker("Tipo", selection: $kind) { Text("Lista M3U").tag("m3u"); Text("Servidor Xtream").tag("xtream") }.pickerStyle(.segmented)
                    TextField("Nombre de la lista", text: $name)
                    TextField(kind == "xtream" ? "Dirección del servidor" : "URL http o https", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Dirección de la guía (opcional)", text: $guideURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    if kind == "xtream" {
                        TextField("Usuario", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                        SecureField("Contraseña", text: $password).textContentType(.password)
                        Picker("Formato de canales", selection: $container) { Text("MPEG-TS").tag("ts"); Text("HLS").tag("m3u8") }
                    }
                    Button(kind == "xtream" ? "Conectar servidor" : "Añadir URL") { Task { if kind == "xtream" { await addServer() } else { await addURL() } } }.disabled(saving || !preferences.ready || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if kind == "m3u" { Button("Importar archivo M3U") { importing = true }.disabled(saving || !preferences.ready) }
                }
                if saving { ProgressView("Leyendo lista…") }
                if let error = error ?? preferences.error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.disabled(saving).navigationTitle("Listas y servidores").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() }.disabled(saving) } }
        }.interactiveDismissDisabled(saving)
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "m3u") ?? .plainText, UTType(filenameExtension: "m3u8") ?? .plainText, .plainText]) { result in
                switch result { case .success(let file): Task { await addFile(file) }; case .failure: error = "No se pudo abrir el archivo seleccionado." }
            }
    }
    private func newSource(remote: String?, fallback: String) -> LivePlaylistSource { LivePlaylistSource(id: UUID().uuidString.lowercased(), name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : String(name.prefix(120)), url: remote) }
    /// Desktop's `epgUrl` field: optional, but when typed it must be an http or https address.
    private func guideAddress() throws -> String? {
        let raw = guideURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }
        guard LivePlaylistService.validURL(raw) != nil else { throw HarborError(code: "iptv-url") }
        return raw
    }
    private func addURL() async {
        let raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LivePlaylistService.validURL(raw) != nil else { error = safeMessage(HarborError(code: "iptv-url")); return }
        var source = newSource(remote: raw, fallback: "Lista M3U")
        do { source.epgURL = try guideAddress() } catch { self.error = safeMessage(error); return }
        source.xtream = XtreamAccount.fromPlaylist(raw)
        if source.xtream != nil { source.url = nil; source.xtreamContainer = container }
        saving = true; error = nil; defer { saving = false }
        do { _ = try await LivePlaylistService.shared.load(source, owner: preferences.owner, refresh: true); try preferences.add(source); name = ""; url = ""; guideURL = "" }
        catch { try? await LivePlaylistService.shared.remove(source, owner: preferences.owner); self.error = safeMessage(error) }
    }
    private func addServer() async {
        saving = true; error = nil; defer { saving = false }
        var source = newSource(remote: nil, fallback: "Xtream")
        do {
            source.xtream = try XtreamAccount.make(server: url, username: username, password: password); source.xtreamContainer = container
            source.epgURL = try guideAddress()
            _ = try await XtreamClient(source: source, owner: preferences.owner).capabilities(refresh: true)
            try preferences.add(source); name = ""; url = ""; username = ""; password = ""; guideURL = ""
        } catch { try? await LivePlaylistService.shared.remove(source, owner: preferences.owner); self.error = safeMessage(error) }
    }
    private func addFile(_ file: URL) async {
        let access = file.startAccessingSecurityScopedResource(); defer { if access { file.stopAccessingSecurityScopedResource() } }
        var source = newSource(remote: nil, fallback: String(file.deletingPathExtension().lastPathComponent.prefix(120)))
        do { source.epgURL = try guideAddress() } catch { self.error = safeMessage(error); return }
        saving = true; error = nil; defer { saving = false }
        do { _ = try await LivePlaylistService.shared.importFile(file, source: source, owner: preferences.owner); try preferences.add(source); name = ""; guideURL = "" }
        catch { try? await LivePlaylistService.shared.remove(source, owner: preferences.owner); self.error = safeMessage(error) }
    }
    private func remove(_ source: LivePlaylistSource) {
        do { try preferences.remove(source); Task { try? await LiveTVGuideService.shared.remove(source, owner: preferences.owner) }; Task { do { try await LivePlaylistService.shared.remove(source, owner: preferences.owner) } catch { self.error = "La lista se ha quitado. No se pudo limpiar su copia local." } } }
        catch { self.error = safeMessage(error) }
    }
}

private struct LiveProgramView: View {
    let channel: LiveChannel
    let source: LivePlaylistSource
    let owner: String
    let guideChannels: [LiveChannel]
    let onPlayCatchup: (LiveProgram) -> Void
    @State private var programs: [LiveProgram] = []
    @State private var error: String?
    @State private var loading = false
    init(channel: LiveChannel, source: LivePlaylistSource, owner: String, guideChannels: [LiveChannel], initialPrograms: [LiveProgram], onPlayCatchup: @escaping (LiveProgram) -> Void) {
        self.channel = channel
        self.source = source
        self.owner = owner
        self.guideChannels = guideChannels
        self.onPlayCatchup = onPlayCatchup
        _programs = State(initialValue: initialPrograms)
    }
    var body: some View {
        List {
            if loading { ProgressView("Cargando programación…") }
            if let error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load() } } }
            ForEach(programs) { program in
                LiveProgramRow(channel: channel, program: program, onPlayCatchup: { onPlayCatchup(program) })
            }
            if programs.isEmpty && !loading && error == nil { Text("El proveedor no publica programación para este canal.").foregroundStyle(.secondary) }
        }.scrollContentBackground(.hidden).background(HarborTheme.background).navigationTitle(channel.name).navigationBarTitleDisplayMode(.inline).task { await load() }.refreshable { await load(refresh: true) }
    }
    private func load(refresh: Bool = false) async {
        guard refresh || programs.isEmpty else { return }
        guard !loading else { return }; loading = true; error = nil; defer { loading = false }
        if let guide = try? await LiveTVGuideService.shared.guide(source, owner: owner, refresh: refresh),
           !Task.isCancelled,
           let latest = LiveTVGuideLookup.programs(for: channel, guide: guide, tvgIDCounts: LiveTVGuideLookup.tvgIDCounts(guideChannels)),
           !latest.isEmpty {
            programs = latest
            return
        }
        guard source.xtream != nil, !Task.isCancelled else { return }
        do {
            let latest = try await XtreamClient(source: source, owner: owner).programs(channel)
            if programs.isEmpty { programs = LiveTVGuideLookup.sanitize(latest) }
        } catch is CancellationError {
            return
        } catch {
            if programs.isEmpty { self.error = safeMessage(error) }
        }
    }
}

private struct LiveProgramRow: View {
    let channel: LiveChannel
    let program: LiveProgram
    let onPlayCatchup: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let replayable = !channel.drm && program.start.timeIntervalSince1970.isFinite && program.end.timeIntervalSince1970.isFinite &&
                program.end <= context.date && program.end > program.start &&
                LiveTVCatchup.url(for: channel, start: program.start, end: program.end, now: context.date) != nil
            Group {
                if replayable {
                    Button(action: onPlayCatchup) { content(now: context.date, replayable: true) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(DesktopInterfaceText.value("Play") + " " + program.title)
                        .accessibilityIdentifier("live-tv-catchup-\(channel.id)-\(Int(program.start.timeIntervalSince1970))")
                } else {
                    content(now: context.date, replayable: false)
                }
            }
        }
    }

    private func content(now: Date, replayable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(program.start, format: .dateTime.hour().minute()); Text("–"); Text(program.end, format: .dateTime.hour().minute())
                Spacer()
                if program.start <= now && program.end > now { Text("Ahora").foregroundStyle(HarborTheme.accent) }
                if replayable { Label(DesktopInterfaceText.value("Play"), systemImage: "play.circle.fill").foregroundStyle(HarborTheme.accent) }
            }.font(.caption)
            Text(program.title).font(.headline)
            if let description = program.description, !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(.secondary) }
        }
        .foregroundStyle(HarborTheme.ink)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
