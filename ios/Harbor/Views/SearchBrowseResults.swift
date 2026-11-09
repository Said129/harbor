import SwiftUI

/// A title search that names a year or genre can open the original standard filter rails.
struct SearchBrowseResults: View {
    let intent: SearchQueryIntent
    let app: AppModel
    @State private var rows: [DiscoveryRail] = []
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()

    private var configuration: MetadataConfiguration { MetadataPreferences.shared.configuration() }
    private var signature: String {
        let configuration = configuration
        return [app.accountOperationScope, EBookShelf.hash(configuration.tmdbKey), configuration.language,
                configuration.region, String(configuration.translateTitles)].joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            if configuration.tmdbKey.isEmpty {
                ContentUnavailableView {
                    Label(intent.title, systemImage: intent.symbol)
                } description: {
                    EmptyView()
                } actions: {
                    NavigationLink(DesktopInterfaceText.value("Metadata providers")) {
                        MetadataSettingsView().toolbar(.visible, for: .navigationBar)
                    }
                }
            } else {
                if loading && rows.isEmpty { ProgressView().padding(28) }
                DiscoveryRails(rows: rows, app: app)
                if !loading && rows.isEmpty {
                    if let error {
                        VStack(spacing: 12) {
                            Text(error).foregroundStyle(.secondary)
                            Button(DesktopInterfaceText.value("Retry")) { Task { await load() } }
                        }.padding()
                    } else {
                        ContentUnavailableView.search(text: intent.title)
                    }
                }
            }
        }.background(HarborTheme.background)
            .navigationTitle(intent.title).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .accessibilityIdentifier("search-intent-results")
            .task(id: signature) { await load() }
            .refreshable { await load() }
    }

    private func load() async {
        let config = configuration
        let expectedSignature = signature
        let request = UUID()
        generation = request
        rows = []; error = nil; loading = !config.tmdbKey.isEmpty
        guard loading else { return }
        defer { if request == generation { loading = false } }
        let definitions = SearchRanking.browseRails(for: intent)
        await withTaskGroup(of: (Int, DiscoveryRail?).self) { group in
            for (index, definition) in definitions.enumerated() {
                group.addTask {
                    guard let result = try? await TMDBService().page(definition, page: 1, configuration: config) else { return (index, nil) }
                    var row = definition
                    row.metas = result
                    return (index, row)
                }
            }
            var loaded: [Int: DiscoveryRail] = [:]
            var failed = false
            for await (index, result) in group {
                guard !Task.isCancelled, request == generation, expectedSignature == signature else { group.cancelAll(); return }
                if let result {
                    if !result.metas.isEmpty { loaded[index] = result }
                } else {
                    failed = true
                }
                rows = definitions.indices.compactMap { loaded[$0] }
            }
            if failed && rows.isEmpty { error = DesktopInterfaceText.value("TMDB is temporarily unavailable. Try your search again shortly.") }
        }
    }
}
