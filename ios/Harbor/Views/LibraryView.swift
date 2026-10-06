import SwiftUI

struct LibraryView: View {
    let app: AppModel
    @State private var query = ""
    @State private var showHidden = false
    private var records: [LibraryRecord] { app.library.selectedItems(query: query) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filters
                LibraryPresentationFeedback(library: app.library)
                if app.library.loading { ProgressView().frame(maxWidth: .infinity) }
                if let error = app.library.error { VStack(alignment: .leading) { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await app.library.sync() } } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12, alignment: .top)], spacing: 22) {
                    ForEach(records) { record in
                        if let media = record.media {
                            NavigationLink(value: media) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Poster(media: media, width: nil)
                                    if app.library.presentation.display.filter == .continuing { LibraryProgress(record: record) }
                                }
                            }.buttonStyle(.plain).contextMenu { LibraryActions(app: app, record: record, media: media, owner: app.library.owner) }
                        }
                    }
                }
                if records.isEmpty && !app.library.loading { emptyState }
                else if !records.isEmpty { Text("\(records.count) títulos").font(.caption).foregroundStyle(.secondary) }
            }.padding()
        }.background(HarborTheme.background).navigationTitle("Mi biblioteca").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Buscar en tu biblioteca")
            .refreshable { await app.library.sync() }
            .onChange(of: app.library.owner) { _, _ in query = ""; showHidden = false }
            .sheet(isPresented: $showHidden) { HiddenContinuingView(app: app) }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Biblioteca", selection: Binding(get: { app.library.presentation.display.filter }, set: { value in app.library.changeDisplay { $0.filter = value } })) {
                ForEach(LibraryFilter.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("library-filter")
            HStack {
                Picker("Tipo", selection: Binding(get: { app.library.presentation.display.kind }, set: { value in app.library.changeDisplay { $0.kind = value } })) {
                    ForEach(LibraryKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("library-kind")
                Spacer()
                Picker("Orden", selection: Binding(get: { app.library.presentation.display.sort }, set: { value in app.library.changeDisplay { $0.sort = value } })) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("library-sort")
            }
            if !app.library.hiddenContinuing.isEmpty {
                Button("Títulos ocultos de Continuar viendo (\(app.library.hiddenContinuing.count))") { showHidden = true }.font(.caption)
            }
        }.disabled(!app.library.canChangePresentation)
    }
    private var emptyState: some View {
        let filtered = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || app.library.presentation.display.kind != .all
        return ContentUnavailableView(filtered ? "Sin coincidencias" : "Tu biblioteca", image: "nav-library", description: Text(filtered ? "Prueba con otro título o cambia el filtro de tipo." : app.user == nil ? "Puedes guardar títulos en este iPhone o iniciar sesión para recuperar tu biblioteca." : "Los títulos guardados y el progreso de tu cuenta aparecen aquí."))
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
                                NavigationLink(value: media) {
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
