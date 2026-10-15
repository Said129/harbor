import SwiftUI
import UniformTypeIdentifiers

struct EBooksView: View {
    let app: AppModel
    let initialFile: URL?
    @State private var shelf: EBookShelf
    @State private var books: [EBook] = []
    @State private var query = ""
    @State private var screen = "browse"
    @State private var language = ""
    @AppStorage("ebook.shelfSort") private var shelfSort = "title"
    @State private var page = 1
    @State private var more = false
    @State private var loading = false
    @State private var generation = UUID()
    @State private var error: String?
    @State private var importing = false
    @State private var importingDocument = false
    @State private var help = false
    @State private var imported: EBook?
    @MainActor init(app: AppModel, initialFile: URL? = nil) { self.app = app; self.initialFile = initialFile; _screen = State(initialValue: initialFile == nil ? "browse" : "shelf"); _shelf = State(initialValue: EBookShelf(owner: app.user?.id ?? "guest")) }
    private var signature: String { query + "|" + language }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("eBook", selection: $screen) { Text("Explorar").tag("browse"); Text("Estantería").tag("shelf") }.pickerStyle(.segmented).padding(.horizontal).accessibilityIdentifier("ebook-screen")
                HarborSearchField(prompt: screen == "browse" ? "Buscar en Gutenberg…" : "Buscar en tu estantería…", text: $query, dismissOnSubmit: true)
                    .padding(.horizontal).accessibilityIdentifier("ebook-search")
                if let message = error ?? shelf.error { Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                Button { importing = true } label: { Label("Importar desde Archivos · EPUB / PDF", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44) }.padding(.horizontal).disabled(importingDocument).accessibilityIdentifier("ebook-import")
                if importingDocument { ProgressView("Importando libro…").frame(maxWidth: .infinity) }
                if screen == "browse" {
                    HStack {
                        Text("Project Gutenberg").font(.headline)
                        Spacer()
                        Picker("Idioma", selection: $language) { Text("English").tag("en"); Text("Español").tag("es"); Text("Français").tag("fr"); Text("Deutsch").tag("de"); Text("Todos").tag("") }
                    }.padding(.horizontal)
                    grid(books)
                    if loading { ProgressView("Buscando libros…").frame(maxWidth: .infinity) }
                    else if error != nil { Button("Reintentar búsqueda") { Task { await load(next: false) } }.frame(maxWidth: .infinity, minHeight: 44) }
                    else if books.isEmpty { ContentUnavailableView("Sin resultados", image: "nav-ebook", description: Text("Busca por título o autor, o cambia el idioma.")) }
                    if more { Button("Cargar más") { Task { await load(next: true) } }.disabled(loading).frame(maxWidth: .infinity) }
                } else {
                    HStack { Text("Tu estantería").font(.headline); Spacer(); ReadingSortMenu(selection: $shelfSort) }.padding(.horizontal)
                    grid(savedBooks)
                    if savedBooks.isEmpty { ContentUnavailableView(query.isEmpty ? "Tu estantería" : "Sin resultados", image: "nav-ebook", description: Text(query.isEmpty ? "Los libros que abras e importes aparecerán aquí." : "Busca por título o autor entre tus libros guardados.")) }
                }
            }.padding(.vertical, 16)
        }.scrollDismissesKeyboard(.interactively).background(HarborTheme.background).navigationTitle("eBook").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { help = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("Cómo leer tus libros").accessibilityIdentifier("ebook-reading-help") } }
            .sheet(isPresented: $help) { ReadingHelpView() }
            .task { if let initialFile { await importBook(initialFile) } }
            .task(id: signature + "|" + screen) { if screen == "browse" && !importingDocument { await load(next: false) } }
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
                NavigationLink { BookReaderDestination(book: book, shelf: shelf) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        EBookCover(book: book, owner: shelf.owner).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(.rect(cornerRadius: 8))
                        Text(book.title).font(.caption.weight(.medium)).lineLimit(2)
                        Text(book.authors.first ?? book.source).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
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
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines), selectedLanguage = language, requestedPage = next ? page + 1 : 1
        loading = true; error = nil
        if !next { books = []; more = false }
        defer { if generation == token { loading = false } }
        do {
            if !next { try await Task.sleep(for: .milliseconds(350)) }
            let result = try await EBookService.shared.catalog(query: term, language: selectedLanguage, page: requestedPage)
            try Task.checkCancellation()
            guard token == generation else { return }
            var seen = Set<String>()
            books = ((next ? books : []) + result.0).filter { seen.insert($0.id).inserted }; more = result.1; page = requestedPage
        } catch is CancellationError { return }
        catch { if token == generation { self.error = "No se pudo cargar Project Gutenberg. Vuelve a intentarlo." } }
    }
    private func importBook(_ file: URL, open: Bool = true) async {
        guard shelf.ready else { error = "La estantería no está disponible. Los libros guardados se conservan."; return }
        importingDocument = true; error = nil
        defer { importingDocument = false }
        do {
            let book = try await EBookService.shared.importDocument(file, owner: shelf.owner)
            try Task.checkCancellation()
            guard shelf.owner == (app.user?.id ?? "guest") else { return }
            try shelf.addImported(book)
            screen = "shelf"
            if open { imported = book }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}
