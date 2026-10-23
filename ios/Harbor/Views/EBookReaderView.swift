import SwiftUI
import AVFoundation
import Observation
import ImageIO
import CoreText

@MainActor @Observable
private final class BookNarrator: NSObject, AVSpeechSynthesizerDelegate {
    var speaking = false
    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    override init() { super.init(); synth.delegate = self }
    func read(_ text: String, language: String?, rate: Double) {
        synth.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language ?? "en-US")
        utterance.rate = Float(min(0.65, max(0.3, rate)))
        synth.speak(utterance); speaking = true
    }
    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { Task { @MainActor in self.speaking = false } }
}

struct EBookReaderView: View {
    let book: EBook
    let shelf: EBookShelf
    var initialChapterID: String? = nil
    var initialPublication: EBookPublication? = nil
    @Environment(\.readingPlugins) private var reading
    @State private var publication: EBookPublication?
    @State private var readerProgram = EBookDetailProgram()
    @State private var readerVolumes: [EBookVolume] = []
    @State private var chapterOrder: [Int] = []
    @State private var blocks: [EBookBlock] = []
    @State private var chapter = 0
    @State private var visible: Int?
    @State private var settledBlock = 0
    @State private var contentRevision = UUID()
    @State private var loading = false
    @State private var error: String?
    @State private var settings = false
    @State private var contents = false
    @State private var contentsVolume: String?
    @State private var bookmarks = false
    @State private var passageSearch = false
    @State private var passageJump: EBookReadingJump?
    @State private var passageQuery = ""
    @State private var revealFuturePassages = false
    @AppStorage("ebook.focusMode") private var focus = false
    @AppStorage("ebook.mode") private var readingMode = "harbor"
    @State private var narrator = BookNarrator()
    @State private var saveTask: Task<Void, Never>?
    @State private var chapterTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ebook.fontSize") private var fontSize = 19.0
    @AppStorage("ebook.lineHeight") private var lineHeight = 1.85
    @AppStorage("ebook.margin") private var margin = 22.0
    @AppStorage("ebook.background") private var background = "dark"
    @AppStorage("ebook.font") private var font = "literary"
    @AppStorage("ebook.direction") private var direction = "auto"
    @AppStorage("ebook.narrationRate") private var rate = 0.5
    @AppStorage("ebook.width") private var pageWidth = 768.0
    @AppStorage("ebook.brightness") private var brightness = 100.0
    @AppStorage("ebook.customFontID") private var customFontID = ""
    @State private var customGraphicFont: CGFont?
    @State private var customFontData: Data?
    @State private var fontError: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var baseCanvas: Color { background == "light" ? Color(.sRGB, red: 0.96, green: 0.94, blue: 0.88) : background == "dim" ? Color(.sRGB, red: 0.21, green: 0.19, blue: 0.17) : HarborTheme.background }
    private var baseInk: Color { background == "light" ? Color(.sRGB, red: 0.15, green: 0.13, blue: 0.11) : .white.opacity(0.88) }
    private var canvas: Color { Color(cgColor: ReadingBrightness.color(UIColor(baseCanvas).cgColor, percent: boundedBrightness)) }
    private var ink: Color { Color(cgColor: ReadingBrightness.color(UIColor(baseInk).cgColor, percent: boundedBrightness)) }
    private var rtl: Bool { direction == "rtl" || (direction == "auto" && ["ar", "he", "fa", "ur"].contains(publication?.language?.components(separatedBy: "-").first ?? "")) }
    private var record: EBookRecord { shelf.record(book) ?? EBookRecord(book: book) }
    private var orderedChapters: [Int] { chapterOrder.isEmpty ? Array(publication?.chapters.indices ?? 0..<0) : chapterOrder }
    private var chapterPosition: Int { orderedChapters.firstIndex(of: chapter) ?? 0 }
    private var previousChapter: Int? { chapterPosition > 0 ? orderedChapters[chapterPosition - 1] : nil }
    private var nextChapter: Int? { orderedChapters.indices.contains(chapterPosition + 1) ? orderedChapters[chapterPosition + 1] : nil }
    private var boundedPageWidth: Double { pageWidth.isFinite ? min(1080, max(520, pageWidth)) : 768 }
    private var boundedBrightness: Double { ReadingBrightness.bounded(brightness) }
    private var boundedFontSize: Double { fontSize.isFinite ? min(36, max(14, fontSize)) : 19 }
    private var boundedLineHeight: Double { lineHeight.isFinite ? min(2.5, max(1.1, lineHeight)) : 1.85 }
    private var readerFont: Font {
        if font == "custom", let customGraphicFont { return Font(CTFontCreateWithGraphicsFont(customGraphicFont, boundedFontSize, nil, nil)) }
        return font == "arabic" ? .custom("Vazirmatn-Regular", size: boundedFontSize) : .system(size: boundedFontSize, design: font == "literary" ? .serif : .default)
    }
    private var printedReader: some View {
        let chapterTitle = publication.flatMap { $0.chapters.indices.contains(chapter) ? $0.chapters[chapter].title : nil } ?? book.title
        return EBookPagedReaderView(book: book, owner: shelf.owner, chapterTitle: chapterTitle,
            firstChapter: chapter == 0, blocks: blocks, revision: contentRevision,
            font: .init(face: font, data: font == "custom" ? customFontData : nil), fontIdentity: customFontID,
            fontSize: boundedFontSize, lineHeight: boundedLineHeight, paper: EBookPaper(rawValue: background) ?? .dark, rtl: rtl, showControls: !focus, brightness: boundedBrightness, jump: passageJump,
            block: Binding(get: { settledBlock }, set: { settledBlock = $0; visible = $0 }))
            .id(contentRevision).environment(\.readingPlugins, reading)
    }
    var body: some View {
        VStack(spacing: 0) {
            if loading { ProgressView("Abriendo libro…").padding() }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding().accessibilityIdentifier("ebook-reader-error"); Button("Reintentar") { Task { await open() } } }
            if let fontError { Text(fontError).font(.caption).foregroundStyle(.secondary).padding().accessibilityIdentifier("ebook-font-error") }
            if font == "custom", !customFontID.isEmpty, customGraphicFont == nil, fontError == nil {
                ProgressView(DesktopInterfaceText.value("Loading font…")).font(.caption).padding().accessibilityIdentifier("ebook-font-loading")
            }
            if readingMode == "book" {
                printedReader
            } else {
                EBookContinuousReaderView(blocks: blocks, spacing: boundedFontSize * max(0.5, boundedLineHeight - 0.85),
                    pageWidth: boundedPageWidth, margin: margin, jump: passageJump,
                    block: Binding(get: { settledBlock }, set: { settledBlock = $0; visible = $0 })) { block in
                        Group {
                            if let image = block.image {
                                BookIllustration(data: image, label: block.text, brightness: boundedBrightness).accessibilityIdentifier("ebook-reader-image")
                            } else if let url = block.imageURL, let pluginID = book.pluginID {
                                RemoteBookIllustration(url: url, pluginID: pluginID, label: block.text, brightness: boundedBrightness).accessibilityIdentifier("ebook-reader-image")
                            } else {
                                Text(block.text).font(block.heading ? readerFont.weight(.bold) : readerFont).lineSpacing(boundedFontSize * (boundedLineHeight - 1)).textSelection(.enabled).accessibilityIdentifier("ebook-reader-text")
                            }
                        }
                }.id(contentRevision).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                    .foregroundStyle(ink)
            }
            if !focus, let publication {
                VStack(spacing: 8) {
                    Text(publication.chapters[chapter].title).font(.caption).lineLimit(1)
                    HStack {
                        Button { if let previousChapter { select(previousChapter) } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 40) }.disabled(previousChapter == nil).accessibilityLabel("Capítulo anterior").accessibilityIdentifier("ebook-previous-section")
                        Spacer()
                        Text("\(chapterPosition + 1) / \(orderedChapters.count)").font(.caption.monospacedDigit())
                        Spacer()
                        Button { if let nextChapter { select(nextChapter) } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(nextChapter == nil).accessibilityLabel("Capítulo siguiente").accessibilityIdentifier("ebook-next-section")
                    }
                }.padding(.horizontal).background(.thinMaterial).foregroundStyle(ink)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(canvas)
            .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Índice") { contents = true }.accessibilityIdentifier("ebook-reader-contents-action")
                        Button(DesktopInterfaceText.value("Search chapter")) { passageSearch = true }.accessibilityIdentifier("ebook-passage-search-action")
                        Button(DesktopInterfaceText.value("Bookmark current passage")) { saveBookmark() }.accessibilityIdentifier("ebook-bookmark-add-action")
                        Button(DesktopInterfaceText.value("Bookmarks")) { bookmarks = true }.accessibilityIdentifier("ebook-bookmarks-action")
                        Button(narrator.speaking ? "Detener narración" : "Leer en voz alta") {
                            if narrator.speaking { narrator.stop() }
                            else { narrator.read(blocks.filter { $0.id >= (visible ?? 0) && $0.image == nil }.map(\.text).joined(separator: "\n\n"), language: publication?.language ?? book.language, rate: rate) }
                        }
                        Button(focus ? "Mostrar controles" : "Modo de concentración") { focus.toggle() }
                        Button(record.completed ? "Marcar como no leído" : "Marcar como leído") { var next = record; next.completed.toggle(); persist(next) }
                        Button("Opciones de lectura") { settings = true }.accessibilityIdentifier("ebook-reader-settings-action")
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Opciones de lectura").accessibilityIdentifier("ebook-reader-menu")
                }
            }
            .task(id: book.pluginID == nil ? "local" : String(reading?.ready ?? false)) { await open() }
            .task(id: font + "|" + customFontID) {
                customGraphicFont = nil; customFontData = nil; fontError = nil
                guard font == "custom", !customFontID.isEmpty else { return }
                do {
                    let data = try await ReadingFontStore.shared.data(id: customFontID, owner: shelf.owner)
                    try Task.checkCancellation()
                    guard let provider = CGDataProvider(data: data as CFData), let graphic = CGFont(provider) else { throw HarborError(code: "reading-font-format") }
                    customGraphicFont = graphic; customFontData = data
                } catch { if !Task.isCancelled { fontError = DesktopInterfaceText.value("That file is not a valid font.") } }
            }
            .onChange(of: visible) { _, line in
                guard let line, !loading, scenePhase == .active, blocks.contains(where: { $0.id == line }) else { return }
                settledBlock = line
                saveTask?.cancel()
                let selectedChapter = chapter
                saveTask = Task {
                    do {
                        try await Task.sleep(for: .milliseconds(350))
                        guard chapter == selectedChapter, blocks.contains(where: { $0.id == line }) else { return }
                        persistPosition(chapter: selectedChapter, block: line)
                    } catch {}
                }
            }
            .onChange(of: readingMode) { _, _ in narrator.stop(); saveCurrentPosition() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { saveTask?.cancel(); saveCurrentPosition() } }
            .onDisappear { saveTask?.cancel(); chapterTask?.cancel(); narrator.stop(); saveCurrentPosition() }
            .sheet(isPresented: $contents) {
                if let publication { EBookReaderContentsView(publication: publication, volumes: readerVolumes, currentChapter: chapter, selectedVolume: $contentsVolume) { target in select(target) } }
            }
            .sheet(isPresented: $passageSearch) {
                EBookPassageSearchView(paragraphs: EBookSearchParagraph.make(blocks), currentBlock: settledBlock, query: $passageQuery, revealFuture: $revealFuturePassages) { target in
                    guard blocks.contains(where: { $0.id == target }) else { return }
                    narrator.stop(); saveTask?.cancel(); settledBlock = target; visible = target
                    passageJump = EBookReadingJump(block: target); saveCurrentPosition()
                }
            }
            .sheet(isPresented: $bookmarks) {
                if let publication {
                    EBookBookmarksView(items: record.bookmarks, publication: publication, volumes: readerVolumes) { bookmark, target in
                        if target == chapter {
                            guard blocks.contains(where: { $0.id == bookmark.block }) else { return }
                            narrator.stop(); saveTask?.cancel(); settledBlock = bookmark.block; visible = bookmark.block
                            passageJump = EBookReadingJump(block: bookmark.block); saveCurrentPosition()
                        } else { select(target, block: bookmark.block) }
                    } removed: { id in
                        var next = record; next.bookmarks.removeAll { $0.id == id }; persist(next)
                    }
                }
            }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        Section(DesktopInterfaceText.value("Reading mode")) {
                            Picker(DesktopInterfaceText.value("Reading mode"), selection: $readingMode) {
                                Text("Harbor").tag("harbor"); Text(DesktopInterfaceText.value("Book")).tag("book")
                            }.pickerStyle(.segmented).accessibilityIdentifier("ebook-reading-mode")
                        }
                        Section("Texto") {
                            Picker("Fuente", selection: $font) { Text("Literaria").tag("literary"); Text("Clásica").tag("classic"); Text("Árabe").tag("arabic"); if !customFontID.isEmpty { Text(DesktopInterfaceText.value("Custom font")).tag("custom") } }
                            NavigationLink { ReadingFontsView(owner: shelf.owner, font: $font, selectedID: $customFontID) } label: { Label(DesktopInterfaceText.value("Import font"), systemImage: "textformat") }
                                .accessibilityIdentifier("ebook-custom-fonts")
                            LabeledContent("Tamaño", value: "\(Int(boundedFontSize))"); Slider(value: Binding(get: { boundedFontSize }, set: { fontSize = $0 }), in: 14...36, step: 1)
                            LabeledContent("Interlineado", value: boundedLineHeight.formatted(.number.precision(.fractionLength(2)))); Slider(value: Binding(get: { boundedLineHeight }, set: { lineHeight = $0 }), in: 1.1...2.5, step: 0.05)
                            LabeledContent("Márgenes", value: "\(Int(margin))"); Slider(value: $margin, in: 12...48, step: 2)
                            if horizontalSizeClass == .regular {
                                LabeledContent(DesktopInterfaceText.value("Page width"), value: "\(Int(boundedPageWidth))")
                                Slider(value: Binding(get: { boundedPageWidth }, set: { pageWidth = $0 }), in: 520...1080, step: 20).accessibilityIdentifier("ebook-page-width")
                            }
                            Picker("Dirección", selection: $direction) { Text("Automática").tag("auto"); Text("Izquierda a derecha").tag("ltr"); Text("Derecha a izquierda").tag("rtl") }
                        }
                        Section("Lectura") {
                            Picker("Fondo", selection: $background) { Text("Oscuro").tag("dark"); Text("Tenue").tag("dim"); Text("Claro").tag("light") }
                            LabeledContent(DesktopInterfaceText.value("Brightness"), value: "\(Int(boundedBrightness)) %")
                            Slider(value: Binding(get: { boundedBrightness }, set: { brightness = $0 }), in: 55...120, step: 1).accessibilityIdentifier("ebook-brightness")
                                .accessibilityValue("\(Int(boundedBrightness)) %")
                            Toggle("Concentración", isOn: $focus)
                            LabeledContent("Velocidad de narración", value: rate.formatted(.number.precision(.fractionLength(2)))); Slider(value: $rate, in: 0.3...0.65, step: 0.05)
                        }
                    }.navigationTitle("Opciones de lectura").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { settings = false }.accessibilityIdentifier("ebook-reader-settings-done") } }
                }
            }
    }
    private func open() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let publication: EBookPublication
            if let initialPublication { publication = initialPublication }
            else if book.pluginID != nil {
                guard let reading else { throw HarborPluginRepositoryError("plugin-unavailable") }
                publication = try await reading.ebookPublication(book)
            } else { publication = try await EBookService.shared.open(book, owner: shelf.owner) }
            let saved = record
            let selected = try publication.startingChapter(requestedID: initialChapterID, resume: saved.chapter)
            let volumes = try await readerProgram.groups(publication.chapters)
            let known = Dictionary(publication.chapters.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            var seen = Set<Int>()
            let order = volumes.flatMap(\.chapters).compactMap { $0["id"].string.flatMap { known[$0] } }.filter { seen.insert($0).inserted }
            let loaded = try await loadBlocks(publication, selected)
            try Task.checkCancellation()
            self.publication = publication; readerVolumes = volumes; chapterOrder = order; chapter = selected; blocks = loaded
            contentsVolume = volumes.first { $0.chapters.contains { $0["id"].string == publication.chapters[selected].id } }?.volume
            visible = loaded.contains(where: { $0.id == saved.block }) ? saved.block : loaded.first?.id
            settledBlock = visible ?? loaded.first?.id ?? 0; contentRevision = UUID()
            if shelf.record(book) == nil { try shelf.save(EBookRecord(book: book)) }
            if saved.bookmarks.contains(where: { $0.chapterID == nil && publication.chapters.indices.contains($0.chapter) }) {
                var next = record; next.bookmarks = EBookBookmarks.upgrading(next.bookmarks, in: publication, volumes: volumes); persist(next)
            }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
    private func select(_ selected: Int, block: Int = 0) {
        guard let publication, publication.chapters.indices.contains(selected), !loading else { return }
        saveTask?.cancel(); saveCurrentPosition(); narrator.stop(); loading = true; error = nil
        chapterTask = Task {
            defer { loading = false }
            do {
                let loaded = try await loadBlocks(publication, selected)
                try Task.checkCancellation()
                chapter = selected; blocks = loaded; visible = loaded.contains(where: { $0.id == block }) ? block : loaded.first?.id
                contentsVolume = readerVolumes.first { $0.chapters.contains { $0["id"].string == publication.chapters[selected].id } }?.volume
                settledBlock = visible ?? loaded.first?.id ?? 0; contentRevision = UUID()
                saveCurrentPosition()
            } catch is CancellationError { return }
            catch { self.error = safeMessage(error) }
        }
    }
    private func saveCurrentPosition() {
        guard let publication, publication.chapters.indices.contains(chapter), let block = blocks.first(where: { $0.id == settledBlock }) ?? blocks.first else { return }
        persistPosition(chapter: chapter, block: block.id)
    }
    private func loadBlocks(_ publication: EBookPublication, _ chapter: Int) async throws -> [EBookBlock] {
        if book.pluginID != nil {
            guard let reading, publication.chapters.indices.contains(chapter) else { throw HarborPluginRepositoryError("plugin-unavailable") }
            return try await reading.ebookBlocks(book, chapter: publication.chapters[chapter])
        }
        return try await EBookService.shared.blocks(book, owner: shelf.owner, chapter: chapter)
    }
    private func persistPosition(chapter: Int, block: Int) {
        do { try shelf.savePosition(book, chapter: chapter, block: block) }
        catch { self.error = "No se pudo guardar tu posición. El progreso anterior se conserva." }
    }
    private func persist(_ record: EBookRecord) {
        do { var next = record; next.updated = Date(); try shelf.save(next) }
        catch { self.error = "No se pudo guardar tu posición. El progreso anterior se conserva." }
    }
    private func saveBookmark() {
        guard let publication, let bookmark = EBookBookmarks.make(chapter: chapter, block: settledBlock,
            paragraphs: EBookSearchParagraph.make(blocks), publication: publication, volumes: readerVolumes) else { return }
        var next = record; next.bookmarks = EBookBookmarks.adding(bookmark, to: next.bookmarks, in: publication); next.updated = Date()
        do { try shelf.save(next); bookmarks = true }
        catch { self.error = "No se pudo guardar tu marcador. Los marcadores anteriores se conservan." }
    }
}

struct RemoteBookIllustration: View {
    let url: String
    let pluginID: String
    let label: String
    var brightness: Double = 100
    @Environment(\.readingPlugins) private var reading
    @State private var data: Data?
    @State private var failed = false
    var body: some View {
        Group {
            if let data { BookIllustration(data: data, label: label, brightness: brightness) }
            else if failed { Text(label).font(.caption).foregroundStyle(.secondary) }
            else { ProgressView().frame(minHeight: 100) }
        }.task(id: url) {
            do {
                guard let reading else { return }
                let value = try await reading.image(url, pluginID: pluginID); try Task.checkCancellation(); data = value
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

struct BookIllustration: View {
    let data: Data
    let label: String
    var brightness: Double = 100
    private var image: UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(label)
                .colorEffect(ShaderLibrary.harborReadingBrightness(.float(Float(ReadingBrightness.bounded(brightness) / 100))), isEnabled: brightness != 100)
        }
        else { Text(label).font(.caption).foregroundStyle(.secondary) }
    }
}
