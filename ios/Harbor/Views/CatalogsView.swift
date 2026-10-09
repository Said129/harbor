import SwiftUI

struct CatalogsView: View {
    let app: AppModel
    @State private var kind = "all"
    @State private var query = ""
    @State private var addon = ""
    @State private var customization: PageCustomization
    @MainActor init(app: AppModel) {
        self.app = app
        _customization = State(initialValue: PageCustomization(owner: app.user?.id ?? "guest", page: "catalogs"))
    }
    private var rows: [CatalogRow] {
        app.rows.filter { row in
            (kind == "all" || row.plan.kind == kind) && (addon.isEmpty || row.plan.addon.id == addon) &&
                (query.isEmpty || (row.plan.title + " " + row.plan.addon.name).localizedCaseInsensitiveContains(query))
        }
    }
    private var providers: [Addon] {
        var seen = Set<String>()
        return app.rows.map { $0.plan.addon }.filter { seen.insert($0.id).inserted }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HarborPageHeading(title: "Catálogos", subtitle: "Todo lo que ofrecen tus complementos, mostrado como pósteres. Desplázate, busca o filtra hasta encontrar lo que quieras.").padding(.horizontal)
                HarborSearchField(prompt: "Buscar catálogos", text: $query).padding(.horizontal)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach([("Todos", "all"), ("Películas", "movie"), ("Series", "series"), ("Anime", "anime")], id: \.1) { title, value in
                            HarborPill(title: title, selected: kind == value) { kind = value }
                        }
                        NavigationLink { LibraryView(app: app) } label: { Text("Biblioteca").font(.caption.weight(.semibold)).padding(.horizontal, 14).frame(height: 38).background(HarborTheme.surface, in: .capsule) }.buttonStyle(.plain)
                        Menu {
                            Button("Todos los addons") { addon = "" }
                            ForEach(providers) { provider in Button(provider.name) { addon = provider.id } }
                        } label: { Label(providers.first { $0.id == addon }?.name ?? "Todos los addons", image: "nav-addons").font(.caption).padding(.horizontal, 14).frame(height: 38).background(HarborTheme.surface, in: .capsule) }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden)
                PageCustomizeButton(rails: app.rows.map(PageRail.catalog), customization: customization)
                ForEach(providers.filter { provider in rows.contains { $0.plan.addon.id == provider.id } }) { provider in
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 9) {
                            Artwork(url: provider.manifest["logo"].string, maxPixels: 96, failureIcon: "nav-addons").frame(width: 24, height: 24).clipShape(.rect(cornerRadius: 6))
                            Text(provider.name).font(.subheadline.weight(.semibold))
                            Text("\(rows.filter { $0.plan.addon.id == provider.id }.count)").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.horizontal)
                        CustomizedRails(rails: rows.filter { $0.plan.addon.id == provider.id }.map(PageRail.catalog), app: app, customization: customization)
                    }
                }
                if !app.loading && rows.isEmpty {
                    if app.rows.isEmpty { HarborCatalogEmptyView(app: app).padding(.horizontal) }
                    else { HarborNoMatchesView().padding(.horizontal) }
                }
            }.padding(.vertical, 20)
        }.background(HarborTheme.background).navigationTitle("").toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { PageEditingFooter(customization: customization) }
            .overlay { if app.loading && app.rows.isEmpty { ProgressView() } }
            .refreshable { await app.loadHome() }
    }
}

struct CatalogBrowserView: View {
    let app: AppModel
    let initial: CatalogRow
    @State private var genre = ""
    @State private var items: [Media] = []
    @State private var loading = false
    @State private var error: String?
    @State private var offset = 0
    @State private var reachedEnd = false
    @State private var generation = 0
    private let columns = [GridItem(.adaptive(minimum: 106), spacing: 12, alignment: .top)]
    private var genres: [String] { initial.plan.catalog?.extra.first { $0.name == "genre" }?.options ?? [] }
    private var supportsPaging: Bool { initial.plan.catalog?.extra.contains { $0.name == "skip" } ?? false }
    init(app: AppModel, initial: CatalogRow) {
        self.app = app; self.initial = initial
        _genre = State(initialValue: initial.selectedGenre ?? "")
        _items = State(initialValue: initial.metas)
        _offset = State(initialValue: initial.receivedCount ?? initial.metas.count)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !genres.isEmpty {
                    Picker("Género", selection: $genre) {
                        Text("Todos los géneros").tag("")
                        ForEach(genres, id: \.self) { Text($0).tag($0) }
                    }.padding(.horizontal).accessibilityIdentifier("catalog-genre")
                }
                if let error {
                    VStack(alignment: .leading) { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load(reset: items.isEmpty) } } }.padding(.horizontal)
                }
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(items, id: \.identity) { media in
                        NavigationLink { DetailView(media: media, app: app) } label: { Poster(media: media, width: nil) }.buttonStyle(.plain).accessibilityLabel(media.name).accessibilityIdentifier("catalog-browser-media")
                    }
                }.padding(.horizontal)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if supportsPaging && offset > 0 && !reachedEnd && !loading && error == nil {
                    ProgressView().frame(maxWidth: .infinity).padding().task { await load(reset: false) }
                }
                if !loading && items.isEmpty && error == nil { HarborNoMatchesView(text: "No titles match these filters.").padding(.horizontal) }
            }
        }.background(HarborTheme.background).navigationTitle(initial.plan.title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .task(id: genre) { if items.isEmpty || genre != (initial.selectedGenre ?? "") || generation > 0 { await load(reset: true) } }
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
            let count = result.receivedCount ?? result.metas.count
            offset += count
            reachedEnd = count == 0 || (!initial.plan.key.hasPrefix("native-kids-") && additions.isEmpty)
        } catch is CancellationError { return }
        catch { if requestGeneration == generation { self.error = safeMessage(error) } }
    }
}
