import Foundation
import CoreGraphics
import ImageIO

/// Bounded rasterization of user-selected documents, away from the UI actor.
enum ReadingArtwork {
    static func thumbnail(_ data: Data, maxPixels: Int = 600) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: min(2200, max(100, maxPixels))] as CFDictionary) else { throw HarborError(code: "ebook-format") }
        return try jpeg(image)
    }
    static func pdfPage(_ file: URL, page index: Int = 0, maxPixels: Int = 600) throws -> Data {
        guard let document = CGPDFDocument(file as CFURL), (!document.isEncrypted || document.isUnlocked), index >= 0, index < document.numberOfPages,
              let page = document.page(at: index + 1) else { throw HarborError(code: "ebook-format") }
        let bounds = page.getBoxRect(.cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw HarborError(code: "ebook-format") }
        let scale = CGFloat(min(2200, max(100, maxPixels))) / max(bounds.width, bounds.height)
        let width = max(1, Int((bounds.width * scale).rounded())), height = max(1, Int((bounds.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw HarborError(code: "ebook-format") }
        let rectangle = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rectangle)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: rectangle, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw HarborError(code: "ebook-format") }
        return try jpeg(image)
    }
    private static func jpeg(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw HarborError(code: "ebook-format") }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw HarborError(code: "ebook-format") }
        return data as Data
    }
}
