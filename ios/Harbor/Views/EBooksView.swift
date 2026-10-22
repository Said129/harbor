import SwiftUI
import UniformTypeIdentifiers

struct EBooksView: View {
    let app: AppModel
    let initialFile: URL?
    @State private var shelf: EBookShelf
    @State private var books: [EBook] = []
    @State private var reading: HarborReadingPluginManager?
    @State private var metadata: EBookMetadataClient?
    @State private var enriched: [String: EBook] = [:]
    @State private var source = "all"
    @State private var catalog = EBookCatalogProgram()
    @State private var definitions: EBookCatalogDefinitions?
    @State private var filters = EBookBrowseFilters()
    @State private var applied = EBookBrowseFilters()
    @State private var titleLanguage = "auto"
    @State private var displayTitles: [String: String] = [:]
    @State private var batches: [String: [EBook]] = [:]
    @State private var offsets: [String: Int] = [:]
    @State private var continuation: [String: Bool] = [:]
    @State private var reload = UUID()
    @State private var query = ""
    @State private var screen = "browse"
    @State private var language = ""
    @AppStorage("ebook.shelfSort") private var shelfSort = "title"
    @State private var more = false
    @State private var loading = false
    @State private var generation = UUID()
    @State private var error: String?
    @State private var importing = false
    @State private var importingDocument = false
    @State private var help = false
    @State private var imported: EBook?
    @MainActor init(app: AppModel, initialFile: URL? = nil) { self.app = app; self.initialFile = initialFile; _screen = State(initialValue: initialFile == nil ? "browse" : "shelf"); _shelf = State(initialValue: EBookShelf(owner: app.personalOwner)) }
    private var signature: String { [query, language, source, applied.group, applied.genre, applied.status, applied.language, applied.sort, String(reading?.document.revision ?? 0), reload.uuidString].joined(separator: "|") }
    private var providers: [HarborInstalledReadingPlugin] { reading?.installed(.ebook) ?? [] }
    private var rawBooks: [EBook] { batches.keys.sorted().flatMap { batches[$0] ?? [] } }
    private var candidates: [EBook] { rawBooks.map { enriched[$0.id] ?? $0 } + shelf.records.map(\.book) }
    private var enrichmentSignature: String { generation.uuidString + "|" + rawBooks.map(\.id).joined(separator: ",") + "|" + String(metadata?.revision ?? 0) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("eBook", selection: $screen) { Text("Explorar").tag("browse"); Text(DesktopInterfaceText.value("Discover")).tag("discover"); Text("Estantería").tag("shelf") }.pickerStyle(.segmented).padding(.horizontal).accessibilityIdentifier("ebook-screen")
                HarborSearchField(prompt: screen == "shelf" ? "Buscar en tu estantería…" : screen == "browse" && source == "gutenberg" ? "Buscar en Gutenberg…" : DesktopInterfaceText.value("Search") + "…", text: $query, dismissOnSubmit: true)
                    .padding(.horizontal).accessibilityIdentifier("ebook-search")
                if let message = error ?? shelf.error { Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                Button { importing = true } label: { Label("Importar desde Archivos · EPUB / PDF", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44) }.padding(.horizontal).disabled(importingDocument).accessibilityIdentifier("ebook-import")
                if importingDocument { ProgressView("Importando libro…").frame(maxWidth: .infinity) }
                if screen == "browse" {
                    HStack {
                        Picker(DesktopInterfaceText.value("Source"), selection: $source) {
                            Text(DesktopInterfaceText.value("All sources")).tag("all")
                            Text("Project Gutenberg").tag("gutenberg")
                            ForEach(providers) { Text($0.entry.name).tag($0.id) }
                        }.accessibilityIdentifier("ebook-source")
                        Spacer()
                        Picker("Idioma de lectura", selection: $language) { Text("English").tag("en"); Text("Español").tag("es"); Text("Français").tag("fr"); Text("Deutsch").tag("de"); Text("العربية").tag("ar"); Text("Todos").tag("") }.accessibilityIdentifier("ebook-content-language")
                    }.padding(.horizontal)
                    EBookBrowseControls(filters: $filters, titleLanguage: $titleLanguage, definitions: definitions) {
                        applied = filters; query = ""; reload = UUID()
                    } reset: {
                        filters = .init(); applied = .init(); query = ""; reload = UUID()
                    }
                    grid(books)
                    if loading { ProgressView("Buscando libros…").frame(maxWidth: .infinity) }
                    else if error != nil { Button("Reintentar búsqueda") { Task { await load(next: false) } }.frame(maxWidth: .infinity, minHeight: 44) }
                    else if books.isEmpty { ContentUnavailableView("Sin resultados", image: "nav-ebook", description: Text("Busca por título o autor, o cambia el idioma.")) }
                    if more { Button("Cargar más") { Task { await load(next: true) } }.disabled(loading).frame(maxWidth: .infinity) }
                } else if screen == "discover" {
                    if let reading { EBookDiscoveryView(manager: reading, shelf: shelf, query: query, candidates: candidates, definitions: definitions) }
                    else { ProgressView().frame(maxWidth: .infinity) }
                } else {
                    HStack { Text("Tu estantería").font(.headline); Spacer(); ReadingSortMenu(selection: $shelfSort) }.padding(.horizontal)
                    grid(savedBooks)
                    if savedBooks.isEmpty { ContentUnavailableView(query.isEmpty ? "Tu estantería" : "Sin resultados", image: "nav-ebook", description: Text(query.isEmpty ? "Los libros que abras e importes aparecerán aquí." : "Busca por título o autor entre tus libros guardados.")) }
                }
            }.padding(.vertical, 16)
        }.scrollDismissesKeyboard(.interactively).background(HarborTheme.background).navigationTitle("eBook").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { if let reading { NavigationLink { EBookMetadataSettingsView(manager: reading) } label: { Image(systemName: "gearshape") }.accessibilityLabel(DesktopInterfaceText.value("Book metadata")).accessibilityIdentifier("ebook-metadata-settings") } }
                ToolbarItem(placement: .topBarTrailing) { NavigationLink { HarborPluginManagementView(app: app, kind: .ebook) } label: { Image(systemName: "puzzlepiece.extension") }.accessibilityLabel(DesktopInterfaceText.value("Plugins")) }
                ToolbarItem(placement: .topBarTrailing) { Button { help = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("Cómo leer tus libros").accessibilityIdentifier("ebook-reading-help") }
            }
            .sheet(isPresented: $help) { ReadingHelpView() }
            .task { if let initialFile { await importBook(initialFile) } }
            .task { do { definitions = try await catalog.filterDefinitions() } catch { self.error = "No se pudieron cargar los filtros de libros." } }
            .task(id: app.accountOperationScope) {
                do { let manager = try await app.openReadingPlugins(); reading = manager; metadata = try manager.ebookMetadata() }
                catch is CancellationError { return }
                catch { self.error = HarborPluginMessages.error(error) }
            }
            .onChange(of: providers.map(\.id)) { _, ids in if !["gutenberg", "all"].contains(source), !ids.contains(source) { source = "all" } }
            .task(id: titleLanguage) { try? await updateCatalog(token: generation) }
            .task(id: signature + "|" + screen) { if screen == "browse" && !importingDocument { await load(next: false) } }
            .task(id: enrichmentSignature) { await enrichCatalog() }
            .refreshable { if screen == "browse" { await load(next: false) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data, .pdf], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let files): Task {
                    var failures: [String] = []
                    for file in files {
                        await importBook(file, open: files.count == 1)
                        if let error { failures.append(file.lastPathComponent + ": " + error) }
                    }
                    if !failures.isEmpty { error = failures.joined(separator: "\n") }
                }
                case .failure: error = "No se pudo abrir el archivo elegido."
                }
            }
            .navigationDestination(item: $imported) { book in BookReaderDestination(book: book, shelf: shelf) }
            .environment(\.readingPlugins, reading)
    }
    private var savedBooks: [EBook] {
        let order = ReadingShelfSort(rawValue: shelfSort) ?? .title
        return shelf.records.filter { ReadingShelfSort.matches(query, title: $0.book.title, author: $0.book.authors.joined(separator: " ")) }.sorted {
            order.before(title: $0.book.title, author: $0.book.authors.joined(separator: " "), updated: $0.updated, id: $0.id,
                         title: $1.book.title, author: $1.book.authors.joined(separator: " "), updated: $1.updated, id: $1.id)
        }.map(\.book)
    }
    private func grid(_ entries: [EBook]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 180))], alignment: .leading, spacing: 18) {
            ForEach(entries) { book in
                NavigationLink { EBookDetailView(book: book, shelf: shelf, candidates: candidates).environment(\.readingPlugins, reading) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        EBookCover(book: book, owner: shelf.owner).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(.rect(cornerRadius: 8))
                        Text(displayTitles[book.id] ?? book.title).font(.caption.weight(.medium)).lineLimit(2)
                        Text(book.authors.first ?? book.source).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        if let alternatives = book.alternativeSources { Text("\(alternatives.count) " + DesktopInterfaceText.value("Sources")).font(.caption2).foregroundStyle(.secondary) }
                        if screen == "shelf", let record = shelf.record(book) {
                            Text(record.completed ? "Leído" : book.isPDF ? "Página \(record.block + 1)" : "Sección \(record.chapter + 1)").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("ebook-card-" + book.id).contextMenu {
                    if screen == "shelf" {
                        Button("Eliminar libro guardado", role: .destructive) {
                            Task { do { try await EBookService.shared.remove(book, owner: shelf.owner); try shelf.remove(book) } catch { self.error = safeMessage(error) } }
                        }
                    }
                }
            }
        }.padding(.horizontal)
    }
    private func load(next: Bool) async {
        if next && loading { return }
        let token = UUID(); generation = token
        let scope = app.accountOperationScope
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let term = typed.utf16.count >= 2 ? typed : "", selectedLanguage = language, tag = applied.sourceTag
        loading = true; error = nil
        if !next { books = []; more = false; batches = [:]; enriched = [:]; offsets = [:]; continuation = [:]; displayTitles = [:] }
        defer { if generation == token { loading = false } }
        do {
            if !next { try await Task.sleep(for: .milliseconds(350)) }
            let plugins = providers.filter { plugin in
                let declared = plugin.entry.language.lowercased().split(separator: "-").first.map(String.init) ?? ""
                return (source == "all" || source == plugin.id) && (selectedLanguage.isEmpty || ["", "all", "multi", selectedLanguage].contains(declared))
            }
            var requests = plugins.map { CatalogRequest(id: $0.id, offset: offsets[$0.id] ?? 0, plugin: $0) }
            if ["all", "gutenberg"].contains(source) { requests.insert(.init(id: "gutenberg", offset: offsets["gutenberg"] ?? 1, plugin: nil), at: 0) }
            let order = requests.map(\.id)
            requests = requests.filter { !next || continuation[$0.id] != false }
            let manager = reading
            var successes = 0
            try await withThrowingTaskGroup(of: CatalogPage.self) { group in
                var cursor = 0
                func enqueue(_ index: Int) {
                    let request = requests[index]
                    group.addTask {
                        do {
                            if let plugin = request.plugin {
                                guard let manager else { throw HarborPluginRepositoryError("plugin-unavailable") }
                                let rows = try await manager.ebookBrowse(plugin, query: term, offset: request.offset, tag: tag)
                                return .init(id: request.id, books: rows, offset: request.offset + rows.count, more: !rows.isEmpty, failed: false)
                            }
                            let result = try await EBookService.shared.catalog(query: term, language: selectedLanguage, page: request.offset)
                            return .init(id: request.id, books: result.0, offset: request.offset + 1, more: result.1, failed: false)
                        } catch is CancellationError { throw CancellationError() }
                        catch { return .init(id: request.id, books: [], offset: request.offset, more: true, failed: true) }
                    }
                }
                while cursor < min(4, requests.count) { enqueue(cursor); cursor += 1 }
                for try await result in group {
                    try Task.checkCancellation()
                    guard token == generation, scope == app.accountOperationScope else { group.cancelAll(); throw CancellationError() }
                    if !result.failed {
                        successes += 1
                        var seen = Set<String>()
                        batches[result.id] = ((next ? batches[result.id] ?? [] : []) + result.books).filter { seen.insert($0.id).inserted }
                        offsets[result.id] = result.offset; continuation[result.id] = result.more
                        try await updateCatalog(token: token, order: order)
                    } else { continuation[result.id] = true }
                    if cursor < requests.count { enqueue(cursor); cursor += 1 }
                }
            }
            guard token == generation, scope == app.accountOperationScope else { return }
            more = continuation.values.contains(true)
            if !requests.isEmpty && successes == 0 { throw HarborError(code: "ebook-network") }
        } catch is CancellationError { return }
        catch { if token == generation { self.error = source == "gutenberg" ? "No se pudo cargar Project Gutenberg. Vuelve a intentarlo." : HarborPluginMessages.error(error) } }
    }
    private struct CatalogRequest: Sendable { let id: String; let offset: Int; let plugin: HarborInstalledReadingPlugin? }
    private struct CatalogPage: Sendable { let id: String; let books: [EBook]; let offset: Int; let more: Bool; let failed: Bool }
    private func updateCatalog(token: UUID, order: [String]? = nil) async throws {
        let ids = order ?? (["gutenberg"] + providers.map(\.id))
        let rules = applied, titles = titleLanguage
        let input = ids.flatMap { batches[$0] ?? [] }.map { enriched[$0.id] ?? $0 }
        let result = try await catalog.filter(input, filters: rules, titleLanguage: titles)
        try Task.checkCancellation()
        guard token == generation, applied == rules, titleLanguage == titles else { return }
        books = result.books; displayTitles = result.titles
    }
    private func enrichCatalog() async {
        guard let metadata, !rawBooks.isEmpty else { return }
        let input = rawBooks, token = generation, scope = app.accountOperationScope
        func publish(_ result: [EBook]) async {
            guard !Task.isCancelled, generation == token, scope == app.accountOperationScope else { return }
            for book in result.flatMap({ $0.alternativeSources ?? [$0] }) { enriched[book.id] = book }
            try? await updateCatalog(token: token)
        }
        do { let result = try await metadata.enrich(input, onPartial: publish); await publish(result) }
        catch { /* Metadata is supplementary; source catalogs and readable routes remain available. */ }
    }
    private func importBook(_ file: URL, open: Bool = true) async {
        guard shelf.ready else { error = "La estantería no está disponible. Los libros guardados se conservan."; return }
        importingDocument = true; error = nil
        defer { importingDocument = false }
        do {
            let book = try await EBookService.shared.importDocument(file, owner: shelf.owner)
            try Task.checkCancellation()
            guard shelf.owner == (app.personalOwner) else { return }
            try shelf.addImported(book)
            screen = "shelf"
            if open { imported = book }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}
