import SwiftUI

struct LibraryView: View {
    let app: AppModel
    @State private var query = ""
    @State private var showHidden = false
    private var records: [LibraryRecord] { app.library.selectedItems(query: query) }
    private var display: LibraryDisplay { app.library.presentation.display }
    private var groups: [LibraryListing.Group] { LibraryListing.groups(records, display: display) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HarborPageHeading(title: "Tu colección.", eyebrow: "Mi biblioteca")
                filters
                LibraryPresentationFeedback(library: app.library)
                if let error = app.library.favorites.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Button("Reintentar favoritos") { app.library.favorites.reload() }
                }
                if app.library.loading { ProgressView().frame(maxWidth: .infinity) }
                if let error = app.library.error { VStack(alignment: .leading) { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await app.library.sync() } } } }
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 14) {
                        if !group.title.isEmpty { Text("\(group.title.uppercased())  \(group.items.count)").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12, alignment: .top)], spacing: 22) {
                            ForEach(group.items) { record in
                                if let media = record.media {
                                    NavigationLink { DetailView(media: media, app: app) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Poster(media: media, width: nil).overlay(alignment: .topLeading) {
                                                if record.bookmarked { Image("desktop-bookmark-filled").resizable().scaledToFit().frame(width: 12, height: 12).foregroundStyle(.black).padding(6).background(.white.opacity(0.8), in: .circle).padding(8) }
                                            }
                                            if display.filter == .continuing { LibraryProgress(record: record) }
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityLabel(media.name).accessibilityIdentifier("library-media").contextMenu { LibraryActions(app: app, record: record, media: media, owner: app.library.owner) }
                                }
                            }
                        }
                    }
                }
                if records.isEmpty && !app.library.loading { emptyState }
                else if !records.isEmpty { Text(records.count == 1 ? "1 título" : "\(records.count) títulos").font(.caption).foregroundStyle(.secondary) }
            }.padding()
        }.background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .refreshable { await app.library.sync() }
            .onChange(of: app.library.owner) { _, _ in query = ""; showHidden = false }
            .sheet(isPresented: $showHidden) { HiddenContinuingView(app: app) }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 18) {
                    ForEach(LibraryFilter.allCases) { filter in
                        if filter == .favorites { localTab }
                        Button { app.library.changeDisplay { $0.filter = filter } } label: {
                            HStack(spacing: 7) {
                                Image(filter == .favorites ? "desktop-star" : filter == .watched ? "desktop-clock" : filter == .continuing ? "ui-play-filled" : filter == .all ? "desktop-library" : "desktop-bookmark").resizable().scaledToFit().frame(width: 16, height: 16)
                                Text(filter.title).font(HarborTheme.font(13, weight: .semibold))
                            }.frame(minHeight: 44).contentShape(Rectangle()).foregroundStyle(display.filter == filter ? HarborTheme.ink : HarborTheme.ink.opacity(0.5))
                                .overlay(alignment: .bottom) { if display.filter == filter { Rectangle().fill(HarborTheme.ink).frame(height: 2) } }
                        }.buttonStyle(.plain).accessibilityLabel(filter.title).accessibilityIdentifier("library-tab-\(filter.rawValue)").accessibilityAddTraits(display.filter == filter ? [.isSelected] : [])
                    }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("library-filter")
            Divider()
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(LibraryKind.allCases) { kind in
                        let count = app.library.filteredItems(for: display.filter).filter { kind == .all || $0.media?.type == kind.rawValue }.count
                        HarborPill(title: "\(kind.title)  \(count)", selected: display.kind == kind) { app.library.changeDisplay { $0.kind = kind } }
                    }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("library-kind")
            HarborSearchField(prompt: "Buscar título…", text: $query)
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(LibrarySort.allCases) { sort in HarborPill(title: sort.title, selected: display.sort == sort) { app.library.changeDisplay { $0.sort = sort } } }
                    Divider().frame(height: 24).padding(.horizontal, 5)
                    HarborPill(title: "Agrupada", selected: display.grouped) { app.library.changeDisplay { $0.grouped = true } }
                    HarborPill(title: "Una lista", selected: !display.grouped) { app.library.changeDisplay { $0.grouped = false } }
                }
            }.scrollIndicators(.hidden).accessibilityIdentifier("library-sort")
            if !app.library.hiddenContinuing.isEmpty {
                Button("Títulos ocultos de Continuar viendo (\(app.library.hiddenContinuing.count))") { showHidden = true }.font(.caption)
            }
        }.disabled(!app.library.canChangePresentation)
    }
    private var localTab: some View {
        NavigationLink { DownloadsView(app: app).toolbar(.visible, for: .navigationBar) } label: {
            HStack(spacing: 7) {
                Image("desktop-hard-drive").resizable().scaledToFit().frame(width: 16, height: 16)
                Text("Local").font(HarborTheme.font(13, weight: .semibold))
            }.foregroundStyle(HarborTheme.ink.opacity(0.5)).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Local").accessibilityIdentifier("library-tab-local")
    }
    private var emptyState: some View {
        let filtered = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.library.presentation.display.kind != .all
        let icon = filtered ? "nav-search" : display.filter == .favorites ? "desktop-star" : display.filter == .watched ? "desktop-clock" : display.filter == .continuing ? "ui-play-filled" : "desktop-bookmark"
        let title: String
        let message: String
        if filtered { title = "Sin coincidencias"; message = "No hay coincidencias con estos filtros." }
        else {
            switch display.filter {
            case .favorites: title = "Aún no hay favoritos"; message = "Agregar a favoritos"
            case .watched: title = "Aún no has visto nada"; message = "Reproduce algo. Aparecerá aquí cuando empieces a verlo."
            case .continuing: title = "Continuar viendo"; message = "Aún no hay nada en progreso. Presiona Reproducir en algún título."
            default: title = "Tu lista de seguimiento está vacía"; message = "Selecciona \"Agregar a la lista de seguimiento\" en su página de detalles para guardarlo aquí."
            }
        }
        return VStack(spacing: 12) {
            Image(icon).resizable().scaledToFit().frame(width: 28, height: 28).foregroundStyle(HarborTheme.ink.opacity(0.4)).accessibilityHidden(true)
            Text(title).font(HarborTheme.font(16, weight: .semibold)).foregroundStyle(HarborTheme.ink)
            if display.filter != .favorites || filtered { Text(message).font(HarborTheme.font(13)).lineSpacing(4).foregroundStyle(HarborTheme.ink.opacity(0.6)) }
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 56)
            .background(HarborTheme.background.opacity(0.3), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
            .accessibilityIdentifier("library-empty-state")
    }
}

struct ContinueWatching: View {
    let app: AppModel
    var kind: String? = nil
    var title = "Continuar viendo"
    var titleIsLiteral = false
    private var items: [LibraryRecord] {
        app.library.continuing.filter { ContinueWatchingSelection.includes($0, kind: kind, detectedAnime: app.animeDetection.identifiers) }
    }
    var body: some View {
        if !items.isEmpty || app.library.presentationError != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(titleIsLiteral ? title : DesktopInterfaceText.value(title)).font(HarborTheme.font(17, weight: .medium)).padding(.horizontal)
                LibraryPresentationFeedback(library: app.library).padding(.horizontal)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(items) { item in
                            if let media = item.media {
                                ContinueWatchingCard(app: app, record: item, media: media).id(app.library.owner + "|" + item.id)
                            }
                        }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden)
            }
        }
    }
}

private struct ContinueWatchingCard: View {
    let app: AppModel
    let record: LibraryRecord
    let media: Media
    @AppStorage(AnimeEpisodeGrouping.preferenceKey) private var episodeGrouping = AnimeEpisodeGrouping.seasons.rawValue
    @State private var hydrated: Media?
    @State private var cardPresentation: ContinueWatchingPresentation?
    private var detailed: Media { hydrated ?? media }
    private var presentation: ContinueWatchingPresentation {
        cardPresentation ?? ContinueWatchingPresentation(record: record, media: media, watched: [])
    }
    var body: some View {
        let presentation = self.presentation
        VStack(alignment: .leading, spacing: 2) {
            NavigationLink { DetailView(media: detailed, app: app, playImmediately: true, metadataLoaded: hydrated != nil) } label: {
                ContinueWatchingArtwork(record: record, media: detailed, presentation: presentation)
            }.accessibilityIdentifier("continue-watching-resume").accessibilityLabel("Continuar viendo \(detailed.name)")
                .accessibilityValue(presentation.upNext ? DesktopInterfaceText.value("Up Next") : "\(presentation.coordinates(record: record, media: detailed)?.caption ?? record.playbackCaption ?? "") · \(Int(presentation.progress * 100)) por ciento")
                .overlay(alignment: .topTrailing) {
                    Button { app.library.hideContinuing(record, owner: app.library.owner) } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white).frame(width: 28, height: 28)
                            .background(.black.opacity(0.75), in: .circle)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!app.library.canChangePresentation)
                        .accessibilityLabel(DesktopInterfaceText.value("Remove from continue watching") + ": " + detailed.name)
                        .accessibilityHint(DesktopInterfaceText.value("Your library and watch history are kept."))
                        .accessibilityIdentifier("continue-watching-remove")
                }
            NavigationLink { DetailView(media: detailed, app: app, metadataLoaded: hydrated != nil) } label: {
                Text(detailed.name).font(HarborTheme.font(13, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.accessibilityIdentifier("continue-watching-details").accessibilityLabel("Abrir ficha de \(detailed.name)")
        }.frame(width: 260, alignment: .leading).foregroundStyle(HarborTheme.ink).buttonStyle(.plain)
            .contextMenu { LibraryActions(app: app, record: record, media: detailed, owner: app.library.owner) }
            .onChange(of: record.raw, initial: true) { _, _ in updatePresentation() }
            .task(id: [record.raw, .string(episodeGrouping)]) {
                let owner = app.library.owner
                let grouping = AnimeEpisodeGrouping(rawValue: episodeGrouping) ?? .seasons
                guard var result = try? await app.continuationMetadata(media), !Task.isCancelled, owner == app.library.owner else { return }
                // Artwork and episodes can be enriched without changing the
                // cloud library identity used for resume and dismissal.
                result.id = media.id
                hydrated = result
                updatePresentation()
                let episodes = await AnimeEpisodeService.shared.episodes(for: result, grouping: grouping)
                guard !Task.isCancelled, owner == app.library.owner else { return }
                result.videos = episodes
                hydrated = result
                updatePresentation()
            }
    }
    private func updatePresentation() {
        let watched = (try? WatchedCodec.decode(record.raw["state"]["watched"].string, videos: detailed.videos ?? [])) ?? []
        cardPresentation = ContinueWatchingPresentation(record: record, media: detailed, watched: watched)
    }
}

private struct ContinueWatchingArtwork: View {
    let record: LibraryRecord
    let media: Media
    let presentation: ContinueWatchingPresentation
    private var episodeCaption: String? {
        guard media.episodic, let coordinates = presentation.coordinates(record: record, media: media) else { return nil }
        return AnimeService.isAnime(media.id) && coordinates.season == 1 ? "Ep \(coordinates.episode)" : coordinates.compactCaption
    }
    private var remainingCaption: String? {
        let duration = record.raw["state"]["duration"].numericValue ?? 0
        let offset = record.raw["state"]["timeOffset"].numericValue ?? 0
        guard duration.isFinite, duration > 0, offset.isFinite, offset >= 0 else { return nil }
        let remaining = max(0, ((duration - offset) / 60_000).rounded())
        guard remaining < Double(Int.max) else { return nil }
        let minutes = Int(remaining), hours = minutes / 60
        let original = minutes < 60 ? "{m}m left" : minutes % 60 == 0 ? "{h}h left" : "{h}h {m}m left"
        return DesktopInterfaceText.value(original).replacingOccurrences(of: "{h}", with: String(hours)).replacingOccurrences(of: "{m}", with: String(minutes < 60 ? minutes : minutes % 60))
    }
    var body: some View {
        ZStack {
            Color.clear
        Artwork(url: media.background, fallback: media.poster, fallbacks: [media.fallbackBackground, media.fallbackPoster].compactMap { $0 }, maxPixels: 650)
            .frame(width: 260, height: 260 * 9 / 16)
            .overlay {
                if let logo = media.logo {
                    Artwork(url: logo, fit: .fit, maxPixels: 500, showsPlaceholder: false)
                        .frame(width: 190, height: 72).opacity(0.8).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 52).allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    Image("ui-play-filled").resizable().scaledToFit().frame(width: 11, height: 11).accessibilityHidden(true)
                    if let episodeCaption { Text(episodeCaption).font(HarborTheme.font(11, weight: .medium)).fixedSize(horizontal: true, vertical: false) }
                    if presentation.upNext {
                        if episodeCaption != nil { Text("·").foregroundStyle(.white.opacity(0.5)) }
                        Text(DesktopInterfaceText.value("Up Next")).font(HarborTheme.font(11, weight: .medium)).foregroundStyle(HarborTheme.accent).lineLimit(1)
                    } else if let title = presentation.episode?.name ?? presentation.episode?.title, !title.isEmpty {
                        if episodeCaption != nil { Text("·").foregroundStyle(.white.opacity(0.5)) }
                        Text(title).font(HarborTheme.font(11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    } else if let caption = remainingCaption {
                        if episodeCaption != nil { Text("·").foregroundStyle(.white.opacity(0.5)) }
                        Text(caption).font(HarborTheme.font(11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                }.foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(HarborTheme.background.opacity(0.95), in: .rect(cornerRadius: 6))
                    .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .overlay(alignment: .bottom) {
                if presentation.progress > 0 {
                GeometryReader { bounds in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(HarborTheme.background.opacity(0.4))
                        Rectangle().fill(HarborTheme.accent).frame(width: bounds.size.width * CGFloat(presentation.progress))
                    }
                }.frame(height: 3).accessibilityLabel("Progreso").accessibilityValue("\(Int(presentation.progress * 100)) por ciento")
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1) }
            .allowsHitTesting(false)
        }.frame(width: 260, height: 260 * 9 / 16).contentShape(Rectangle())
    }
}

private struct LibraryProgress: View {
    let record: LibraryRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ProgressView(value: record.progress).tint(HarborTheme.accent).accessibilityLabel("Progreso").accessibilityValue("\(Int(record.progress * 100)) por ciento")
            if let caption = record.playbackCaption { Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
        }
    }
}
private struct LibraryActions: View {
    let app: AppModel
    let record: LibraryRecord
    let media: Media
    let owner: String
    var body: some View {
        Button(DesktopInterfaceText.value(app.library.favorites.contains(media) ? "Remove from favorites" : "Add to favorites")) {
            guard owner == app.library.owner else { return }
            app.library.favorites.toggle(media)
        }.disabled(!app.library.favorites.ready)
        Button(record.bookmarked ? "Quitar de mi lista" : "Añadir a mi lista") {
            Task { guard owner == app.library.owner else { return }; await app.library.toggleBookmark(media) }
        }.disabled(app.library.busy)
        Button(record.watched ? "Marcar como no visto" : "Marcar como visto") {
            Task {
                guard owner == app.library.owner else { return }
                let detailed = (try? await app.service.metadata(media, addons: app.addons)) ?? media
                guard owner == app.library.owner else { return }
                await app.library.toggleWatched(detailed)
            }
        }.disabled(app.library.busy)
        if record.continuing {
            Button(DesktopInterfaceText.value("Remove from Continue Watching")) { app.library.hideContinuing(record, owner: owner) }.disabled(!app.library.canChangePresentation)
        }
    }
}
private struct LibraryPresentationFeedback: View {
    let library: LibraryModel
    var body: some View {
        if let error = library.presentationError {
            VStack(alignment: .leading, spacing: 6) {
                Text(error).font(.caption).foregroundStyle(.orange)
                Button("Reintentar preferencias") { library.reloadPresentation() }.font(.caption)
            }
        }
    }
}
private struct HiddenContinuingView: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Estos títulos están ocultos sólo en este iPhone. Su progreso, favoritos y episodios vistos se conservan; vuelven a aparecer cuando hay nueva actividad del título.").font(.caption).foregroundStyle(.secondary) }
                LibraryPresentationFeedback(library: app.library)
                ForEach(app.library.hiddenContinuing) { record in
                    if let media = record.media {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) { Text(media.name); if let caption = record.playbackCaption { Text(caption).font(.caption).foregroundStyle(.secondary) } }
                            Spacer()
                            Button("Mostrar") { app.library.showContinuing(record) }.disabled(!app.library.canChangePresentation)
                        }
                    }
                }
            }.navigationTitle("Títulos ocultos").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } } }
        }.onChange(of: app.library.owner) { _, _ in dismiss() }
    }
}
