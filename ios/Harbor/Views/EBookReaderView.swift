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
    @State private var blocks: [EBookBlock] = []
    @State private var chapter = 0
    @State private var visible: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var settings = false
    @State private var contents = false
    @State private var bookmarks = false
    @AppStorage("ebook.focusMode") private var focus = false
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
    @State private var fontError: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var canvas: Color { background == "light" ? Color(.sRGB, red: 0.96, green: 0.94, blue: 0.88) : background == "dim" ? Color(.sRGB, red: 0.21, green: 0.19, blue: 0.17) : HarborTheme.background }
    private var ink: Color { background == "light" ? Color(.sRGB, red: 0.15, green: 0.13, blue: 0.11) : .white.opacity(0.88) }
    private var rtl: Bool { direction == "rtl" || (direction == "auto" && ["ar", "he", "fa", "ur"].contains(publication?.language?.components(separatedBy: "-").first ?? "")) }
    private var record: EBookRecord { shelf.record(book) ?? EBookRecord(book: book) }
    private var boundedPageWidth: Double { pageWidth.isFinite ? min(1080, max(520, pageWidth)) : 768 }
    private var boundedBrightness: Double { brightness.isFinite ? min(120, max(55, brightness)) : 100 }
    private var readerFont: Font {
        if font == "custom", let customGraphicFont { return Font(CTFontCreateWithGraphicsFont(customGraphicFont, fontSize, nil, nil)) }
        return font == "arabic" ? .custom("Vazirmatn-Regular", size: fontSize) : .system(size: fontSize, design: font == "literary" ? .serif : .default)
    }
    var body: some View {
        VStack(spacing: 0) {
            if loading { ProgressView("Abriendo libro…").padding() }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding().accessibilityIdentifier("ebook-reader-error"); Button("Reintentar") { Task { await open() } } }
            if let fontError { Text(fontError).font(.caption).foregroundStyle(.secondary).padding().accessibilityIdentifier("ebook-font-error") }
            if font == "custom", !customFontID.isEmpty, customGraphicFont == nil, fontError == nil {
                ProgressView(DesktopInterfaceText.value("Loading font…")).font(.caption).padding().accessibilityIdentifier("ebook-font-loading")
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: fontSize * max(0.5, lineHeight - 0.85)) {
                    ForEach(blocks) { block in
                        Group {
                            if let image = block.image {
                                BookIllustration(data: image, label: block.text).accessibilityIdentifier("ebook-reader-image")
                            } else if let url = block.imageURL, let pluginID = book.pluginID {
                                RemoteBookIllustration(url: url, pluginID: pluginID, label: block.text).accessibilityIdentifier("ebook-reader-image")
                            } else {
                                Text(block.text).font(block.heading ? readerFont.weight(.bold) : readerFont).lineSpacing(fontSize * (lineHeight - 1)).textSelection(.enabled).accessibilityIdentifier("ebook-reader-text")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).id(block.id)
                    }
                }.scrollTargetLayout().frame(maxWidth: boundedPageWidth).frame(maxWidth: .infinity).padding(.horizontal, margin).padding(.vertical, 24)
            }.scrollPosition(id: $visible, anchor: .top).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                .foregroundStyle(ink)
            if !focus, let publication {
                VStack(spacing: 8) {
                    Text(publication.chapters[chapter].title).font(.caption).lineLimit(1)
                    HStack {
                        Button { select(chapter - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 40) }.disabled(chapter <= 0).accessibilityLabel("Capítulo anterior")
                        Spacer()
                        Text("\(chapter + 1) / \(publication.chapters.count)").font(.caption.monospacedDigit())
                        Spacer()
                        Button { select(chapter + 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(chapter >= publication.chapters.count - 1).accessibilityLabel("Capítulo siguiente").accessibilityIdentifier("ebook-next-section")
                    }
                }.padding(.horizontal).background(.thinMaterial)
            }
        }.background(canvas)
            .colorEffect(ShaderLibrary.harborReadingBrightness(.float(Float(boundedBrightness / 100))), isEnabled: boundedBrightness != 100)
            .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Índice") { contents = true }
                        Button("Añadir marcador") { saveBookmark() }
                        Button("Marcadores") { bookmarks = true }
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
                customGraphicFont = nil; fontError = nil
                guard font == "custom", !customFontID.isEmpty else { return }
                do {
                    let data = try await ReadingFontStore.shared.data(id: customFontID, owner: shelf.owner)
                    try Task.checkCancellation()
                    guard let provider = CGDataProvider(data: data as CFData), let graphic = CGFont(provider) else { throw HarborError(code: "reading-font-format") }
                    customGraphicFont = graphic
                } catch { if !Task.isCancelled { fontError = DesktopInterfaceText.value("That file is not a valid font.") } }
            }
            .onChange(of: visible) { _, line in
                guard let line, !loading, scenePhase == .active, blocks.contains(where: { $0.id == line }) else { return }
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
            .onChange(of: scenePhase) { _, phase in if phase != .active { saveTask?.cancel(); saveCurrentPosition() } }
            .onDisappear { saveTask?.cancel(); chapterTask?.cancel(); narrator.stop(); saveCurrentPosition() }
            .sheet(isPresented: $contents) {
                NavigationStack { List { if let publication { ForEach(Array(publication.chapters.enumerated()), id: \.element.id) { index, item in Button(item.title) { contents = false; select(index) } } } }.navigationTitle("Índice").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { contents = false } } } }
            }
            .sheet(isPresented: $bookmarks) {
                NavigationStack {
                    List {
                        ForEach(record.bookmarks) { bookmark in
                            Button { bookmarks = false; select(bookmark.chapter, block: bookmark.block) } label: { VStack(alignment: .leading, spacing: 6) { Text(publication?.chapters.indices.contains(bookmark.chapter) == true ? publication!.chapters[bookmark.chapter].title : "Marcador").font(.caption).foregroundStyle(.secondary); Text(bookmark.preview).lineLimit(3) } }
                        }.onDelete { indices in var next = record; next.bookmarks.remove(atOffsets: indices); persist(next) }
                    }.navigationTitle("Marcadores").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { bookmarks = false } } }
                }
            }
            .sheet(isPresented: $settings) {
                NavigationStack {
                    Form {
                        Section("Texto") {
                            Picker("Fuente", selection: $font) { Text("Literaria").tag("literary"); Text("Clásica").tag("classic"); Text("Árabe").tag("arabic"); if !customFontID.isEmpty { Text(DesktopInterfaceText.value("Custom font")).tag("custom") } }
                            NavigationLink { ReadingFontsView(owner: shelf.owner, font: $font, selectedID: $customFontID) } label: { Label(DesktopInterfaceText.value("Import font"), systemImage: "textformat") }
                                .accessibilityIdentifier("ebook-custom-fonts")
                            LabeledContent("Tamaño", value: "\(Int(fontSize))"); Slider(value: $fontSize, in: 14...36, step: 1)
                            LabeledContent("Interlineado", value: lineHeight.formatted(.number.precision(.fractionLength(2)))); Slider(value: $lineHeight, in: 1.1...2.5, step: 0.05)
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
            let loaded = try await loadBlocks(publication, selected)
            try Task.checkCancellation()
            self.publication = publication; chapter = selected; blocks = loaded
            visible = loaded.contains(where: { $0.id == saved.block }) ? saved.block : loaded.first?.id
            if shelf.record(book) == nil { try shelf.save(EBookRecord(book: book)) }
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
                saveCurrentPosition()
            } catch is CancellationError { return }
            catch { self.error = safeMessage(error) }
        }
    }
    private func saveCurrentPosition() {
        guard let publication, publication.chapters.indices.contains(chapter), let block = blocks.first(where: { $0.id == visible }) ?? blocks.first else { return }
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
        guard let block = blocks.first(where: { $0.id == visible }) ?? blocks.first else { return }
        var next = record
        if !next.bookmarks.contains(where: { $0.chapter == chapter && $0.block == block.id }) { next.bookmarks.append(EBookBookmark(id: UUID(), chapter: chapter, block: block.id, preview: String(block.text.prefix(180)))); persist(next) }
    }
}

private struct RemoteBookIllustration: View {
    let url: String
    let pluginID: String
    let label: String
    @Environment(\.readingPlugins) private var reading
    @State private var data: Data?
    @State private var failed = false
    var body: some View {
        Group {
            if let data { BookIllustration(data: data, label: label) }
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

private struct BookIllustration: View {
    let data: Data
    let label: String
    private var image: UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    var body: some View {
        if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(label) }
        else { Text(label).font(.caption).foregroundStyle(.secondary) }
    }
}
