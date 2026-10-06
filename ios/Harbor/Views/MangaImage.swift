import SwiftUI
import ImageIO
import UIKit

private struct MangaBitmap: @unchecked Sendable { let image: UIImage; let size: CGSize }

struct MangaImage: View {
    let book: MangaBook
    let owner: String
    let path: String?
    let client: SuwayomiClient?
    var maxPixels = 2200
    var onSize: ((CGSize) -> Void)?
    @State private var image: UIImage?
    @State private var failed = false
    private var signature: String { [owner, book.id, path ?? "cover", String(maxPixels)].joined(separator: "|") }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit().accessibilityLabel(book.title) }
            else {
                Rectangle().fill(HarborTheme.surface).overlay {
                    if failed { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise").padding(20) }.accessibilityLabel("Reintentar imagen") }
                    else { ProgressView() }
                }
            }
        }.task(id: signature) { await load() }
    }
    private func load() async {
        failed = false; image = nil
        do {
            let data: Data
            if book.server == nil {
                let selected: String
                if let path { selected = path }
                else {
                    let pages = try await MangaLocalStore.shared.pages(book, owner: owner)
                    guard let first = pages.first(where: { ($0.path as NSString).lastPathComponent.lowercased().hasPrefix("cover.") }) ?? pages.first else { throw HarborError(code: "manga-format") }
                    selected = first.path
                }
                data = try await MangaLocalStore.shared.data(book, owner: owner, path: selected)
            } else {
                guard let client, let path else { throw HarborError(code: "manga-connection") }
                data = try await client.image(path)
            }
            let limit = maxPixels
            let bitmap = try await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: limit] as CFDictionary) else { throw HarborError(code: "manga-format") }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? Double(image.width)
                let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? Double(image.height)
                return MangaBitmap(image: UIImage(cgImage: image), size: CGSize(width: width, height: height))
            }.value
            try Task.checkCancellation(); image = bitmap.image; onSize?(bitmap.size)
        } catch is CancellationError { return }
        catch { failed = true }
    }
}
