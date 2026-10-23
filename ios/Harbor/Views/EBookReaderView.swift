import SwiftUI
import AVFoundation
import Observation
import ImageIO
import CoreText

struct EBookReaderView: View {
    let book: EBook
    let shelf: EBookShelf
    var initialChapterID: String? = nil
    var initialPublication: EBookPublication? = nil
    @Environment(\.readingPlugins) private var reading
    @State private var publication: EBookPublication?
    @State private var readerProgram = EBookDetailProgram()
    @State private var readerVolumes: [EBookVolume] = []
    @State private var notes = EBookReaderNotes()
    @State private var chrome = EBookReaderChrome()
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var chapterOrder: [Int] = []
    @State private var blocks: [EBookBlock] = []
    @State private var originalBlocks: [EBookBlock] = []
    @State private var translation: EBookTranslation?
    @State private var showOriginal = true
    @State private var translationClient: EBookTranslationClient?
    @State private var translationTask: Task<Void, Never>?
    @State private var translationRequest = UUID()
    @State private var translating = false
    @State private var translationProgress = EBookTranslationProgress(percent: 0, etaMs: nil)
    @State private var translationFailure: String?
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
    @State private var narrator = EBookNarrator()
    @State private var narrationOptions = false
    @State private var narrationAfterSettings = false
    @State private var saveTask: Task<Void, Never>?
    @State private var chapterTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ebook.fontSize") private var fontSize = 19.0
    @AppStorage("ebook.lineHeight") private var lineHeight = 1.85
    @AppStorage("ebook.margin") private var margin = 22.0
    @AppStorage("ebook.background") private var background = "dark"
    @AppStorage("ebook.font") private var font = "literary"
    @AppStorage("ebook.direction") private var direction = "auto"
    @AppStorage("ebook.narrationVoice") private var narrationVoice = "en-US-AvaNeural"
    @AppStorage("ebook.deviceNarrationVoice") private var deviceNarrationVoice = ""
    @AppStorage("ebook.narrationProvider") private var narrationProvider = "edge"
    @AppStorage("ebook.narrationSpeed") private var narrationSpeed = 1.0
    @AppStorage("ebook.width") private var pageWidth = 768.0
    @AppStorage("ebook.brightness") private var brightness = 100.0
    @AppStorage("ebook.customFontID") private var customFontID = ""
    @State private var customGraphicFont: CGFont?
    @State private var customFontData: Data?
    @State private var fontError: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var paper: EBookPaper { EBookPaper(rawValue: background) ?? .dark }
    private var baseCanvas: Color { Color(cgColor: EBookPaper.color(paper.desk)) }
    private var baseInk: Color { Color(cgColor: EBookPaper.color(paper.ink)) }
    private var pageColor: Color { Color(cgColor: ReadingBrightness.color(EBookPaper.color(paper.page), percent: boundedBrightness)) }
    private var muted: Color { Color(cgColor: ReadingBrightness.color(EBookPaper.color(paper.muted), percent: boundedBrightness)) }
    private var canvas: Color { Color(cgColor: ReadingBrightness.color(UIColor(baseCanvas).cgColor, percent: boundedBrightness)) }
    private var ink: Color { Color(cgColor: ReadingBrightness.color(UIColor(baseInk).cgColor, percent: boundedBrightness)) }
    private var rtl: Bool { direction == "rtl" || (direction == "auto" && ["ar", "he", "fa", "ur"].contains(publication?.language?.components(separatedBy: "-").first ?? "")) }
    private var record: EBookRecord { shelf.record(book) ?? EBookRecord(book: book) }
    private var originalChapterTitle: String { publication.flatMap { $0.chapters.indices.contains(chapter) ? $0.chapters[chapter].title : nil } ?? book.title }
    private var displayChapterTitle: String { !showOriginal ? translation?.title ?? originalChapterTitle : originalChapterTitle }
    private var translationAction: String { translation == nil ? "Translate chapter" : showOriginal ? "Show translation" : "Show original language" }
    private var orderedChapters: [Int] { chapterOrder.isEmpty ? Array(publication?.chapters.indices ?? 0..<0) : chapterOrder }
    private var chapterPosition: Int { orderedChapters.firstIndex(of: chapter) ?? 0 }
    private var previousChapter: Int? { chapterPosition > 0 ? orderedChapters[chapterPosition - 1] : nil }
    private var nextChapter: Int? { orderedChapters.indices.contains(chapterPosition + 1) ? orderedChapters[chapterPosition + 1] : nil }
    private var boundedPageWidth: Double { pageWidth.isFinite ? min(1080, max(520, pageWidth)) : 768 }
    private var boundedBrightness: Double { ReadingBrightness.bounded(brightness) }
    private var boundedFontSize: Double { fontSize.isFinite ? min(36, max(14, fontSize)) : 19 }
    private var boundedLineHeight: Double { lineHeight.isFinite ? min(2.5, max(1.1, lineHeight)) : 1.85 }
    private var annotationSignature: String { shelf.owner + "|" + book.id + "|" + contentRevision.uuidString + "|" + String(notes.revision) }
    private var canAnnotate: Bool { notes.canSelect(revision: contentRevision) }
    private var chromeSuspended: Bool {
        loading || error != nil || settings || contents || bookmarks || passageSearch || narrationOptions || notes.route != nil || scenePhase != .active || voiceOver
    }
    private var readerFont: Font { readingFont(size: boundedFontSize) }
    private func readingFont(size: Double) -> Font {
        if font == "custom", let customGraphicFont { return Font(CTFontCreateWithGraphicsFont(customGraphicFont, size, nil, nil)) }
        return .custom(font == "classic" ? "Palatino-Roman" : font == "arabic" ? "Vazirmatn-Regular" : "Georgia", size: size)
    }
    private var printedReader: some View {
        return EBookPagedReaderView(book: book, owner: shelf.owner, chapterTitle: displayChapterTitle,
            firstChapter: chapterPosition == 0, blocks: blocks, revision: contentRevision,
            font: .init(face: font, data: font == "custom" ? customFontData : nil), fontIdentity: customFontID,
            fontSize: boundedFontSize, lineHeight: boundedLineHeight, paper: EBookPaper(rawValue: background) ?? .dark, rtl: rtl, showControls: chrome.visible, brightness: boundedBrightness, jump: passageJump,
            block: Binding(get: { settledBlock }, set: { settledBlock = $0; visible = $0 }))
            .id(contentRevision).environment(\.readingPlugins, reading)
    }
    private var chapterHeading: EBookReaderHeading? {
        guard publication != nil else { return nil }
        return EBookReaderHeading(book: book, owner: shelf.owner, title: displayChapterTitle,
            firstChapter: chapterPosition == 0, titleFont: readingFont(size: boundedFontSize * 1.85).weight(.semibold), muted: muted)
    }
    private var continuousReader: some View {
        EBookContinuousReaderView(blocks: blocks, spacing: boundedFontSize * max(0.5, boundedLineHeight - 0.85),
            pageWidth: boundedPageWidth, margin: margin, jump: passageJump,
            heading: chapterHeading, pageColor: pageColor,
            block: Binding(get: { settledBlock }, set: { settledBlock = $0; visible = $0 })) { block in
                Group {
                    if let image = block.image {
                        BookIllustration(data: image, label: block.text, brightness: boundedBrightness).accessibilityIdentifier("ebook-reader-image")
                    } else if let url = block.imageURL, let pluginID = book.pluginID {
                        RemoteBookIllustration(url: url, pluginID: pluginID, label: block.text, brightness: boundedBrightness).accessibilityIdentifier("ebook-reader-image")
                    } else {
                        passage(block)
                    }
                }
        }.id(contentRevision).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .foregroundStyle(ink)
    }
    private var readerSurface: some View {
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
                continuousReader
            }
            if chrome.visible, publication != nil {
                readerFooter.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(canvas)
            .modifier(EBookReaderChromeModifier(chrome: chrome, focus: focus, suspended: chromeSuspended))

    }
    private var readerFooter: some View {
                VStack(spacing: 8) {
                    Text(displayChapterTitle).font(.caption).lineLimit(1)
                    EBookNarrationBar(narrator: narrator, start: startNarration, options: { narrationOptions = true })
                    if translating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("≈\(translationProgress.percent)%").monospacedDigit()
                            if let eta = translationProgress.etaMs { Text(String(format: "%d:%02d", Int(eta / 60000), Int(eta / 1000) % 60)) }
                            else { Text(DesktopInterfaceText.value("Estimating…")) }
                        }.font(.caption).accessibilityIdentifier("ebook-translation-progress")
                    }
                    if let translationFailure { Text(translationFailure).font(.caption).foregroundStyle(.orange).lineLimit(2).accessibilityIdentifier("ebook-translation-error") }
                    HStack {
                        Button { if let previousChapter { select(previousChapter) } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 40) }.disabled(previousChapter == nil).accessibilityLabel("Capítulo anterior").accessibilityIdentifier("ebook-previous-section")
                        Spacer()
                        Text("\(chapterPosition + 1) / \(orderedChapters.count)").font(.caption.monospacedDigit())
                        Spacer()
                        Button { notes.select(block: settledBlock) } label: { Image(systemName: "highlighter").frame(width: 44, height: 44) }
                            .disabled(!canAnnotate).accessibilityLabel(DesktopInterfaceText.value("Notes & highlights")).accessibilityIdentifier("ebook-note-open-selection")
                        Button { if translation == nil { translateChapter(manual: true) } else { showOriginal.toggle(); applyTranslation() } } label: {
                            Image(systemName: "character.bubble").frame(width: 44, height: 44)
                        }.disabled(translating || originalBlocks.isEmpty).accessibilityLabel(DesktopInterfaceText.value(translationAction)).accessibilityIdentifier("ebook-translate-chapter")
                        Button { if let nextChapter { select(nextChapter) } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.disabled(nextChapter == nil).accessibilityLabel("Capítulo siguiente").accessibilityIdentifier("ebook-next-section")
                    }
                }.padding(.horizontal).background(canvas.opacity(0.92)).background(.ultraThinMaterial).foregroundStyle(ink)
    }
    private var readerMenu: some View {
                    Menu {
                        Button("Índice") { contents = true }.accessibilityIdentifier("ebook-reader-contents-action")
                        Button(DesktopInterfaceText.value("Search chapter")) { passageSearch = true }.accessibilityIdentifier("ebook-passage-search-action")
                        Button(DesktopInterfaceText.value("Bookmark current passage")) { saveBookmark() }.accessibilityIdentifier("ebook-bookmark-add-action")
                        Button(DesktopInterfaceText.value("Bookmarks")) { bookmarks = true }.accessibilityIdentifier("ebook-bookmarks-action")
                        Button(DesktopInterfaceText.value("Notes & highlights")) { notes.route = .list }.accessibilityIdentifier("ebook-notes-action")
                        Button(DesktopInterfaceText.value("Highlight")) { notes.select(block: settledBlock) }.disabled(!canAnnotate).accessibilityIdentifier("ebook-note-select-action")
                        Button(DesktopInterfaceText.value("Voice")) { narrationOptions = true }.accessibilityIdentifier("ebook-narration-menu")
                        Toggle(DesktopInterfaceText.value("Focus mode"), isOn: $focus).accessibilityIdentifier("ebook-focus-toggle")
                        Button(record.completed ? "Marcar como no leído" : "Marcar como leído") { var next = record; next.completed.toggle(); persist(next) }
                        Button("Opciones de lectura") { settings = true }.accessibilityIdentifier("ebook-reader-settings-action")
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Opciones de lectura").accessibilityIdentifier("ebook-reader-menu")
    }
    private var readerLifecycle: some View {
        readerSurface
            .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(canvas, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(paper == .light ? .light : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    readerMenu
                }
            }
            .task(id: book.pluginID == nil ? "local" : String(reading?.ready ?? false)) { await open() }
            .task(id: shelf.owner + "|" + book.id) { await notes.prepare(owner: shelf.owner, book: book.id) }
            .task(id: shelf.owner) { narrator.prepare(owner: shelf.owner) }
            .onChange(of: narrator.currentBlock) { _, target in
                guard let target, blocks.contains(where: { $0.id == target }) else { return }
                settledBlock = target; visible = target; passageJump = .init(block: target)
            }
            .sheet(isPresented: $narrationOptions) {
                EBookNarrationView(narrator: narrator, fallback: blocks.filter { $0.image == nil && $0.imageURL == nil }.prefix(2).map(\.text).joined(separator: " "),
                    voice: $narrationVoice, deviceVoice: $deviceNarrationVoice, provider: $narrationProvider, speed: $narrationSpeed)
            }

    }
    private var readerPersistence: some View {
        readerLifecycle
            .task(id: annotationSignature) {
                guard let publication, publication.chapters.indices.contains(chapter) else { return }
                let selected = publication.chapters[chapter]
                let label = selected.number.map { DesktopInterfaceText.value("Chapter {chapter}", variables: ["chapter": $0]) } ?? selected.title
                let volume = readerVolumes.first { $0.chapters.contains { $0["id"].string == selected.id } }?.label ?? DesktopInterfaceText.value("Chapters")
                await notes.update(blocks: blocks, revision: contentRevision, chapterID: selected.id, chapterLabel: label, volumeLabel: volume)
            }
            .modifier(EBookNotesPresentation(notes: notes, bookTitle: book.title, rtl: rtl) { note in jumpToNote(note) })
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
            .onDisappear { saveTask?.cancel(); chapterTask?.cancel(); translationTask?.cancel(); narrator.stop(); saveCurrentPosition() }

    }
    var body: some View {
        readerPersistence
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
            .sheet(isPresented: $settings, onDismiss: {
                if narrationAfterSettings { narrationAfterSettings = false; narrationOptions = true }
            }) {
                readerSettings
            }
    }
    private var readerSettings: some View {
                NavigationStack {
                    Form {
                        Section(DesktopInterfaceText.value("Reading mode")) {
                            Picker(DesktopInterfaceText.value("Reading mode"), selection: $readingMode) {
                                Text("Harbor").tag("harbor"); Text(DesktopInterfaceText.value("Book")).tag("book")
                            }.pickerStyle(.segmented).accessibilityIdentifier("ebook-reading-mode")
                        }
                        Section(DesktopInterfaceText.value("Translation")) {
                            NavigationLink { EBookTranslationSettingsView(owner: shelf.owner) } label: { Label(DesktopInterfaceText.value("DeepSeek chapter translation"), systemImage: "character.bubble") }
                                .accessibilityIdentifier("ebook-reader-translation-settings")
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
                            Picker("Fondo", selection: $background) { Text("Oscuro").tag("dark"); Text("Tenue").tag("dim"); Text("Claro").tag("light") }.accessibilityIdentifier("ebook-paper")
                            LabeledContent(DesktopInterfaceText.value("Brightness"), value: "\(Int(boundedBrightness)) %")
                            Slider(value: Binding(get: { boundedBrightness }, set: { brightness = $0 }), in: 55...120, step: 1).accessibilityIdentifier("ebook-brightness")
                                .accessibilityValue("\(Int(boundedBrightness)) %")
                            Toggle(DesktopInterfaceText.value("Focus mode"), isOn: $focus).accessibilityIdentifier("ebook-focus-setting")
                            Button(DesktopInterfaceText.value("Voice")) { narrationAfterSettings = true; settings = false }.accessibilityIdentifier("ebook-narration-settings")
                        }
                    }.accessibilityIdentifier("ebook-reader-settings-form")
                        .navigationTitle("Opciones de lectura").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { settings = false }.accessibilityIdentifier("ebook-reader-settings-done") } }
                }
    }
    private func startNarration() {
        narrator.prepare(owner: shelf.owner)
        narrator.start(blocks: blocks, block: settledBlock, voice: narrationProvider == "device" ? deviceNarrationVoice : narrationVoice, device: narrationProvider == "device", speed: narrationSpeed)
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
            resetTranslation(loaded)
            contentsVolume = volumes.first { $0.chapters.contains { $0["id"].string == publication.chapters[selected].id } }?.volume
            visible = loaded.contains(where: { $0.id == saved.block }) ? saved.block : loaded.first?.id
            settledBlock = visible ?? loaded.first?.id ?? 0; contentRevision = UUID()
            if shelf.record(book) == nil { try shelf.save(EBookRecord(book: book)) }
            if saved.bookmarks.contains(where: { $0.chapterID == nil && publication.chapters.indices.contains($0.chapter) }) {
                var next = record; next.bookmarks = EBookBookmarks.upgrading(next.bookmarks, in: publication, volumes: volumes); persist(next)
            }
            translateChapter(manual: false)
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
    private func select(_ selected: Int, block: Int = 0, passageLine: Int? = nil) {
        guard let publication, publication.chapters.indices.contains(selected), !loading else { return }
        saveTask?.cancel(); saveCurrentPosition(); narrator.stop(); translationTask?.cancel(); translationRequest = UUID(); translating = false; loading = true; error = nil
        chapterTask = Task {
            defer { loading = false }
            do {
                let loaded = try await loadBlocks(publication, selected)
                try Task.checkCancellation()
                let paragraphs = EBookSearchParagraph.make(loaded)
                let target = passageLine.flatMap { paragraphs.indices.contains($0) ? paragraphs[$0].block : nil } ?? block
                chapter = selected; blocks = loaded; visible = loaded.contains(where: { $0.id == target }) ? target : loaded.first?.id
                resetTranslation(loaded)
                contentsVolume = readerVolumes.first { $0.chapters.contains { $0["id"].string == publication.chapters[selected].id } }?.volume
                settledBlock = visible ?? loaded.first?.id ?? 0; contentRevision = UUID()
                saveCurrentPosition()
                translateChapter(manual: false)
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
    private func resetTranslation(_ loaded: [EBookBlock]) {
        translationTask?.cancel(); translationRequest = UUID(); originalBlocks = loaded
        translation = nil; showOriginal = true; translating = false; translationFailure = nil
        translationProgress = .init(percent: 0, etaMs: nil)
    }
    @ViewBuilder private func passage(_ block: EBookBlock) -> some View {
        Group {
            if let paint = notes.paint[block.id], !paint.isEmpty {
                EBookAnnotatedPassage(text: EBookPrintRules.paragraphs(block.text).joined(separator: "\n\n"), paint: paint,
                    font: annotationFont(heading: block.heading), ink: UIColor(ink), spacing: boundedFontSize * (boundedLineHeight - 1), rtl: rtl, brightness: boundedBrightness, semantic: notes.caption(for: paint)) { notes.edit($0) }
            } else { Text(block.text).font(block.heading ? readerFont.weight(.bold) : readerFont).lineSpacing(boundedFontSize * (boundedLineHeight - 1)).textSelection(.enabled).accessibilityIdentifier("ebook-reader-text") }
        }.background(narrator.currentBlock == block.id ? Color.accentColor.opacity(0.1) : Color.clear)
    }
    private func annotationFont(heading: Bool) -> CTFont {
        let selected: CTFont
        if font == "custom", let customGraphicFont { selected = CTFontCreateWithGraphicsFont(customGraphicFont, boundedFontSize, nil, nil) }
        else if font == "arabic" { selected = CTFontCreateWithName("Vazirmatn-Regular" as CFString, boundedFontSize, nil) }
        else {
            let descriptor = UIFont.systemFont(ofSize: boundedFontSize).fontDescriptor
            let face = font == "literary" ? descriptor.withDesign(.serif) ?? descriptor : descriptor
            let attributes = Dictionary(uniqueKeysWithValues: face.fontAttributes.map { ($0.key.rawValue, $0.value) })
            selected = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), boundedFontSize, nil)
        }
        return heading ? CTFontCreateCopyWithSymbolicTraits(selected, boundedFontSize, nil, .traitBold, .traitBold) ?? selected : selected
    }
    private func jumpToNote(_ note: EBookAnnotation) -> Bool {
        guard let publication, let selected = publication.chapters.firstIndex(where: { $0.id == note.chapterID }), let line = note.ranges.first?.line else { return false }
        if selected == chapter {
            let paragraphs = EBookSearchParagraph.make(blocks); guard paragraphs.indices.contains(line) else { return false }
            narrator.stop(); saveTask?.cancel(); settledBlock = paragraphs[line].block; visible = settledBlock
            passageJump = .init(block: settledBlock); saveCurrentPosition()
        } else { select(selected, passageLine: line) }
        return true
    }
    private func translateChapter(manual: Bool) {
        guard !translating, translation == nil, !originalBlocks.isEmpty else { return }
        let source = originalBlocks.filter { $0.image == nil && $0.imageURL == nil }.map(\.text).joined(separator: "\n\n")
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let request = UUID(), title = originalChapterTitle; translationRequest = request; translating = true; translationFailure = nil
        translationTask = Task {
            defer { if translationRequest == request { translating = false } }
            do {
                let settings = try EBookTranslationSettings.load(owner: shelf.owner)
                if translationClient == nil { translationClient = try EBookTranslationClient(owner: shelf.owner) }
                guard let translationClient else { throw EBookTranslationError.response }
                let result = try await translationClient.translate(source: source, title: title, settings: settings, manual: manual) { progress in
                    if translationRequest == request { translationProgress = progress }
                }
                try Task.checkCancellation(); guard translationRequest == request, result.text != source else { return }
                translation = result; showOriginal = false; applyTranslation()
            } catch is CancellationError { return }
            catch { if translationRequest == request { translationFailure = (error as? EBookTranslationError)?.errorDescription ?? DesktopInterfaceText.value("Translation failed") } }
        }
    }
    private func applyTranslation() {
        narrator.stop(); saveTask?.cancel()
        if showOriginal { blocks = originalBlocks }
        else if let translation {
            blocks = EBookTranslatedChapter.blocks(translation.text, original: originalBlocks)
        }
        if !blocks.contains(where: { $0.id == settledBlock }) { settledBlock = blocks.first?.id ?? 0 }
        visible = settledBlock; contentRevision = UUID(); saveCurrentPosition()
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
