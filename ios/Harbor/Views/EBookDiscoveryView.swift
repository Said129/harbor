import SwiftUI

struct EBookDiscoveryView: View {
    let manager: HarborReadingPluginManager
    let shelf: EBookShelf
    let query: String
    let candidates: [EBook]
    let definitions: EBookCatalogDefinitions?
    var app: AppModel? = nil
    @State private var mode = "popular"
    @State private var category = ""
    @State private var books: [EBook] = []
    @State private var page = 1
    @State private var more = false
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = UUID()
    private func text(_ value: String) -> String { DesktopInterfaceText.value(value) }
    private var signature: String { query + "|" + mode + "|" + category + "|" + String(manager.document.revision) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Picker(text("Discover"), selection: $mode) {
                    Text(text("Popular")).tag("popular")
                    Text(text("Top rated")).tag("SCORE_DESC")
                    Text(text("Trending")).tag("TRENDING_DESC")
                    Text(text("New releases")).tag("new")
                }.accessibilityIdentifier("ebook-discovery-mode")
                Spacer()
                Picker(text("Category"), selection: $category) {
                    Text(text("All")).tag("")
                    ForEach((definitions?.categories.keys.sorted() ?? []), id: \.self) { group in
                        Section(text(group)) { ForEach(definitions?.categories[group] ?? [], id: \.self) { Text(text($0)).tag($0) } }
                    }
                }.accessibilityIdentifier("ebook-discovery-category")
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary); Button(text("Retry")) { Task { await load(next: false) } } }
            EBookGrid(books: books, shelf: shelf, manager: manager, candidates: candidates, app: app)
            if loading { ProgressView(text("Loading")).frame(maxWidth: .infinity) }
            else if books.isEmpty && failure == nil { ContentUnavailableView(text("No results"), systemImage: "books.vertical") }
            if more { Button(text("Load more")) { Task { await load(next: true) } }.disabled(loading).frame(maxWidth: .infinity, minHeight: 44) }
        }.padding(.horizontal).task(id: signature) { await load(next: false) }
    }
    private func load(next: Bool) async {
        guard !next || !loading else { return }
        let token = UUID(); generation = token
        loading = true; failure = nil
        if !next { books = []; page = 1; more = false }
        defer { if generation == token { loading = false } }
        do {
            if !next { try await Task.sleep(for: .milliseconds(350)) }
            let client = try manager.ebookMetadata(), term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var arguments: [String: JSONValue] = [:]
            let operation: String
            if term.utf16.count >= 2 { operation = "search"; arguments["query"] = .string(term); if !category.isEmpty { arguments["category"] = .string(category) } }
            else if !category.isEmpty { operation = "category"; arguments["category"] = .string(category) }
            else if mode == "popular" || mode == "new" { operation = mode }
            else { operation = "browse"; arguments["sort"] = .string(mode); arguments["page"] = .integer(Int64(page)) }
            let raw = try await client.query(operation, arguments: arguments)
            let linked = try await client.query("attach", arguments: ["books": raw, "sources": .array(candidates.map(EBookMetadataMapping.raw))])
            try Task.checkCancellation(); guard generation == token else { return }
            let result = EBookMetadataMapping.books(linked, preserving: candidates)
            var seen = Set<String>(); books = ((next ? books : []) + result).filter { seen.insert($0.id).inserted }
            more = operation == "browse" && !result.isEmpty; page += 1
        } catch is CancellationError { return }
        catch { if generation == token { failure = "No se pudieron cargar estos libros. Vuelve a intentarlo." } }
    }
}

struct EBookGrid: View {
    let books: [EBook]
    let shelf: EBookShelf
    let manager: HarborReadingPluginManager
    var candidates: [EBook] = []
    var app: AppModel? = nil
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180))], alignment: .leading, spacing: 18) {
            ForEach(books) { book in
                NavigationLink { EBookDetailView(book: book, shelf: shelf, candidates: candidates, app: app).environment(\.readingPlugins, manager) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        EBookCover(book: book, owner: shelf.owner).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(.rect(cornerRadius: 8))
                        Text(book.title).font(.caption.weight(.medium)).lineLimit(2)
                        Text(book.authors.first ?? book.source).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("ebook-discovery-card-" + book.id)
            }
        }
    }
}
