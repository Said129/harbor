import SwiftUI

struct CustomListMangaDestination: View {
    let app: AppModel
    let item: CustomListItem
    let listID: String
    @State private var book: MangaBook?
    @State private var shelf: MangaShelf?
    @State private var client: SuwayomiClient?
    @State private var manager: HarborReadingPluginManager?
    @State private var failure: String?
    @State private var retry = 0
    @AppStorage("manga.adultSources") private var adult = false
    @Environment(\.locale) private var locale
    var body: some View {
        Group {
            if let book, let shelf { MangaDetailView(book: book, shelf: shelf, client: book.server == client?.server.id ? client : nil) }
            else if let failure {
                VStack(spacing: 16) {
                    Text(failure).font(HarborTheme.font(14)).multilineTextAlignment(.center)
                    Button(DesktopInterfaceText.value("Retry", language: locale.identifier)) { retry += 1 }.frame(minHeight: 44)
                    NavigationLink { MangaView(app: app) } label: { Text(DesktopInterfaceText.value("Manga sources", language: locale.identifier)).frame(minHeight: 44) }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(HarborTheme.background).environment(\.readingPlugins, manager).toolbar(.visible, for: .navigationBar)
            .task(id: app.accountOperationScope + "|" + String(retry)) { await open() }
    }
    private func open() async {
        book = nil; failure = nil; manager = nil; client = nil
        let scope = app.accountOperationScope, target = app.customLists
        let shelf = MangaShelf(owner: app.personalOwner), connection = MangaConnection(owner: app.personalOwner)
        self.shelf = shelf
        do {
            guard shelf.ready, connection.ready else { throw HarborError(code: "manga-store") }
            let client = connection.server.map { SuwayomiClient(server: $0) }
            let local = shelf.records.map(\.book)
            let localOnly = local.contains { $0.id == item.id && $0.server == nil && $0.pluginID == nil && CustomListMangaTitle.matches(item.name, title: $0.title, alternate: $0.metadata?["altTitle"].string) }
            var manager: HarborReadingPluginManager?
            if !localOnly { manager = try? await app.openReadingPlugins() }
            try Task.checkCancellation(); guard scope == app.accountOperationScope else { return }
            let resolved = try await CustomListMangaOpening.resolve(item, local: local, server: client, reading: manager, includeAdult: adult)
            try Task.checkCancellation(); guard scope == app.accountOperationScope else { return }
            guard let resolved else { failure = DesktopInterfaceText.value("This title would not open", language: locale.identifier); return }
            if resolved.id != item.id || resolved.title != item.name || resolved.cover != item.poster {
                var update: [String: JSONValue] = ["id": .string(resolved.id), "name": .string(resolved.title)]
                update["poster"] = resolved.cover.map(JSONValue.string)
                await target.apply(.updateItem(listID, item.id, .object(update)))
                try Task.checkCancellation(); guard scope == app.accountOperationScope else { return }
            }
            self.client = client; self.manager = manager; book = resolved
        } catch is CancellationError {}
        catch { guard !Task.isCancelled, scope == app.accountOperationScope else { return }; failure = safeMessage(error) }
    }
}
