import SwiftUI
import UniformTypeIdentifiers

struct MangaView: View {
    let app: AppModel
    @State private var shelf: MangaShelf
    @State private var connection: MangaConnection
    @State private var client: SuwayomiClient?
    @State private var sources: [MangaSource] = []
    @State private var selected = ""
    @State private var screen = "browse"
    @State private var latest = false
    @State private var query = ""
    @State private var books: [MangaBook] = []
    @State private var serverLibrary: [MangaBook] = []
    @State private var page = 1
    @State private var more = false
    @State private var loading = false
    @State private var generation = UUID()
    @State private var configuring = false
    @State private var extensions = false
    @State private var importing = false
    @State private var imported: MangaBook?
    @State private var error: String?
    @AppStorage("manga.adultSources") private var adult = false
    @MainActor init(app: AppModel) {
        self.app = app
        let owner = app.user?.id ?? "guest"
        _shelf = State(initialValue: MangaShelf(owner: owner)); _connection = State(initialValue: MangaConnection(owner: owner))
    }
    private var visibleSources: [MangaSource] { sources.filter { adult || !$0.adult } }
    private var signature: String { selected + "|" + query + "|" + String(latest) + "|" + String(adult) }
    private var savedBooks: [MangaBook] {
        var seen = Set<String>()
        return (shelf.records.sorted { $0.updated > $1.updated }.map(\.book) + serverLibrary).filter { seen.insert($0.id).inserted && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Manga", selection: $screen) { Text("Explorar").tag("browse"); Text("Biblioteca").tag("shelf") }.pickerStyle(.segmented).padding(.horizontal)
                if let message = error ?? shelf.error ?? connection.error { Text(message).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                if screen == "browse" {
                    if !visibleSources.isEmpty {
                        HStack {
                            Picker("Fuente", selection: $selected) { ForEach(visibleSources) { Text("\($0.name) · \($0.language.uppercased())").tag($0.id) } }
                            Spacer()
                            if sources.first(where: { $0.id == selected })?.latest == true { Toggle("Novedades", isOn: $latest).font(.caption).fixedSize() }
                        }.padding(.horizontal)
                        grid(books)
                        if more { Button("Cargar más") { Task { await browse(next: true) } }.disabled(loading).frame(maxWidth: .infinity) }
                    } else if !loading {
                        ContentUnavailableView("Manga", image: "nav-manga", description: Text(connection.server == nil ? "Conecta tu servidor Suwayomi o importa un CBZ/ZIP desde Archivos." : "No hay fuentes disponibles. Instala extensiones en tu servidor o importa un archivo."))
                        HStack { Button("Suwayomi") { configuring = true }; Button("Importar CBZ/ZIP") { importing = true } }.frame(maxWidth: .infinity)
                    }
                } else {
                    grid(savedBooks)
                    if savedBooks.isEmpty { ContentUnavailableView("Tu biblioteca de Manga", image: "nav-manga", description: Text("Los mangas que leas o guardes y tus archivos locales aparecerán aquí.")) }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
            }.padding(.vertical, 16)
        }.background(HarborTheme.background).navigationTitle("Manga").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Buscar manga en la fuente")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Importar CBZ/ZIP o carpeta") { importing = true }
                    Button("Conexión Suwayomi") { configuring = true }
                    if client != nil { Button("Extensiones") { extensions = true } }
                    Toggle("Fuentes para adultos", isOn: $adult)
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Opciones de Manga")
            } }
            .task(id: connection.server) { await connect() }
            .task(id: signature) { await browse(next: false) }
            .onChange(of: adult) { _, _ in
                if !visibleSources.contains(where: { $0.id == selected }) { books = []; selected = visibleSources.first?.id ?? "" }
            }
            .refreshable { await connect() }
            .sheet(isPresented: $configuring) { MangaConnectionView(connection: connection) }
            .sheet(isPresented: $extensions, onDismiss: { Task { await connect() } }) { if let client { MangaExtensionsView(client: client, adult: adult) } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "cbz") ?? .zip, .zip, .folder]) { result in
                if case .success(let file) = result { Task { await importBook(file) } }
                else if case .failure = result { error = "No se pudo abrir el archivo elegido." }
            }
            .navigationDestination(item: $imported) { book in MangaDetailView(book: book, shelf: shelf, client: matchingClient(book)) }
    }
    private func matchingClient(_ book: MangaBook) -> SuwayomiClient? { book.server == connection.server?.id ? client : nil }
    private func grid(_ entries: [MangaBook]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
            ForEach(entries) { book in
                NavigationLink { MangaDetailView(book: book, shelf: shelf, client: matchingClient(book)) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        MangaImage(book: book, owner: shelf.owner, path: book.cover, client: matchingClient(book), maxPixels: 500).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(.rect(cornerRadius: 8))
                        Text(book.title).font(.caption.weight(.medium)).lineLimit(2)
                        if let record = shelf.record(book), let progress = record.progress[record.chapter] { Text(progress.completed ? "Leído" : "Página \(progress.page + 1)").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain).contextMenu {
                    Button("Quitar de esta biblioteca", role: .destructive) {
                        do { try shelf.remove(book) } catch { self.error = safeMessage(error) }
                    }
                    if book.server == nil { Button("Eliminar archivo", role: .destructive) { Task { do { try await MangaLocalStore.shared.remove(book, owner: shelf.owner); try shelf.remove(book) } catch { self.error = safeMessage(error) } } } }
                }
            }
        }.padding(.horizontal)
    }
    private func connect() async {
        generation = UUID(); client = nil; sources = []; books = []; serverLibrary = []; more = false
        guard let server = connection.server else { loading = false; return }
        let service = SuwayomiClient(server: server); client = service; loading = true; error = nil
        do {
            let loaded = try await service.sources(); try Task.checkCancellation()
            guard connection.server == server else { return }
            sources = loaded
            selected = visibleSources.first(where: { $0.id == selected })?.id ?? visibleSources.first(where: { $0.language == "es" })?.id ?? visibleSources.first?.id ?? ""
            if !selected.isEmpty { await browse(next: false) }
            do { let library = try await service.library(); guard connection.server == server else { return }; serverLibrary = library }
            catch is CancellationError { return }
            catch { if books.isEmpty { self.error = safeMessage(error) } }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
        if connection.server == server { loading = false }
    }
    private func browse(next: Bool) async {
        guard let client, !selected.isEmpty, visibleSources.contains(where: { $0.id == selected }) else { return }
        if next && loading { return }
        let token = UUID(); generation = token; loading = true; error = nil
        let source = selected, term = query.trimmingCharacters(in: .whitespacesAndNewlines), requested = next ? page + 1 : 1, useLatest = latest && sources.first(where: { $0.id == source })?.latest == true
        defer { if generation == token { loading = false } }
        do {
            if !next { try await Task.sleep(for: .milliseconds(350)) }
            let result = try await client.browse(source: source, latest: useLatest, query: term, page: requested)
            try Task.checkCancellation(); guard generation == token else { return }
            var seen = Set<String>()
            books = ((next ? books : []) + result.0).filter { seen.insert($0.id).inserted }; page = requested; more = result.1
        } catch is CancellationError { return }
        catch { if generation == token { self.error = safeMessage(error) } }
    }
    private func importBook(_ file: URL) async {
        guard shelf.ready else { error = "La biblioteca no está disponible. Los archivos guardados se conservan."; return }
        let access = file.startAccessingSecurityScopedResource(); defer { if access { file.stopAccessingSecurityScopedResource() } }
        do {
            let folder = try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            let book: MangaBook
            if folder { book = try await MangaLocalStore.shared.importFolder(file, owner: shelf.owner) }
            else { book = try await MangaLocalStore.shared.importArchive(file, owner: shelf.owner) }
            do { try shelf.save(MangaRecord(book: book)) }
            catch { try? await MangaLocalStore.shared.remove(book, owner: shelf.owner); throw error }
            screen = "shelf"; imported = book
        } catch { self.error = safeMessage(error) }
    }
}

struct MangaConnectionView: View {
    let connection: MangaConnection
    @Environment(\.dismiss) private var dismiss
    @State private var base = ""
    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Suwayomi") {
                    TextField("URL del servidor", text: $base).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("Usuario (opcional)", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    SecureField("Contraseña", text: $password).textContentType(.password)
                    Text("Usa el servidor que ya tienes configurado en Harbor. En la red local, permite el acceso cuando iOS lo solicite.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
                Section {
                    Button(busy ? "Conectando…" : "Comprobar y guardar") { Task { await save() } }.disabled(busy || !connection.ready)
                    if connection.server != nil { Button("Desconectar", role: .destructive) { do { try connection.save(nil); dismiss() } catch { self.error = safeMessage(error) } }.disabled(busy) }
                }
            }.navigationTitle("Conexión Manga").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() }.disabled(busy) } }
                .onAppear { if let server = connection.server { base = server.base; username = server.username; password = server.password } }
        }
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let server = try MangaServer.normalized(base, username: username, password: password)
            _ = try await SuwayomiClient(server: server).sources()
            try Task.checkCancellation(); try connection.save(server); dismiss()
        } catch { self.error = safeMessage(error) }
    }
}

private struct MangaExtensionsView: View {
    let client: SuwayomiClient
    let adult: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [MangaExtension] = []
    @State private var loading = false
    @State private var query = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.orange) }
                ForEach(entries.filter { (adult || !$0.adult) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.name).font(.headline)
                        Text("\(entry.language.uppercased()) · \(entry.version)\(entry.obsolete ? " · Obsoleta" : "")").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(entry.installed ? "Desinstalar" : "Instalar", role: entry.installed ? .destructive : nil) { change(entry, action: entry.installed ? "uninstall" : "install") }
                            if entry.update { Button("Actualizar") { change(entry, action: "update") } }
                        }.buttonStyle(.bordered).disabled(loading)
                    }.padding(.vertical, 6)
                }
                if loading { ProgressView() }
                if entries.isEmpty && !loading { Text("No hay extensiones disponibles en este servidor.") }
            }.navigationTitle("Extensiones Manga").searchable(text: $query).toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { dismiss() } } }.task { await load() }.refreshable { await load() }
        }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { entries = try await client.extensions() } catch { self.error = safeMessage(error) }
    }
    private func change(_ entry: MangaExtension, action: String) {
        loading = true; error = nil
        Task { do { try await client.changeExtension(entry, action: action); await load() } catch { self.error = safeMessage(error); loading = false } }
    }
}
