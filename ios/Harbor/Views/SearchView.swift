import SwiftUI

struct SearchView: View {
    let app: AppModel
    @State private var query = ""
    @State private var rows: [CatalogRow] = []
    @State private var topMatch: Media?
    @State private var matchDestination: Media?
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
            if !isTitleQuery { SearchLinkCard(app: app, input: linkInput).padding().id(linkInput) }
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentSearches
                if history.items.isEmpty { ContentUnavailableView("Busca en tus addons", systemImage: "magnifyingglass", description: Text("Películas, series y catálogos instalados.")) }
            }
            else if isTitleQuery && rows.isEmpty && topMatch == nil && browseIntent == nil && !loading { ContentUnavailableView.search(text: query) }
            if let completedQuery {
                Text("Resultados para «\(completedQuery)»").font(.headline).padding()
                    .accessibilityIdentifier("search-results-query")
            }
            if let browseIntent {
                NavigationLink {
                    SearchBrowseResults(intent: browseIntent, app: app)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(DesktopInterfaceText.value("Browse")).font(.caption).foregroundStyle(HarborTheme.accent)
                            Text(browseIntent.title).font(HarborTheme.font(15, weight: .semibold))
                        }
                    } icon: {
                        Image(systemName: browseIntent.symbol).foregroundStyle(HarborTheme.accent)
                    }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 14)
                        .background(HarborTheme.accent.opacity(0.12), in: .rect(cornerRadius: 14))
                }.buttonStyle(.plain).padding(.horizontal).accessibilityIdentifier("search-browse-intent")
            }
            if isTitleQuery, let topMatch {
                SearchTopMatchCard(media: topMatch, destination: matchDestination ?? topMatch, app: app).padding(.horizontal)
            }
            if let anime = topAnime { AniListRelationsSection(media: anime, app: app).padding(.horizontal).padding(.bottom, 8) }
            if isTitleQuery { SearchLiveTVSection(app: app, query: query) }
            if isTitleQuery { SearchPeopleSection(app: app, query: query) }
            aiSearchLink
            CatalogRails(rows: SearchPresentation.rows(rows), app: app, titleOverrides: searchTitles, browseCatalogs: false, onSelect: { history.record(query) })
        }
        .background(HarborTheme.background).navigationTitle("Buscar")
        .searchable(text: $query, prompt: "Título")
        .onSubmit(of: .search) { history.record(query) }
        .onDisappear { if completedQuery != nil { history.record(query) } }
        .refreshable { ArtworkRefresh.shared.retryFailedImages(); await search() }
        .task(id: query + "|" + searchContext) { await search() }
    }
    /// A pasted magnet, info hash or direct video link gets a Play card instead of a catalog search.
    private var linkInput: SearchInput { SearchInput.classify(query) }
    private var isTitleQuery: Bool { if case .query = linkInput { true } else { false } }
    private var browseIntent: SearchQueryIntent? { isTitleQuery ? SearchRanking.intent(query) : nil }
    private var searchContext: String {
        let configuration = MetadataPreferences.shared.configuration()
        return [app.accountOperationScope, app.addons.filter(\.enabled).map(\.id).joined(separator: "|"),
                EBookShelf.hash(configuration.tmdbKey), configuration.language, String(configuration.translateTitles)].joined(separator: "|")
    }
    /// Desktop shows the sequels and prequels of the best match when that match is an anime (`topMatchIsAnime`).
    private var topAnime: Media? {
        guard isTitleQuery, completedQuery != nil, let first = SearchPresentation.rows(rows).first,
              first.id != SearchAnimeSource.rowID, first.isAnimeCatalog else { return nil }
        return first.metas.first
    }
    /// Desktop's "Ask AI" entry: a screen that finds titles from a plain-language request with the person's own key.
    @ViewBuilder private var aiSearchLink: some View {
        if isTitleQuery && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SearchAILink(app: app, query: query)
        }
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
        let requestContext = searchContext
        let configuration = MetadataPreferences.shared.configuration()
        rows = []; error = nil; completedQuery = nil; loading = !requestedQuery.isEmpty
        topMatch = nil; matchDestination = nil
        guard !requestedQuery.isEmpty, case .query = SearchInput.classify(requestedQuery) else { loading = false; return }
        do {
            try await Task.sleep(for: .milliseconds(300))
            async let animeSearch = AnimeService.shared.search(requestedQuery)
            async let tmdbSearch = SearchTMDBSource.load(query: requestedQuery, configuration: configuration)
            var addonRows: [CatalogRow] = []
            var warnings: [String] = []
            var addonPlanningFailed = false
            do {
                let providers = try await app.service.catalogProviders(app.addons)
                (addonRows, warnings) = try await app.service.catalogs(providers, search: requestedQuery, onRow: { row in
                    guard isCurrent(request, query: requestedQuery, context: requestContext) else { return }
                    if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index] = row }
                    else { rows.append(row) }
                    completedQuery = requestedQuery
                })
            } catch is CancellationError { throw CancellationError() }
            catch {
                // Keep any rows already streamed into the view while public providers continue independently.
                addonRows = rows
                addonPlanningFailed = true
            }
            try Task.checkCancellation()
            let matches = await tmdbSearch
            try Task.checkCancellation()
            guard isCurrent(request, query: requestedQuery, context: requestContext) else { return }
            let tmdbRows = SearchTMDBSource.rows(for: matches.titles, addonRows: addonRows)
            topMatch = matches.topMatch
            matchDestination = matches.topMatch.map { SearchTMDBSource.destination(for: $0, addonRows: addonRows) }
            rows = SearchPresentation.rows(addonRows + tmdbRows)
            completedQuery = requestedQuery
            let anime = await animeSearch
            try Task.checkCancellation()
            guard isCurrent(request, query: requestedQuery, context: requestContext) else { return }
            let animeRows = SearchAnimeSource.row(metas: anime, excluding: (addonRows + tmdbRows).flatMap(\.metas)).map { [$0] } ?? []
            rows = SearchPresentation.rows(addonRows + tmdbRows + animeRows)
            completedQuery = requestedQuery
            let hasResults = topMatch != nil || rows.contains(where: { !$0.metas.isEmpty })
            error = (addonPlanningFailed || !warnings.isEmpty) && !hasResults
                ? "No se pudo completar la búsqueda. Reintentar puede recuperar los resultados."
                : nil
            loading = false
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled, isCurrent(request, query: requestedQuery, context: requestContext) else { return }
            self.error = safeMessage(error); loading = false
        }
    }

    private func isCurrent(_ request: UUID, query requestedQuery: String, context: String) -> Bool {
        generation == request && query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery
            && searchContext == context
    }
}

private struct SearchTopMatchCard: View {
    let media: Media
    let destination: Media
    let app: AppModel
    @Environment(\.locale) private var locale

    private func text(_ key: String, variables: [String: String] = [:]) -> String {
        DesktopInterfaceText.value(key, variables: variables, language: locale.identifier)
    }

    var body: some View {
        NavigationLink {
            DetailView(media: destination, app: app)
        } label: {
            HStack(spacing: 14) {
                Artwork(url: media.poster, maxPixels: 350)
                    .frame(width: 80, height: 120).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(text("Top match").uppercased(with: locale)).font(HarborTheme.font(11, weight: .semibold))
                        .tracking(2).foregroundStyle(HarborTheme.accent)
                    Text(media.name).font(HarborTheme.displayFont(24)).lineLimit(2)
                    HStack(spacing: 7) {
                        Text(text(media.type == "movie" ? "Movie" : "Series"))
                        if let year = media.releaseInfo { Text(year) }
                        if let rating = media.imdbRating { Label(rating, systemImage: "star.fill") }
                    }.font(HarborTheme.font(12)).foregroundStyle(.secondary)
                    if let overview = media.description {
                        Text(overview).font(HarborTheme.font(12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward").font(.subheadline).foregroundStyle(HarborTheme.accent)
            }.padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 16))
        }.buttonStyle(.plain)
            .accessibilityLabel(text("Open {name}", variables: ["name": media.name]))
            .accessibilityIdentifier("search-title-top-match")
    }
}
