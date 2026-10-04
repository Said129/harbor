import SwiftUI

struct SearchView: View {
    let app: AppModel
    @State private var query = ""
    @State private var rows: [CatalogRow] = []
    @State private var error: String?
    @State private var loading = false
    @State private var completedQuery: String?
    var body: some View {
        ScrollView {
            if loading { ProgressView().padding() }
            if let error { Text(error).foregroundStyle(.secondary).padding() }
            if query.isEmpty { ContentUnavailableView("Busca en tus addons", systemImage: "magnifyingglass", description: Text("Películas, series y catálogos instalados.")) }
            else if rows.isEmpty && !loading { ContentUnavailableView.search(text: query) }
            if let completedQuery {
                Text("Resultados para «\(completedQuery)»").font(.headline).padding()
                    .accessibilityIdentifier("search-results-query")
            }
            CatalogRails(rows: rows)
        }
        .background(HarborTheme.background).navigationTitle("Buscar")
        .searchable(text: $query, prompt: "Título")
        .task(id: query) { await search() }
    }
    private func search() async {
        let requestedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        rows = []; error = nil; completedQuery = nil; loading = !requestedQuery.isEmpty
        guard !requestedQuery.isEmpty else { return }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let (result, warnings) = try await app.service.catalogs(app.addons, search: requestedQuery)
            try Task.checkCancellation()
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery else { return }
            rows = result
            completedQuery = requestedQuery
            error = warnings.isEmpty ? nil : "Algunos addons fallaron: \(warnings.joined(separator: ", "))"
            loading = false
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery else { return }
            self.error = safeMessage(error); loading = false
        }
    }
}
