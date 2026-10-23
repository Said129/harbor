import CoreGraphics
import Foundation

enum ReadingBrightness {
    static func bounded(_ percent: Double) -> Double { percent.isFinite ? min(120, max(55, percent)) : 100 }
    static func color(_ value: CGColor, percent: Double) -> CGColor {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let rgb = value.converted(to: space, intent: .defaultIntent, options: nil), let components = rgb.components, components.count == 4 else { return value }
        let factor = CGFloat(bounded(percent) / 100)
        return CGColor(colorSpace: space, components: components.prefix(3).map { min(1, max(0, $0 * factor)) } + [components[3]]) ?? value
    }
    /// The renderer's own RGBA canvas can be adjusted before it enters UIKit.
    static func apply(_ context: CGContext, percent: Double) throws {
        let factor = bounded(percent) / 100
        guard factor != 1 else { return }
        guard context.bitsPerComponent == 8, context.bitsPerPixel == 32,
              context.alphaInfo == .premultipliedLast, context.bitmapInfo.contains(.byteOrder32Big),
              let data = context.data else { throw HarborError(code: "ebook-page-layout") }
        let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
        for row in 0..<context.height {
            if row % 64 == 0 { try Task.checkCancellation() }
            for column in 0..<context.width {
                let offset = row * context.bytesPerRow + column * 4, alpha = Double(pixels[offset + 3])
                for channel in 0..<3 { pixels[offset + channel] = UInt8(min(alpha, Double(pixels[offset + channel]) * factor).rounded()) }
            }
        }
    }
}
