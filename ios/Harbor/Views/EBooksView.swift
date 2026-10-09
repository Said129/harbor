import SwiftUI
import UniformTypeIdentifiers

struct EBooksView: View {
    let app: AppModel
    @State private var shelf: EBookShelf
    @State private var books: [EBook] = []
    @State private var query = ""
    @State private var screen = "browse"
    @State private var language = "en"
    @State private var page = 1
    @State private var more = false
    @State private var loading = false
    @State private var generation = UUID()
    @State private var error: String?
    @State private var importing = false
    @State private var imported: EBook?
    @MainActor init(app: AppModel) { self.app = app; _shelf = State(initialValue: EBookShelf(owner: app.user?.id ?? "guest")) }
    private var signature: String { query + "|" + language }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("eBook", selection: $screen) { Text("Explorar").tag("browse"); Text("Estantería").tag("shelf") }.pickerStyle(.segmented).padding(.horizontal)
                if let message = error ?? shelf.error { Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if screen == "browse" {
                    HStack {
                        Text("Project Gutenberg").font(.headline)
                        Spacer()
                        Picker("Idioma", selection: $language) { Text("English").tag("en"); Text("Español").tag("es"); Text("Français").tag("fr"); Text("Deutsch").tag("de"); Text("Todos").tag("") }
                    }.padding(.horizontal)
                    grid(books)
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    else if books.isEmpty { ContentUnavailableView("Sin resultados", image: "nav-ebook", description: Text("Busca por título o autor, o cambia el idioma.")) }
                    if more { Button("Cargar más") { Task { await load(next: true) } }.disabled(loading).frame(maxWidth: .infinity) }
                } else {
                    let saved = shelf.records.sorted { $0.updated > $1.updated }
                    ForEach(saved) { record in
                        NavigationLink { EBookReaderView(book: record.book, shelf: shelf) } label: {
                            HStack(spacing: 16) {
                                Artwork(url: record.book.cover, maxPixels: 280).frame(width: 58, height: 86).clipShape(.rect(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(record.book.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(record.completed ? "Leído" : "Sección \(record.chapter + 1)").font(.caption).foregroundStyle(.secondary)
                                    Text(record.book.authors.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption)
                            }.padding(.horizontal)
                        }.buttonStyle(.plain).contextMenu {
                            Button("Eliminar libro guardado", role: .destructive) {
                                Task { do { try await EBookService.shared.remove(record.book, owner: shelf.owner); try shelf.remove(record.book) } catch { self.error = safeMessage(error) } }
                            }
                        }
                    }
                    if saved.isEmpty { ContentUnavailableView("Tu estantería", image: "nav-ebook", description: Text("Los libros que abras e importes aparecerán aquí.")) }
                }
            }.padding(.vertical, 16)
        }.background(HarborTheme.background).navigationTitle("eBook").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Libros y autores")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("Importar EPUB") } }
            .task(id: signature) { await load(next: false) }
            .refreshable { await load(next: false) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "epub") ?? .data]) { result in
                switch result {
                case .success(let file): Task { await importBook(file) }
                case .failure: error = "No se pudo abrir el archivo elegido."
                }
            }
            .navigationDestination(item: $imported) { book in EBookReaderView(book: book, shelf: shelf) }
    }
    private func grid(_ entries: [EBook]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
            ForEach(entries) { book in
                NavigationLink { EBookReaderView(book: book, shelf: shelf) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Artwork(url: book.cover, maxPixels: 500).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(.rect(cornerRadius: 8))
                        Text(book.title).font(.caption.weight(.medium)).lineLimit(2)
                        Text(book.authors.first ?? book.source).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal)
    }
    private func load(next: Bool) async {
        if next && loading { return }
        let token = UUID(); generation = token
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines), selectedLanguage = language, requestedPage = next ? page + 1 : 1
        loading = true; error = nil
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
    private func importBook(_ file: URL) async {
        guard shelf.ready else { error = "La estantería no está disponible. Los libros guardados se conservan."; return }
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 48 * 1024 * 1024 else { throw HarborError(code: "ebook-size") }
                return try Data(contentsOf: file)
            }.value
            var book = EBook(id: "local:\(UUID().uuidString)", title: file.deletingPathExtension().lastPathComponent, source: "Archivo local")
            let publication = try await EBookService.shared.open(book, owner: shelf.owner, imported: data)
            book.title = publication.title; book.authors = publication.authors; book.language = publication.language
            try shelf.save(EBookRecord(book: book)); screen = "shelf"; imported = book
        } catch { self.error = safeMessage(error) }
    }
}
