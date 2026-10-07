import SwiftUI

struct LibraryView: View {
    let app: AppModel
    @State private var query = ""
    @State private var showHidden = false
    private var records: [LibraryRecord] { app.library.selectedItems(query: query) }
    private var display: LibraryDisplay { app.library.presentation.display }
    private var groups: [(title: String, items: [LibraryRecord])] {
        guard display.grouped else { return [("", records)] }
        let calendar = Calendar.current, now = Date()
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let month = calendar.dateInterval(of: .month, for: now)
        var buckets = [[LibraryRecord](), [LibraryRecord](), [LibraryRecord](), [LibraryRecord]()]
        for record in records {
            let timestamp = display.filter == .watched || display.filter == .continuing ? record.activityTimestamp : LibraryRecord.timestamp(record.raw["_ctime"].string) ?? LibraryRecord.timestamp(record.modified) ?? 0
            let date = Date(timeIntervalSince1970: timestamp / 1_000)
            let index = timestamp == 0 ? 3 : week?.contains(date) == true ? 0 : month?.contains(date) == true ? 1 : 2
            buckets[index].append(record)
        }
        return zip(["Esta semana", "Este mes", "Anteriores", "Sin fecha"], buckets).filter { !$0.1.isEmpty }.map { (title: $0.0, items: $0.1) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HarborPageHeading(title: "Tu colección.", eyebrow: "Mi biblioteca", subtitle: "Tu biblioteca reúne los títulos guardados y el progreso de Stremio y de este iPhone. Mi lista muestra lo que aún no has visto; Historial, lo que has visto.")
                filters
                LibraryPresentationFeedback(library: app.library)
                if let error = app.library.favorites.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                    Button("Reintentar favoritos") { app.library.favorites.reload() }
                }
                if display.filter == .favorites { Text("Favoritos guardados en este iPhone para esta cuenta.").font(.caption).foregroundStyle(.secondary) }
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
        if filtered { title = "Sin coincidencias"; message = "Prueba con otro título o cambia el filtro de tipo." }
        else {
            switch display.filter {
            case .favorites: title = "Aún no hay favoritos"; message = "Toca el corazón en la ficha de una película o serie para guardarla aquí."
            case .watched: title = "Aún no has visto ningún título"; message = "Empieza a reproducir algo y aparecerá aquí."
            case .continuing: title = "Nada pendiente de continuar"; message = "Los títulos que empieces a ver aparecerán aquí con su progreso."
            case .watchlist: title = "Tu lista está vacía"; message = "Pulsa «Añadir a mi lista» en la ficha de un título para guardarlo aquí."
            default: title = "Tu biblioteca está vacía"; message = app.user == nil ? "Guarda títulos desde su ficha o inicia sesión para recuperar la biblioteca de tu cuenta." : "Los títulos guardados y el progreso de tu cuenta aparecen aquí."
            }
        }
        return VStack(spacing: 12) {
            Image(icon).resizable().scaledToFit().frame(width: 28, height: 28).foregroundStyle(HarborTheme.ink.opacity(0.4)).accessibilityHidden(true)
            Text(title).font(HarborTheme.font(16, weight: .semibold)).foregroundStyle(HarborTheme.ink)
            Text(message).font(HarborTheme.font(13)).lineSpacing(4).foregroundStyle(HarborTheme.ink.opacity(0.6))
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 56)
            .background(HarborTheme.background.opacity(0.3), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(HarborTheme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
            .accessibilityIdentifier("library-empty-state")
    }
}

struct ContinueWatching: View {
    let app: AppModel
    var body: some View {
        if !app.library.continuing.isEmpty || app.library.presentationError != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continuar viendo").font(.headline).padding(.horizontal)
                LibraryPresentationFeedback(library: app.library).padding(.horizontal)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(app.library.continuing) { item in
                            if let media = item.media {
                                NavigationLink { DetailView(media: media, app: app, playImmediately: true) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Artwork(url: media.background, fallback: media.poster, fallbacks: [media.fallbackBackground, media.fallbackPoster].compactMap { $0 }, maxPixels: 650).frame(width: 230, height: 130).clipShape(.rect(cornerRadius: 10))
                                        LibraryProgress(record: item)
                                        Text(media.name).font(.caption).lineLimit(1)
                                    }.frame(width: 230)
                                }.buttonStyle(.plain).contextMenu { LibraryActions(app: app, record: item, media: media, owner: app.library.owner) }
                            }
                        }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden)
            }
        }
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
        Button(app.library.favorites.contains(media) ? "Quitar de favoritos de este iPhone" : "Añadir a favoritos de este iPhone") {
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
            Button("Ocultar de Continuar viendo en este iPhone") { app.library.hideContinuing(record, owner: owner) }.disabled(!app.library.canChangePresentation)
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
