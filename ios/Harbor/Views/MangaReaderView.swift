import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct MangaReaderView: View {
    let book: MangaBook
    let chapters: [MangaChapter]
    let shelf: MangaShelf
    let client: SuwayomiClient?
    @State private var chapter: MangaChapter
    @State private var pages: [MangaPage] = []
    @State private var visible: Int? = 0
    @State private var spread = 0
    @State private var ratios: [Int: CGFloat] = [:]
    @State private var dimensions: [Int: CGSize] = [:]
    @State private var loading = false
    @State private var settings = false
    @State private var contents = false
    @State private var error: String?
    @State private var progressTask: Task<Void, Never>?
    @State private var export: URL?
    @State private var chapterEnded = false
    @State private var hasScrolled = false
    @AppStorage("manga.reader.mode") private var mode = "long"
    @AppStorage("manga.reader.fit") private var fit = "width"
    @AppStorage("manga.reader.background") private var background = "dark"
    @AppStorage("manga.reader.rtl") private var rtl = true
    @AppStorage("manga.reader.zoom") private var zoom = 1.0
    @AppStorage("manga.reader.autoNextChapter") private var autoNext = true
    @AppStorage("manga.reader.navPos") private var navPos = "stack-br"
    @AppStorage("manga.reader.doubleGap") private var doubleGap = 8.0
    @AppStorage("manga.reader.focusMode") private var focus = false
    @AppStorage("manga.reader.hideChapterEndHint") private var hideEndHint = false
    @AppStorage("manga.reader.enablePageDownload") private var pageDownload = false
    init(book: MangaBook, initialChapter: MangaChapter, chapters: [MangaChapter], shelf: MangaShelf, client: SuwayomiClient?) {
        self.book = book; self.chapters = chapters; self.shelf = shelf; self.client = client; _chapter = State(initialValue: initialChapter)
    }
    private var canvas: Color { background == "light" ? Color(.sRGB, red: 0.96, green: 0.96, blue: 0.96) : background == "gray" ? Color(.sRGB, red: 0.15, green: 0.15, blue: 0.15) : Color(.sRGB, red: 0.043, green: 0.043, blue: 0.051) }
    private var ink: Color { background == "light" ? .black : .white }
    private var index: Int { chapters.firstIndex(where: { $0.id == chapter.id }) ?? 0 }
    private var current: Int { max(0, min(visible ?? 0, pages.count - 1)) }
    private var double: Bool { mode == "double" }
    private var spreadCount: Int { double ? (pages.count + 1) / 2 : pages.count }
    var body: some View {
        VStack(spacing: 0) {
            if loading { ProgressView("Cargando páginas…").padding() }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(); Button("Reintentar") { Task { await load(chapter) } } }
            GeometryReader { geometry in
                reader(size: geometry.size)
                    .overlay(alignment: navPos == "stack-bl" ? .bottomLeading : .bottomTrailing) { if !focus && navPos.hasPrefix("stack") { VStack(spacing: 6) { previousButton; nextButton }.padding(12).background(.thinMaterial, in: .rect(cornerRadius: 12)).padding(12) } }
                    .overlay { if !focus && navPos == "sides" { HStack { previousButton; Spacer(); nextButton }.padding(8) } }
            }
            if chapterEnded && !hideEndHint && !focus { Text(index + 1 < chapters.count ? "Fin del capítulo · Siguiente para continuar" : "Fin del manga").font(.caption).padding(8) }
            if !focus { bottomBar }
        }.background(canvas).foregroundStyle(ink).navigationTitle(chapter.title).navigationBarTitleDisplayMode(.inline)
            .toolbar(focus ? .hidden : .visible, for: .navigationBar)
            .toolbar { ToolbarItemGroup(placement: .topBarTrailing) { Button { contents = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel("Capítulos"); Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Opciones del lector") } }
            .overlay(alignment: .topTrailing) { if focus { Button { focus = false } label: { Image(systemName: "eye").padding(12).background(.ultraThinMaterial, in: .circle) }.accessibilityLabel("Mostrar controles").padding(8) } }
            .task { await load(chapter) }
            .onChange(of: visible) { _, _ in scheduleProgress() }
            .onChange(of: spread) { _, value in if !loading { visible = min(pages.count - 1, value * (double ? 2 : 1)) } }
            .onChange(of: mode) { _, _ in spread = current / (double ? 2 : 1) }
            .onDisappear { progressTask?.cancel(); if !pages.isEmpty { persist(page: current, sync: true) }; if let export { try? FileManager.default.removeItem(at: export) } }
            .sheet(isPresented: $settings) { readerSettings }
            .sheet(isPresented: $contents) { chapterList }
    }
    @ViewBuilder private func reader(size: CGSize) -> some View {
        if !pages.isEmpty {
            if mode == "book" {
                MangaBookPager(pages: pages, selected: Binding(get: { current }, set: { visible = $0 }), rtl: rtl, canvas: canvas) { page in AnyView(pageView(page, width: size.width, height: size.height)) }
            } else if mode == "paged" || double {
                TabView(selection: $spread) {
                    ForEach(0..<spreadCount, id: \.self) { number in
                        if double {
                            let first = number * 2
                            HStack(spacing: doubleGap) {
                                pageView(pages[first], width: max(40, (size.width - doubleGap) / 2), height: size.height)
                                if first + 1 < pages.count { pageView(pages[first + 1], width: max(40, (size.width - doubleGap) / 2), height: size.height) }
                                else { Color.clear.frame(width: max(40, (size.width - doubleGap) / 2)) }
                            }.environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight).tag(number)
                        } else { pageView(pages[number], width: size.width, height: size.height).tag(number) }
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never)).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            } else if mode == "long-h" {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) { ForEach(pages) { page in pageView(page, width: size.width * zoom, height: size.height).frame(width: size.width * zoom, height: size.height).id(page.id) } }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned).scrollPosition(id: $visible).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(spacing: 0) {
                        ForEach(pages) { page in
                            let ratio = ratios[page.id] ?? 2.0 / 3.0
                            let width = max(40, (fit == "original" ? dimensions[page.id]?.width ?? size.width : fit == "height" ? size.height * ratio : size.width) * zoom)
                            MangaImage(book: book, owner: shelf.owner, path: page.path, client: client, onSize: { size in if size.height > 0 { ratios[page.id] = size.width / size.height; dimensions[page.id] = size } }).frame(width: width, height: width / ratio).id(page.id)
                        }
                        Color.clear.frame(height: 20).background { GeometryReader { proxy in Color.clear.preference(key: MangaEndOffset.self, value: proxy.frame(in: .named("manga-vertical")).minY) } }
                    }.scrollTargetLayout()
                }.coordinateSpace(name: "manga-vertical").scrollPosition(id: $visible, anchor: .top)
                    .simultaneousGesture(DragGesture().onChanged { _ in hasScrolled = true })
                    .onPreferenceChange(MangaEndOffset.self) { offset in
                        guard hasScrolled, !loading, autoNext, index + 1 < chapters.count, offset >= 0, offset < size.height else { return }
                        hasScrolled = false
                        Task { await load(chapters[index + 1], page: 0) }
                    }
            }
        }
    }
    private func pageView(_ page: MangaPage, width: CGFloat, height: CGFloat) -> some View {
        let ratio = ratios[page.id] ?? 2.0 / 3.0
        let displayWidth = (fit == "height" ? height * ratio : fit == "original" ? dimensions[page.id]?.width ?? width : width) * zoom
        return ScrollView([.horizontal, .vertical]) {
            MangaImage(book: book, owner: shelf.owner, path: page.path, client: client, onSize: { size in if size.height > 0 { ratios[page.id] = size.width / size.height; dimensions[page.id] = size } }).frame(width: max(40, displayWidth), height: max(40, displayWidth / ratio))
        }.frame(width: width, height: height).background(canvas).clipped()
    }
    private var previousButton: some View { Button { turn(-1) } label: { Image(systemName: rtl ? "chevron.right" : "chevron.left").frame(width: 40, height: 40) }.disabled(current == 0 && index == 0 || loading).accessibilityLabel("Página anterior") }
    private var nextButton: some View { Button { turn(1) } label: { Image(systemName: rtl ? "chevron.left" : "chevron.right").frame(width: 40, height: 40) }.disabled(current >= pages.count - 1 && index + 1 >= chapters.count || loading).accessibilityLabel("Página siguiente") }
    private var bottomBar: some View {
        VStack(spacing: 6) {
            HStack {
                if navPos == "bottom" { previousButton }
                Text("\(pages.isEmpty ? 0 : current + 1) / \(pages.count)").font(.caption.monospacedDigit())
                if !pages.isEmpty { Slider(value: Binding(get: { Double(current) }, set: { go(Int($0)) }), in: 0...Double(max(1, pages.count - 1)), step: 1).disabled(pages.count <= 1) }
                if navPos == "bottom" { nextButton }
                Button { focus = true } label: { Image(systemName: "eye.slash").frame(width: 40, height: 40) }.accessibilityLabel("Modo de concentración")
            }
            if pageDownload {
                HStack { Button("Guardar página") { Task { await exportPage() } }; if let export { ShareLink("Compartir página", item: export) } }.font(.caption)
            }
        }.padding(.horizontal, 12).padding(.vertical, 4).background(.thinMaterial)
    }
    private var readerSettings: some View {
        NavigationStack {
            Form {
                Section("Modo de lectura") {
                    Picker("Modo", selection: $mode) { Text("Tira vertical").tag("long"); Text("Tira horizontal").tag("long-h"); Text("Una página").tag("paged"); Text("Dos páginas").tag("double"); Text("Libro").tag("book") }
                    Picker("Ajuste", selection: $fit) { Text("Anchura").tag("width"); Text("Altura").tag("height"); Text("Original").tag("original") }
                    LabeledContent("Zoom", value: "\(Int(zoom * 100)) %"); Slider(value: $zoom, in: 0.5...3, step: 0.1)
                    Toggle("Derecha a izquierda", isOn: $rtl)
                    LabeledContent("Separación entre páginas", value: "\(Int(doubleGap))"); Slider(value: $doubleGap, in: 0...40, step: 2)
                }
                Section("Interfaz") {
                    Picker("Fondo", selection: $background) { Text("Oscuro").tag("dark"); Text("Gris").tag("gray"); Text("Claro").tag("light") }
                    Picker("Navegación", selection: $navPos) { Text("Abajo a la derecha").tag("stack-br"); Text("Abajo a la izquierda").tag("stack-bl"); Text("Laterales").tag("sides"); Text("Barra inferior").tag("bottom") }
                    Toggle("Modo de concentración", isOn: $focus)
                    Toggle("Ocultar aviso de fin", isOn: $hideEndHint)
                    Toggle("Continuar al siguiente capítulo", isOn: $autoNext)
                    Toggle("Guardar y compartir páginas", isOn: $pageDownload)
                }
            }.navigationTitle("Opciones del lector").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { settings = false } } }
        }
    }
    private var chapterList: some View {
        NavigationStack {
            List(chapters) { item in Button { contents = false; Task { await load(item) } } label: { HStack { Text(item.title); Spacer(); if item.id == chapter.id { Image(systemName: "checkmark") } } } }.navigationTitle("Capítulos").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { contents = false } } }
        }
    }
    private func load(_ selected: MangaChapter, page: Int? = nil) async {
        guard !loading else { return }
        progressTask?.cancel()
        if !pages.isEmpty { persist(page: current, sync: true) }
        loading = true; error = nil; chapterEnded = false; hasScrolled = false
        defer { loading = false }
        do {
            let loaded: [MangaPage]
            if book.server == nil { loaded = try await MangaLocalStore.shared.pages(book, owner: shelf.owner, chapter: selected.id) }
            else { guard let client else { throw HarborError(code: "manga-connection") }; loaded = try await client.pages(book, chapter: selected) }
            try Task.checkCancellation(); guard !loaded.isEmpty else { throw HarborError(code: "manga-pages") }
            let saved = shelf.record(book)?.progress[selected.id]
            chapter = selected; pages = loaded; ratios = [:]; dimensions = [:]
            let start = min(loaded.count - 1, max(0, page ?? saved?.page ?? selected.lastPage))
            visible = start; spread = start / (double ? 2 : 1)
            if shelf.record(book) == nil { try shelf.save(MangaRecord(book: book, chapter: selected.id)) }
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
    private func go(_ page: Int) {
        guard !loading, pages.indices.contains(page) else { return }
        visible = page; spread = page / (double ? 2 : 1)
    }
    private func turn(_ direction: Int) {
        let next = current + direction * (double ? 2 : 1)
        if next >= pages.count {
            chapterEnded = true; persist(page: pages.count - 1, sync: true)
            if autoNext && index + 1 < chapters.count { Task { await load(chapters[index + 1], page: 0) } }
        } else if next < 0 {
            if index > 0 { Task { await load(chapters[index - 1]) } }
        } else { go(next); chapterEnded = false }
    }
    private func scheduleProgress() {
        guard !loading, !pages.isEmpty else { return }
        progressTask?.cancel()
        let page = current
        chapterEnded = page == pages.count - 1
        progressTask = Task { do { try await Task.sleep(for: .milliseconds(650)); persist(page: page, sync: true) } catch {} }
    }
    private func persist(page: Int, sync: Bool) {
        guard !pages.isEmpty else { return }
        do {
            var record = shelf.record(book) ?? MangaRecord(book: book)
            let completed = record.progress[chapter.id]?.completed == true || chapter.read || page >= pages.count - 1
            record.chapter = chapter.id; record.progress[chapter.id] = MangaProgress(page: max(0, page), completed: completed); record.updated = Date()
            try shelf.save(record)
            if sync, let client, book.server != nil {
                let target = chapter
                Task { do { try await client.progress(book, chapter: target, page: page, completed: completed) } catch { self.error = "El progreso está guardado en este iPhone. Suwayomi no pudo sincronizarlo ahora." } }
            }
        } catch { self.error = "No se pudo guardar tu posición. El progreso anterior se conserva." }
    }
    private func exportPage() async {
        guard pages.indices.contains(current) else { return }
        do {
            let path = pages[current].path, data: Data
            if book.server == nil { data = try await MangaLocalStore.shared.data(book, owner: shelf.owner, path: path) }
            else { guard let client else { throw HarborError(code: "manga-connection") }; data = try await client.image(path) }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension else { throw HarborError(code: "manga-format") }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor-page-" + UUID().uuidString + "." + ext)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if let export { try? FileManager.default.removeItem(at: export) }; export = file
        } catch { self.error = safeMessage(error) }
    }
}

private struct MangaEndOffset: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}

/// Native UIKit page-curl transition replaces Desktop's JavaScript flipbook.
@MainActor private struct MangaBookPager: UIViewControllerRepresentable {
    let pages: [MangaPage]
    @Binding var selected: Int
    let rtl: Bool
    let canvas: Color
    let content: (MangaPage) -> AnyView
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let view = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal, options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)])
        view.dataSource = context.coordinator; view.delegate = context.coordinator
        view.view.backgroundColor = UIColor(canvas)
        if let leaf = context.coordinator.leaf(selected) { view.setViewControllers([leaf], direction: .forward, animated: false) }
        return view
    }
    func updateUIViewController(_ view: UIPageViewController, context: Context) {
        context.coordinator.parent = self; view.view.backgroundColor = UIColor(canvas)
        if (view.viewControllers?.first as? Leaf)?.index != selected, let leaf = context.coordinator.leaf(selected) { view.setViewControllers([leaf], direction: .forward, animated: false) }
    }
    private final class Leaf: UIHostingController<AnyView> {
        let index: Int
        init(index: Int, content: AnyView) { self.index = index; super.init(rootView: content) }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError("Unavailable") }
    }
    @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MangaBookPager
        init(_ parent: MangaBookPager) { self.parent = parent }
        fileprivate func leaf(_ index: Int) -> UIViewController? {
            guard parent.pages.indices.contains(index) else { return nil }
            let leaf = Leaf(index: index, content: parent.content(parent.pages[index])); leaf.view.backgroundColor = UIColor(parent.canvas); return leaf
        }
        func pageViewController(_ view: UIPageViewController, viewControllerBefore controller: UIViewController) -> UIViewController? { guard let leaf = controller as? Leaf else { return nil }; return self.leaf(leaf.index + (parent.rtl ? 1 : -1)) }
        func pageViewController(_ view: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? { guard let leaf = controller as? Leaf else { return nil }; return self.leaf(leaf.index + (parent.rtl ? -1 : 1)) }
        func pageViewController(_ view: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) { if completed, let leaf = view.viewControllers?.first as? Leaf { parent.selected = leaf.index } }
    }
}
