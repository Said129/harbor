import SwiftUI

struct EBookAdaptationDestination: View {
    let item: JSONValue
    let book: EBook
    let manager: HarborReadingPluginManager
    let app: AppModel
    @State private var client: EBookAdaptationClient?
    @State private var server: SuwayomiClient?
    @State private var manga: [MangaBook] = []
    @State private var anime: Media?
    @State private var loading = true
    @State private var failure: String?
    @State private var retry = UUID()
    @State private var shelf: MangaShelf
    @MainActor init(item: JSONValue, book: EBook, manager: HarborReadingPluginManager, app: AppModel) {
        self.item = item; self.book = book; self.manager = manager; self.app = app
        _shelf = State(initialValue: MangaShelf(owner: app.personalOwner))
    }
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    var body: some View {
        Group {
            if let direct = EBookAdaptationClient.directAnime(item) { DetailView(media: direct, app: app) }
            else if let anime { DetailView(media: anime, app: app) }
            else if manga.count == 1, let first = manga.first { detail(first) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if loading { ProgressView(text("Loading")).frame(maxWidth: .infinity) }
                        if let failure { Text(failure).font(.callout).foregroundStyle(.secondary) }
                        if !loading && manga.isEmpty { Text(text("No sources found")).foregroundStyle(.secondary); Button(text("Retry")) { retry = UUID() } }
                        ForEach(manga) { row in
                            NavigationLink { detail(row) } label: {
                                HStack(spacing: 16) {
                                    MangaImage(book: row, owner: app.personalOwner, path: row.cover, client: row.server == server?.server.id ? server : nil, maxPixels: 300)
                                        .frame(width: 60, height: 90).clipShape(.rect(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 8) { Text(row.title).font(.headline); Text(row.author).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }.padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityIdentifier("ebook-adaptation-choice-" + row.id)
                        }
                    }.padding(20)
                }.background(HarborTheme.background).navigationTitle(item["title"].string ?? text("Adaptations")).navigationBarTitleDisplayMode(.inline)
            }
        }.environment(\.readingPlugins, manager)
            .task(id: app.accountOperationScope + retry.uuidString) { await load() }
            .onDisappear { client?.dispose(); client = nil }
    }
    private func detail(_ book: MangaBook) -> some View {
        MangaDetailView(book: book, shelf: shelf, client: book.server == server?.server.id ? server : nil).environment(\.readingPlugins, manager)
    }
    private func load() async {
        guard EBookAdaptationClient.directAnime(item) == nil, let scope = app.pluginExecutionScope else { loading = false; return }
        client?.dispose(); let next = EBookAdaptationClient(scope: scope, currentScope: { [weak app] in app?.pluginExecutionScope ?? .init(owner: "locked", activation: scope.activation) })
        client = next; loading = true; failure = nil
        defer { if app.pluginExecutionScope == scope { loading = false } }
        do {
            if item["kind"].string == "manga" {
                let connection = MangaConnection(owner: app.personalOwner)
                let remote = connection.server.map(SuwayomiClient.init(server:)); server = remote
                let rows = try await manager.resolveMangaAdaptation(item, book: book, client: next, server: remote, includeAdult: UserDefaults.standard.bool(forKey: "manga.adultSources"))
                try Task.checkCancellation(); guard app.pluginExecutionScope == scope else { return }; manga = rows
            } else {
                let matches = try await next.query("anime-search", arguments: ["query": .string(item["title"].string ?? "")])
                let route = try await next.query("anime-route", arguments: ["item": item, "matches": matches])
                try Task.checkCancellation(); guard app.pluginExecutionScope == scope else { return }; anime = EBookAdaptationClient.animeMedia(route)
            }
        } catch is CancellationError { return }
        catch { if !Task.isCancelled, app.pluginExecutionScope == scope { failure = "No se pudo encontrar esta adaptación. Vuelve a intentarlo." } }
    }
}
