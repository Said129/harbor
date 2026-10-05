import SwiftUI

struct CatalogsView: View {
    let app: AppModel
    @State private var kind = "movie"
    var body: some View {
        List {
            Section {
                Picker("Tipo de contenido", selection: $kind) {
                    Label("Películas", image: "nav-movies").tag("movie")
                    Label("Series", image: "nav-shows").tag("series")
                }.pickerStyle(.segmented)
            }
            Section(kind == "movie" ? "Películas de tus addons" : "Series de tus addons") {
                ForEach(app.rows.filter { $0.plan.kind == kind }) { row in
                    NavigationLink { CatalogBrowserView(app: app, initial: row) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.plan.title)
                            Text(row.plan.addon.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("catalog-browser-link")
                }
                if !app.loading && app.rows.filter({ $0.plan.kind == kind }).isEmpty {
                    Text("Tus addons no tienen catálogos de este tipo.").foregroundStyle(.secondary)
                }
            }
        }.navigationTitle("Catálogos").overlay { if app.loading { ProgressView() } }
    }
}

private struct CatalogBrowserView: View {
    let app: AppModel
    let initial: CatalogRow
    @State private var genre = ""
    @State private var items: [Media] = []
    @State private var loading = false
    @State private var error: String?
    @State private var offset = 0
    @State private var reachedEnd = false
    @State private var generation = 0
    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 12)]
    private var genres: [String] { initial.plan.catalog?.extra.first { $0.name == "genre" }?.options ?? [] }
    private var supportsPaging: Bool { initial.plan.catalog?.extra.contains { $0.name == "skip" } ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !genres.isEmpty {
                    Picker("Género", selection: $genre) {
                        Text("Todos los géneros").tag("")
                        ForEach(genres, id: \.self) { Text($0).tag($0) }
                    }.padding(.horizontal).accessibilityIdentifier("catalog-genre")
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items, id: \.identity) { media in
                        NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain).accessibilityLabel(media.name).accessibilityIdentifier("catalog-browser-media")
                    }
                }.padding(.horizontal)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if supportsPaging && !reachedEnd && !loading {
                    Button("Cargar más") { Task { await load(reset: false) } }.frame(maxWidth: .infinity).padding()
                }
                if !loading && items.isEmpty && error == nil { ContentUnavailableView("Sin resultados", systemImage: "film") }
            }
        }.background(HarborTheme.background).navigationTitle(initial.plan.title).navigationBarTitleDisplayMode(.inline)
            .task(id: genre) { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        loading = true; error = nil
        generation += 1
        let requestGeneration = generation
        if reset { items = []; offset = 0; reachedEnd = false }
        let requestedGenre = genre
        defer { if requestGeneration == generation { loading = false } }
        do {
            // Request this catalog only: some addons expose dozens of catalogs.
            let result = try await app.service.catalog(initial.plan, genre: requestedGenre.isEmpty ? nil : requestedGenre, skip: reset ? 0 : offset)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            var known = Set(items.map(\.identity))
            let additions = result.metas.filter { known.insert($0.identity).inserted }
            items.append(contentsOf: additions)
            offset += result.metas.count
            reachedEnd = result.metas.isEmpty || additions.isEmpty
        } catch is CancellationError { return }
        catch { if requestGeneration == generation { self.error = safeMessage(error) } }
    }
}
