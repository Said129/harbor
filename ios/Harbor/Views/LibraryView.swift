import SwiftUI

struct LibraryView: View {
    let app: AppModel
    @State private var filter = "saved"
    @State private var kind = "all"
    private var records: [LibraryRecord] {
        app.library.items.filter { item in
            (filter == "saved" ? item.bookmarked : filter == "watched" ? item.watched : item.continuing) && (kind == "all" || item.media?.type == kind)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Biblioteca", selection: $filter) { Text("Mi lista").tag("saved"); Text("Vistos").tag("watched"); Text("Continuar").tag("continue") }.pickerStyle(.segmented)
                Picker("Tipo", selection: $kind) { Text("Todo").tag("all"); Text("Películas").tag("movie"); Text("Series").tag("series") }
                if app.library.loading { ProgressView().frame(maxWidth: .infinity) }
                if let error = app.library.error { VStack(alignment: .leading) { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await app.library.sync() } } } }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 22) {
                    ForEach(records) { record in
                        if let media = record.media {
                            NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain)
                                .contextMenu {
                                    Button(record.bookmarked ? "Quitar de mi lista" : "Añadir a mi lista") { Task { await app.library.toggleBookmark(media) } }
                                    Button(record.watched ? "Marcar como no visto" : "Marcar como visto") { Task {
                                        let detailed = (try? await app.service.metadata(media, addons: app.addons)) ?? media
                                        await app.library.toggleWatched(detailed)
                                    } }
                                }
                        }
                    }
                }
                if records.isEmpty && !app.library.loading { ContentUnavailableView("Tu biblioteca", image: "nav-library", description: Text(app.user == nil ? "Puedes guardar títulos en este iPhone o iniciar sesión para recuperar tu biblioteca." : "Los títulos guardados y el progreso de tu cuenta aparecen aquí.")) }
            }.padding()
        }.background(HarborTheme.background).navigationTitle("Mi biblioteca").navigationBarTitleDisplayMode(.inline).refreshable { await app.library.sync() }
    }
}

struct ContinueWatching: View {
    let app: AppModel
    var body: some View {
        if !app.library.continuing.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Continuar viendo").font(.headline).padding(.horizontal)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(app.library.continuing) { item in
                            if let media = item.media {
                                NavigationLink(value: media) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Artwork(url: media.background, fallback: media.poster, maxPixels: 650).frame(width: 230, height: 130).clipShape(.rect(cornerRadius: 10))
                                        ProgressView(value: item.progress).tint(HarborTheme.accent)
                                        Text(media.name).font(.caption).lineLimit(1)
                                    }.frame(width: 230)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden)
            }
        }
    }
}
