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
    @State private var query = ""
    @State private var error: String?
    private var displayed: MangaBook { detail ?? book }
    private var resume: MangaChapter? { chapters.first(where: { $0.id == shelf.record(book)?.chapter }) ?? chapters.first }
    private var hasReadingProgress: Bool { shelf.record(book)?.progress.isEmpty == false }
    private var visibleChapters: [MangaChapter] {
        let matches = query.isEmpty ? chapters : chapters.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return reverse ? Array(matches.reversed()) : matches
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                if !displayed.description.isEmpty {
                    Text(displayed.description).font(HarborTheme.font(15)).lineSpacing(5).foregroundStyle(HarborTheme.ink.opacity(0.7)).textSelection(.enabled).padding(.horizontal, 20)
                }
                if let error {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange)
                        Button("Reintentar") { Task { await load() } }.buttonStyle(HarborAccountButtonStyle())
                    }.padding(.horizontal, 20)
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Capítulos").font(HarborTheme.font(21, weight: .semibold))
                        if !chapters.isEmpty { Text("\(chapters.count)").font(HarborTheme.font(12)).foregroundStyle(HarborTheme.ink.opacity(0.5)) }
                        Spacer()
                        Button { reverse.toggle() } label: { glyph("desktop-arrow-up-down", size: 18).frame(width: 44, height: 44).background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12)) }
                            .buttonStyle(.plain).accessibilityLabel("Cambiar orden de capítulos").accessibilityValue(reverse ? "Más recientes primero" : "Orden de lectura")
                    }
                    HarborSearchField(prompt: "Buscar capítulos…", text: $query)
                    LazyVStack(spacing: 10) { ForEach(visibleChapters) { chapterRow($0) } }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    else if visibleChapters.isEmpty { Text(query.isEmpty ? "No hay capítulos disponibles." : "No hay capítulos que coincidan con tu búsqueda.").font(HarborTheme.font(13)).foregroundStyle(HarborTheme.ink.opacity(0.6)).padding(.vertical, 14) }
                }
                .padding(.horizontal, 20)
            }.padding(.bottom, 24)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Guardar en esta biblioteca") { saveBook() }
                    if let client { Button("Añadir a biblioteca Suwayomi") { Task { do { try await client.setLibrary(book, enabled: true) } catch { self.error = safeMessage(error) } } }; Button("Quitar de biblioteca Suwayomi", role: .destructive) { Task { do { try await client.setLibrary(book, enabled: false) } catch { self.error = safeMessage(error) } } } }
                } label: { glyph("desktop-bookmark", size: 19).frame(width: 44, height: 44) }.accessibilityLabel("Biblioteca de Manga")
            } }
            .task { await load() }
            .navigationDestination(item: $selection) { chapter in MangaReaderView(book: displayed, initialChapter: chapter, chapters: chapters, shelf: shelf, client: client) }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                MangaImage(book: displayed, owner: shelf.owner, path: displayed.cover, client: client, maxPixels: 700)
                    .frame(width: 116, height: 174).clipShape(.rect(cornerRadius: 16)).shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                VStack(alignment: .leading, spacing: 12) {
                    Text(displayed.title).font(.custom("QRAmesBeta-Regular", size: 28)).foregroundStyle(.white).accessibilityIdentifier("manga-detail-title")
                    if !displayed.author.isEmpty { Text(displayed.author).font(HarborTheme.font(13)).foregroundStyle(.white.opacity(0.7)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    if let resume {
                        Button { selection = resume } label: {
                            HStack(spacing: 8) { glyph("desktop-book-open", size: 18); Text(hasReadingProgress ? "Continuar leyendo" : "Leer ahora").font(HarborTheme.font(14, weight: .semibold)) }
                                .padding(.horizontal, 20).frame(minHeight: 48).foregroundStyle(.black).background(.white, in: .capsule)
                        }.buttonStyle(.plain).accessibilityIdentifier("manga-detail-read")
                    }
                    Button { saveBook() } label: {
                        HStack(spacing: 8) { glyph("desktop-bookmark", size: 17); Text(shelf.record(book) == nil ? "Guardar en biblioteca" : "En biblioteca").font(HarborTheme.font(13, weight: .semibold)) }
                            .padding(.horizontal, 16).frame(minHeight: 48).foregroundStyle(.white).background(.white.opacity(0.1), in: .capsule)
                            .overlay { Capsule().stroke(.white.opacity(0.12), lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityIdentifier("manga-detail-library")
                }
            }.scrollIndicators(.hidden)
        }.padding(20).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GeometryReader { frame in
                    Image("manga-hero-background").resizable().scaledToFill().frame(width: frame.size.width, height: frame.size.height).clipped()
                        .overlay(.black.opacity(0.65)).overlay { LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom) }
                }.accessibilityHidden(true)
            }
    }
    private func chapterRow(_ chapter: MangaChapter) -> some View {
        let progress = shelf.record(book)?.progress[chapter.id]
        let completed = progress?.completed == true || chapter.read
        return Button { selection = chapter } label: {
            HStack(spacing: 14) {
                glyph(completed ? "music-check" : "desktop-book-open", size: 19).foregroundStyle(completed ? HarborTheme.accent : HarborTheme.ink.opacity(0.5))
                VStack(alignment: .leading, spacing: 7) {
                    Text(chapter.title).font(HarborTheme.font(14, weight: .medium)).multilineTextAlignment(.leading)
                    if let progress, !progress.completed { Text("Página \(progress.page + 1)").font(HarborTheme.font(12)).foregroundStyle(HarborTheme.accent) }
                    else if chapter.pages > 0 { Text("\(chapter.pages) páginas").font(HarborTheme.font(12)).foregroundStyle(HarborTheme.ink.opacity(0.5)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                glyph("desktop-chevron-right", size: 16).foregroundStyle(HarborTheme.ink.opacity(0.4))
            }.padding(16).frame(minHeight: 64).background(HarborTheme.surface.opacity(0.65), in: .rect(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(HarborTheme.ink.opacity(0.07), lineWidth: 1) }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func glyph(_ name: String, size: CGFloat) -> some View { Image(name).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true) }
    private func saveBook() {
        do { var record = shelf.record(book) ?? MangaRecord(book: displayed); record.book = displayed; try shelf.save(record) }
        catch { self.error = safeMessage(error) }
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
