import SwiftUI

struct SearchView: View {
    let app: AppModel
    @State private var query = ""
    @State private var rows: [CatalogRow] = []
    @State private var error: String?
    @State private var loading = false
    @State private var completedQuery: String?
    @State private var generation = UUID()
    @Bindable private var history = SearchHistory.shared
    init(app: AppModel, initialQuery: String = "") { self.app = app; _query = State(initialValue: initialQuery) }
    var body: some View {
        ScrollView {
            if loading { ProgressView().padding() }
            if let error {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.secondary)
                    Button("Reintentar") { Task { ArtworkRefresh.shared.retryFailedImages(); await search() } }
                }.padding()
            }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentSearches
                if history.items.isEmpty { ContentUnavailableView("Busca en tus addons", systemImage: "magnifyingglass", description: Text("Películas, series y catálogos instalados.")) }
            }
            else if rows.isEmpty && !loading { ContentUnavailableView.search(text: query) }
            if let completedQuery {
                Text("Resultados para «\(completedQuery)»").font(.headline).padding()
                    .accessibilityIdentifier("search-results-query")
            }
            CatalogRails(rows: SearchPresentation.rows(rows), app: app, titleOverrides: searchTitles, browseCatalogs: false, onSelect: { history.record(query) })
        }
        .background(HarborTheme.background).navigationTitle("Buscar")
        .searchable(text: $query, prompt: "Título")
        .onSubmit(of: .search) { history.record(query) }
        .onDisappear { if completedQuery != nil { history.record(query) } }
        .refreshable { ArtworkRefresh.shared.retryFailedImages(); await search() }
        .task(id: query + app.accountOperationScope + app.addons.filter(\.enabled).map(\.id).joined()) { await search() }
    }
    private var searchTitles: [String: String] {
        Dictionary(rows.map { ($0.id, $0.isAnimeCatalog ? "Anime" : ["movie": "Películas", "series": "Series", "tv": "TV", "channel": "TV"][$0.plan.kind] ?? "Resultados") }, uniquingKeysWith: { first, _ in first })
    }
    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !history.items.isEmpty {
                HStack {
                    Text("Búsquedas recientes").font(.headline)
                    Spacer()
                    Button("Borrar todo") { history.clear() }.font(.caption).frame(minHeight: 44)
                        .accessibilityIdentifier("search-history-clear")
                }
                ForEach(history.items, id: \.self) { recent in
                    HStack(spacing: 8) {
                        Button { query = recent; history.record(recent) } label: {
                            Label(recent, systemImage: "clock").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("search-recent-query")
                        Button { history.remove(recent) } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Quitar \(recent) del historial").accessibilityIdentifier("search-recent-remove")
                    }
                }
            }
        }.padding()
    }
    private func search() async {
        let request = UUID(); generation = request
        let requestedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = []; error = nil; completedQuery = nil; loading = !requestedQuery.isEmpty
        guard !requestedQuery.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let providers = try await app.service.catalogProviders(app.addons)
            let (result, warnings) = try await app.service.catalogs(providers, search: requestedQuery, onRow: { row in
                guard generation == request, query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery else { return }
                if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = row }
                else { rows.append(row) }
                completedQuery = requestedQuery
            })
            try Task.checkCancellation()
            guard generation == request, query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery else { return }
            rows = SearchPresentation.rows(result)
            completedQuery = requestedQuery
            error = warnings.isEmpty || result.contains(where: { !$0.metas.isEmpty }) ? nil : "No se pudo completar la búsqueda. Reintentar puede recuperar los resultados."
            loading = false
        } catch is CancellationError { return }
        catch {
            guard generation == request, !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery else { return }
            self.error = safeMessage(error); loading = false
        }
    }
}
