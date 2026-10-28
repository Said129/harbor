import Foundation

enum CustomListMangaArtworkSelection {
    static func matches(_ item: CustomListItem, _ book: MangaBook) -> Bool {
        [item.name, item.raw["altTitle"].string].compactMap { $0 }.contains {
            CustomListMangaTitle.matches($0, title: book.title, alternate: book.metadata?["altTitle"].string)
        }
    }
    static func saved(_ item: CustomListItem, books: [MangaBook], server: String?, plugins: Set<String>) -> MangaBook? {
        books.first {
            guard $0.id == item.id, matches(item, $0) else { return false }
            if let plugin = $0.pluginID { return plugins.contains(plugin) }
            if let source = $0.server { return source == server }
            return true
        }
    }
}

@MainActor final class CustomListMangaArtworkContext {
    let activation: String
    let owner: String
    let client: SuwayomiClient?
    let reading: HarborReadingPluginManager?
    private let books: [MangaBook]
    private let isCurrent: @MainActor () -> Bool
    var active: Bool { isCurrent() }
    private var requests: [String: Task<MangaBook?, Never>] = [:]
    init(activation: String, owner: String, books: [MangaBook], client: SuwayomiClient?, reading: HarborReadingPluginManager?, isCurrent: @escaping @MainActor () -> Bool) {
        self.activation = activation; self.owner = owner; self.books = books; self.client = client; self.reading = reading; self.isCurrent = isCurrent
    }
    func resolve(_ item: CustomListItem) async -> MangaBook? {
        guard isCurrent(), !Task.isCancelled else { return nil }
        let plugins = reading?.installed(.manga, includeAdult: UserDefaults.standard.bool(forKey: "manga.adultSources")) ?? []
        if let book = CustomListMangaArtworkSelection.saved(item, books: books, server: client?.server.id, plugins: Set(plugins.map(\.id))) { return book }
        let key = EBookShelf.hash(item.id + "|" + item.name + "|" + (item.poster ?? ""))
        if let request = requests[key] {
            let result = await request.value
            return isCurrent() && !Task.isCancelled ? result : nil
        }
        let request = Task<MangaBook?, Never> { [client, reading] in
            let book: MangaBook?
            if let plugin = plugins.first(where: { item.id.hasPrefix($0.entry.id + "::") }) {
                let remote = String(item.id.dropFirst(plugin.entry.id.count + 2))
                guard !remote.isEmpty, let reading else { return nil }
                let candidate = MangaBook(id: item.id, title: item.name, remoteID: remote, sourceID: plugin.entry.id, pluginID: plugin.id)
                book = try? await reading.mangaDetail(candidate)
            } else if let client {
                let prefix = client.server.id + ":"
                let remote = item.id.hasPrefix(prefix) ? String(item.id.dropFirst(prefix.count)) : item.id
                guard !remote.isEmpty, remote.allSatisfy(\.isNumber) else { return nil }
                book = try? await client.detail(.init(id: item.id, title: item.name, server: client.server.id, remoteID: remote))
            } else { return nil }
            guard !Task.isCancelled, let book, CustomListMangaArtworkSelection.matches(item, book) else { return nil }
            return book
        }
        requests[key] = request
        let result = await request.value
        return isCurrent() && !Task.isCancelled ? result : nil
    }
    func cancel() { requests.values.forEach { $0.cancel() }; requests.removeAll() }
}
