import PDFKit
import SwiftUI

struct BookReaderDestination: View {
    let book: EBook
    let shelf: EBookShelf
    var body: some View {
        if book.isPDF { PDFBookReaderView(book: book, shelf: shelf) }
        else { EBookReaderView(book: book, shelf: shelf) }
    }
}

// Construct off the main thread, then transfer exclusively to PDFView. After
// loading, this document is only accessed on the main actor.
private final class LoadedPDF: @unchecked Sendable {
    let document: PDFDocument
    init(url: URL) throws {
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else { throw HarborError(code: "ebook-format") }
        self.document = document
    }
}

private struct PDFBookReaderView: View {
    let book: EBook
    let shelf: EBookShelf
    @State private var loaded: LoadedPDF?
    @State private var error: String?
    @State private var page = 0
    @AppStorage("ebook.pdf.horizontal") private var horizontal = false
    var body: some View {
        Group {
            if let loaded {
                PDFBookSurface(document: loaded.document, initialPage: shelf.record(book)?.block ?? 0, horizontal: horizontal) { index in
                    page = index
                    do { try shelf.savePosition(book, chapter: 0, block: index) } catch { self.error = safeMessage(error) }
                }
            } else if let error { ContentUnavailableView("No se pudo abrir el libro", systemImage: "book.closed", description: Text(error)) }
            else { ProgressView("Abriendo libro…") }
        }.background(HarborTheme.background).navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack {
                    if let loaded { Text("\(page + 1) / \(loaded.document.pageCount)").font(.caption.monospacedDigit()).padding(8) }
                    if loaded != nil, let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Pasar páginas horizontalmente", isOn: $horizontal)
                        Button("Marcar como leído") {
                            var record = shelf.record(book) ?? EBookRecord(book: book); record.completed = true
                            do { try shelf.save(record) } catch { self.error = safeMessage(error) }
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Opciones de lectura")
                }
            }
            .task {
                do {
                    let url = try await EBookService.shared.pdfURL(book, owner: shelf.owner)
                    let document = try await Task.detached(priority: .userInitiated) { try LoadedPDF(url: url) }.value
                    try Task.checkCancellation(); page = min(max(0, shelf.record(book)?.block ?? 0), document.document.pageCount - 1); loaded = document
                } catch is CancellationError { return }
                catch { self.error = safeMessage(error) }
            }
    }
}

struct PDFBookSurface: UIViewRepresentable {
    let document: PDFDocument
    let initialPage: Int
    let horizontal: Bool
    let pageChanged: (Int) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(pageChanged) }
    func makeUIView(context: Context) -> PDFView {
        let view = ReadingPDFView(); view.autoScales = true; view.backgroundColor = .secondarySystemBackground
        view.document = document
        configure(view)
        view.pendingPage = document.page(at: min(max(0, initialPage), document.pageCount - 1))
        context.coordinator.view = view
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed), name: .PDFViewPageChanged, object: view)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { context.coordinator.pageChanged = pageChanged; configure(view) }
    private func configure(_ view: PDFView) {
        let direction: PDFDisplayDirection = horizontal ? .horizontal : .vertical
        let mode: PDFDisplayMode = .singlePageContinuous
        if view.displayDirection != direction { view.displayDirection = direction }
        if view.displayMode != mode { view.displayMode = mode }
    }
    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) { NotificationCenter.default.removeObserver(coordinator) }
    @MainActor final class Coordinator: NSObject {
        weak var view: PDFView?
        var pageChanged: (Int) -> Void
        init(_ pageChanged: @escaping (Int) -> Void) { self.pageChanged = pageChanged }
        @objc func changed() {
            guard let view, let page = view.currentPage, let document = view.document else { return }
            pageChanged(document.index(for: page))
        }
    }
}

private final class ReadingPDFView: PDFView {
    var pendingPage: PDFPage?
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let page = pendingPage else { return }
        pendingPage = nil
        go(to: page)
    }
}
