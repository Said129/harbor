import SwiftUI

struct MangaDetailView: View {
    let book: MangaBook
    let shelf: MangaShelf
    let client: SuwayomiClient?
    @State private var detail: MangaBook?
    @State private var chapters: [MangaChapter] = []
    @State private var selection: MangaChapter?
    @State private var loading = false
    @State private var reverse = false
    @State private var error: String?
    private var displayed: MangaBook { detail ?? book }
    private var resume: MangaChapter? { chapters.first(where: { $0.id == shelf.record(book)?.chapter }) ?? chapters.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    MangaImage(book: book, owner: shelf.owner, path: book.cover, client: client, maxPixels: 700).frame(width: 110, height: 165).clipShape(.rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 12) {
                        Text(displayed.title).font(.title2.bold())
                        if !displayed.author.isEmpty { Text(displayed.author).font(.subheadline).foregroundStyle(.secondary) }
                        if let resume { Button(shelf.record(book) == nil ? "Leer" : "Continuar leyendo") { selection = resume }.buttonStyle(.borderedProminent) }
                    }
                }
                if !displayed.description.isEmpty { Text(displayed.description).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                if let error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load() } } }
                HStack { Text("Capítulos").font(.headline); Spacer(); Button { reverse.toggle() } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("Cambiar orden de capítulos") }
                ForEach(reverse ? Array(chapters.reversed()) : chapters) { chapter in
                    Button { selection = chapter } label: {
                        HStack(spacing: 14) {
                            let progress = shelf.record(book)?.progress[chapter.id]
                            Image(systemName: progress?.completed == true || chapter.read ? "checkmark.circle.fill" : "book.pages")
                            VStack(alignment: .leading, spacing: 6) {
                                Text(chapter.title).font(.subheadline).multilineTextAlignment(.leading)
                                if let progress, !progress.completed { Text("Página \(progress.page + 1)").font(.caption).foregroundStyle(.secondary) }
                                else if chapter.pages > 0 { Text("\(chapter.pages) páginas").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }.padding(14).background(HarborTheme.surface, in: .rect(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                else if chapters.isEmpty { Text("No hay capítulos disponibles.").font(.caption).foregroundStyle(.secondary) }
            }.padding(16)
        }.background(HarborTheme.background).navigationTitle("Manga").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Guardar en esta biblioteca") { do { var record = shelf.record(book) ?? MangaRecord(book: displayed); record.book = displayed; try shelf.save(record) } catch { self.error = safeMessage(error) } }
                    if let client { Button("Añadir a biblioteca Suwayomi") { Task { do { try await client.setLibrary(book, enabled: true) } catch { self.error = safeMessage(error) } } }; Button("Quitar de biblioteca Suwayomi", role: .destructive) { Task { do { try await client.setLibrary(book, enabled: false) } catch { self.error = safeMessage(error) } } } }
                } label: { Image(systemName: "bookmark") }.accessibilityLabel("Biblioteca de Manga")
            } }
            .task { await load() }
            .navigationDestination(item: $selection) { chapter in MangaReaderView(book: displayed, initialChapter: chapter, chapters: chapters, shelf: shelf, client: client) }
    }
    private func load() async {
        loading = true; error = nil; defer { loading = false }
        do {
            if book.server == nil {
                chapters = try await MangaLocalStore.shared.chapters(book, owner: shelf.owner)
            } else {
                guard let client else { throw HarborError(code: "manga-connection") }
                do { detail = try await client.detail(book) }
                catch is CancellationError { return }
                catch { self.error = safeMessage(error) }
                chapters = try await client.chapters(book)
            }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}
