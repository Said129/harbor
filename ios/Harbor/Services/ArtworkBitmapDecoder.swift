import Foundation
import UIKit
import ImageIO

/// The pixels are fully decoded before this immutable image crosses to UIKit.
struct DecodedArtworkBitmap: @unchecked Sendable { let image: UIImage }

enum ArtworkBitmapDecoder {
    static func decode(_ data: Data, maxPixels: Int) throws -> DecodedArtworkBitmap {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw HarborError(code: "invalid-artwork") }
        let limit: Int
        if maxPixels > 0 { limit = maxPixels }
        else {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            guard let width = properties?[kCGImagePropertyPixelWidth as String] as? NSNumber,
                  let height = properties?[kCGImagePropertyPixelHeight as String] as? NSNumber else { throw HarborError(code: "invalid-artwork") }
            limit = max(width.intValue, height.intValue)
        }
        guard limit > 0, let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
            [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
             kCGImageSourceThumbnailMaxPixelSize: limit, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw HarborError(code: "invalid-artwork") }
        try Task.checkCancellation()
        return DecodedArtworkBitmap(image: UIImage(cgImage: image))
    }
    static func thumbnail(_ data: Data, maxPixels: Int) async throws -> DecodedArtworkBitmap {
        let worker = Task.detached(priority: .utility) { try decode(data, maxPixels: maxPixels) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
