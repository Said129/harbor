import SwiftUI

struct SearchView: View {
    let app: AppModel
    @State private var query = ""
    @State private var rows: [CatalogRow] = []
    @State private var error: String?
    @State private var loading = false
    @State private var completedQuery: String?
    @State private var generation = UUID()
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
            if query.isEmpty { ContentUnavailableView("Busca en tus addons", systemImage: "magnifyingglass", description: Text("Películas, series y catálogos instalados.")) }
            else if rows.isEmpty && !loading { ContentUnavailableView.search(text: query) }
            if let completedQuery {
                Text("Resultados para «\(completedQuery)»").font(.headline).padding()
                    .accessibilityIdentifier("search-results-query")
            }
            CatalogRails(rows: rows, app: app)
        }
        .background(HarborTheme.background).navigationTitle("Buscar")
        .searchable(text: $query, prompt: "Título")
        .refreshable { ArtworkRefresh.shared.retryFailedImages(); await search() }
        .task(id: query + (app.user?.id ?? "guest") + app.addons.filter(\.enabled).map(\.id).joined()) { await search() }
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
            rows = result
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
