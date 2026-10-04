import SwiftUI

struct SearchView: View {
    let app: AppModel
    @State private var query = ""
    @State private var rows: [CatalogRow] = []
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        ScrollView {
            if loading { ProgressView().padding() }
            if let error { Text(error).foregroundStyle(.secondary).padding() }
            if query.isEmpty { ContentUnavailableView("Busca en tus addons", systemImage: "magnifyingglass", description: Text("Películas, series y catálogos instalados.")) }
            else if rows.isEmpty && !loading { ContentUnavailableView.search(text: query) }
            CatalogRails(rows: rows)
        }
        .background(HarborTheme.background).navigationTitle("Buscar")
        .searchable(text: $query, prompt: "Título")
        .task(id: query) { await search() }
    }
    private func search() async {
        rows = []; error = nil; loading = !query.isEmpty
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { loading = false; return }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let (result, warnings) = try await app.service.catalogs(app.addons, search: query)
            try Task.checkCancellation()
            rows = result
            error = warnings.isEmpty ? nil : "Algunos addons fallaron: \(warnings.joined(separator: ", "))"
            loading = false
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error); loading = false }
    }
}
