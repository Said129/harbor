import SwiftUI
import UIKit

struct EBookPagedReaderView: View {
    let book: EBook
    let owner: String
    let chapterTitle: String
    let firstChapter: Bool
    let blocks: [EBookBlock]
    let revision: UUID
    let font: EBookPrintFont
    let fontIdentity: String
    let fontSize: Double
    let lineHeight: Double
    let paper: EBookPaper
    let rtl: Bool
    let showControls: Bool
    @Binding var block: Int
    @Environment(\.readingPlugins) private var reading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var document: EBookPrintedDocument?
    @State private var page = 0
    @State private var preparing = false
    @State private var failure = false
    @State private var retry = UUID()
    @State private var turning = false
    private var images: [EBookBlock] { blocks.filter { $0.image != nil || $0.imageURL != nil } }
    private var hasCover: Bool { firstChapter && (coverBook.cover != nil || book.id.hasPrefix("local:")) }
    private var coverCount: Int { hasCover ? 1 : 0 }
    private var count: Int { coverCount + (document?.layout.pages.count ?? 0) + images.count }
    private var signature: String { [revision.uuidString, fontIdentity, font.face, String(font.data != nil), String(fontSize), String(lineHeight), paper.rawValue, String(rtl), retry.uuidString].joined(separator: "|") }
    private var desk: Color { Color(cgColor: EBookPaper.color(paper.desk)) }
    private var coverBook: EBook {
        var value = book
        if let internalCover = book.metadata?["internalCover"].string { value.cover = internalCover }
        return value
    }
    var body: some View {
        GeometryReader { geometry in
            let spread = !reduceMotion && geometry.size.width > 750 && geometry.size.width > geometry.size.height * 1.1
            VStack(spacing: 0) {
                ZStack {
                    if let document, count > 0 {
                        ReadingPageCurl(count: count, rtl: rtl, spread: spread, reduceMotion: reduceMotion, canvas: desk, selected: $page, turning: $turning) { index in
                            AnyView(leaf(index, document: document).environment(\.readingPlugins, reading))
                        }.id(document.id + String(spread) + String(reduceMotion))
                    }
                    if preparing { ProgressView(DesktopInterfaceText.value("Preparing book…")).padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) }
                    if failure {
                        VStack(spacing: 16) {
                            Text("No se pudieron preparar las páginas de este libro.")
                            Button(DesktopInterfaceText.value("Retry")) { retry = UUID() }
                        }.padding()
                    } else if document != nil && count == 0 { Text(DesktopInterfaceText.value("No pages available")) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if count > 0 && showControls {
                    HStack {
                        Button { move(-1, spread: spread) } label: { Image(systemName: rtl ? "chevron.right" : "chevron.left").frame(width: 44, height: 44) }
                            .disabled(page <= 0 || turning).accessibilityLabel(DesktopInterfaceText.value("Previous page")).accessibilityIdentifier("ebook-print-previous")
                        Spacer()
                        Text("\(page + 1) / \(count)").font(.caption.monospacedDigit()).accessibilityIdentifier("ebook-print-position")
                        Spacer()
                        Button { move(1, spread: spread) } label: { Image(systemName: rtl ? "chevron.left" : "chevron.right").frame(width: 44, height: 44) }
                            .disabled(page >= count - (spread ? 2 : 1) || turning).accessibilityLabel(DesktopInterfaceText.value("Next page")).accessibilityIdentifier("ebook-print-next")
                    }.padding(.horizontal, 12).foregroundStyle(Color(cgColor: EBookPaper.color(paper.ink)))
                }
            }.background(desk)
        }
        .task(id: signature) {
            preparing = true; failure = false
            let expected = signature, target = block
            defer { if signature == expected { preparing = false } }
            do {
                let next = try await EBookPageRenderer.shared.prepare(blocks: blocks, font: font, fontSize: fontSize, lineHeight: lineHeight, paper: paper, rtl: rtl, title: chapterTitle, owner: owner)
                try Task.checkCancellation(); guard signature == expected else { return }
                let targetPage = images.firstIndex(where: { $0.id == target }).map { coverCount + next.layout.pages.count + $0 } ?? coverCount + next.resumePage(block: target)
                page = min(max(0, targetPage), max(0, coverCount + next.layout.pages.count + images.count - 1)); document = next
            } catch { if !Task.isCancelled && signature == expected { failure = true } }
        }
        .onChange(of: page) { _, value in
            guard let document, !preparing else { return }
            let printed = value - coverCount
            if printed < 0 { block = document.blockIDs.first ?? blocks.first?.id ?? 0 }
            else if document.layout.pages.indices.contains(printed) { block = document.block(at: printed) }
            else { let image = printed - document.layout.pages.count; if images.indices.contains(image) { block = images[image].id } }
        }
    }
    private func move(_ delta: Int, spread: Bool) {
        let step = spread ? 2 : 1
        var next = min(count - 1, max(0, page + delta * step))
        if spread { next -= next % 2 }; page = next
    }
    @ViewBuilder private func leaf(_ index: Int, document: EBookPrintedDocument) -> some View {
        if hasCover && index == 0 {
            EBookCover(book: coverBook, owner: owner).padding(8).frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityLabel(book.title)
        } else {
            let printed = index - coverCount
            if document.layout.pages.indices.contains(printed) { PrintedBookPage(document: document, index: printed) }
            else {
                let image = printed - document.layout.pages.count
                if images.indices.contains(image) {
                    let item = images[image]
                    if let data = item.image { BookIllustration(data: data, label: item.text).padding(8) }
                    else if let url = item.imageURL, let pluginID = book.pluginID { RemoteBookIllustration(url: url, pluginID: pluginID, label: item.text).padding(8) }
                }
            }
        }
    }
}

private struct PrintedBookPage: View {
    let document: EBookPrintedDocument
    let index: Int
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { ReadingPageZoom(image: image, label: document.layout.pages[index].map(\.text).joined(separator: " ")) }
            else if failed { Text("No se pudo dibujar esta página.") }
            else { ProgressView() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: document.id + String(index)) {
                do { let data = try await EBookPageRenderer.shared.page(document, index: index); try Task.checkCancellation(); image = UIImage(data: data) }
                catch { if !Task.isCancelled { failed = true } }
            }
    }
}

private struct ReadingPageZoom: UIViewRepresentable {
    let image: UIImage
    let label: String
    func makeUIView(context: Context) -> Canvas { Canvas() }
    func updateUIView(_ view: Canvas, context: Context) {
        if view.art.image !== image { view.setZoomScale(1, animated: false); view.art.image = image; view.setNeedsLayout() }
        view.isAccessibilityElement = true; view.accessibilityIdentifier = "ebook-print-page"
        view.accessibilityLabel = label; view.accessibilityValue = "\(Int((view.zoomScale * 100).rounded())) %"
    }
    final class Canvas: UIScrollView, UIScrollViewDelegate {
        let art = UIImageView()
        override init(frame: CGRect) {
            super.init(frame: frame); delegate = self; minimumZoomScale = 1; maximumZoomScale = 4
            showsHorizontalScrollIndicator = false; showsVerticalScrollIndicator = false; backgroundColor = .clear
            art.contentMode = .scaleAspectFit; addSubview(art); panGestureRecognizer.isEnabled = false
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoomPage)); doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
        }
        required init?(coder: NSCoder) { fatalError("Unavailable") }
        override func layoutSubviews() { super.layoutSubviews(); if zoomScale == 1 { art.frame = bounds; contentSize = bounds.size } }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { art }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            panGestureRecognizer.isEnabled = zoomScale > 1.01
            accessibilityValue = "\(Int((zoomScale * 100).rounded())) %"
        }
        @objc private func zoomPage() { setZoomScale(zoomScale > 1.01 ? 1 : 2, animated: !UIAccessibility.isReduceMotionEnabled) }
    }
}

private struct ReadingPageCurl: UIViewControllerRepresentable {
    let count: Int
    let rtl: Bool
    let spread: Bool
    let reduceMotion: Bool
    let canvas: Color
    @Binding var selected: Int
    @Binding var turning: Bool
    let content: (Int) -> AnyView
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
        let spine: UIPageViewController.SpineLocation = spread ? .mid : .min
        let view = UIPageViewController(transitionStyle: reduceMotion ? .scroll : .pageCurl, navigationOrientation: .horizontal, options: reduceMotion ? nil : [.spineLocation: NSNumber(value: spine.rawValue)])
        view.isDoubleSided = !reduceMotion && spread; view.dataSource = context.coordinator; view.delegate = context.coordinator
        view.view.backgroundColor = UIColor(canvas)
        view.setViewControllers(context.coordinator.controllers(selected), direction: .forward, animated: false)
        return view
    }
    func updateUIViewController(_ view: UIPageViewController, context: Context) { context.coordinator.parent = self; context.coordinator.show(view) }
    private final class Leaf: UIHostingController<AnyView> {
        let index: Int
        init(_ index: Int, _ content: AnyView) { self.index = index; super.init(rootView: content) }
        @MainActor required dynamic init?(coder: NSCoder) { fatalError("Unavailable") }
    }
    @MainActor final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReadingPageCurl
        private var animating = false
        init(_ parent: ReadingPageCurl) { self.parent = parent }
        private func anchor(_ index: Int) -> Int { parent.spread && !parent.reduceMotion ? index - index % 2 : index }
        fileprivate func leaf(_ index: Int) -> UIViewController? {
            guard index >= 0, index < parent.count || (index == parent.count && parent.spread && !parent.reduceMotion && index % 2 == 1) else { return nil }
            let content = index < parent.count ? parent.content(index) : AnyView(parent.canvas)
            let view = Leaf(index, content); view.view.backgroundColor = UIColor(parent.canvas); return view
        }
        fileprivate func controllers(_ index: Int) -> [UIViewController] {
            let first = anchor(index)
            guard let view = leaf(first) else { return [] }
            if parent.spread && !parent.reduceMotion, let next = leaf(first + 1) { return parent.rtl ? [next, view] : [view, next] }
            return [view]
        }
        fileprivate func show(_ view: UIPageViewController) {
            guard !animating else { return }
            let current = view.viewControllers?.compactMap { ($0 as? Leaf)?.index }.min() ?? 0
            let target = anchor(parent.selected)
            guard current != target else {
                if parent.selected != target { Task { @MainActor in self.parent.selected = target } }
                return
            }
            animating = true
            Task { @MainActor in self.parent.turning = true }
            let forward = parent.rtl ? target < current : target > current
            view.setViewControllers(controllers(target), direction: forward ? .forward : .reverse, animated: !parent.reduceMotion) { [weak self, weak view] _ in
                Task { @MainActor [weak self, weak view] in
                    guard let self else { return }; self.animating = false; self.parent.turning = false
                    if let view { self.show(view) }
                }
            }
        }
        func pageViewController(_ view: UIPageViewController, viewControllerBefore controller: UIViewController) -> UIViewController? { guard let leaf = controller as? Leaf else { return nil }; return self.leaf(leaf.index + (parent.rtl ? 1 : -1)) }
        func pageViewController(_ view: UIPageViewController, viewControllerAfter controller: UIViewController) -> UIViewController? { guard let leaf = controller as? Leaf else { return nil }; return self.leaf(leaf.index + (parent.rtl ? -1 : 1)) }
        func pageViewController(_ view: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { animating = true; parent.turning = true }
        func pageViewController(_ view: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            animating = false; parent.turning = false
            if completed, let index = view.viewControllers?.compactMap({ ($0 as? Leaf)?.index }).min(), index < parent.count { parent.selected = index }
        }
    }
}
