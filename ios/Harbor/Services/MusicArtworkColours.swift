import CryptoKit
import Foundation
import JavaScriptCore
import UIKit

/// Original, bounded pure Desktop calculations; no network or credentials are
/// exposed to JavaScriptCore. Pixel decoding and analysis stay off the UI actor.
actor MusicArtworkColours {
    static let shared = MusicArtworkColours()
    private final class Entry: NSObject {
        let value: MusicArtworkPalette?
        init(_ value: MusicArtworkPalette?) { self.value = value; super.init() }
    }
    private let cache = NSCache<NSString, Entry>()
    private var context: JSContext?
    init() { cache.countLimit = 128 }

    private func prepare() throws -> JSContext {
        if let context { return context }
        guard let file = Bundle.main.url(forResource: "MusicArtworkAssets", withExtension: "json"),
              let data = try? Data(contentsOf: file), data.count <= 64 * 1024,
              let asset = try? JSONDecoder().decode(JSONValue.self, from: data),
              asset["schema"].integer == 1, asset["reference"].string == "0834340cec5531650bfe78cd628628702e636987",
              asset["inputs"]["src/lib/music/appearance.ts"].string == "cf6e50a8a3267c6aa706a8a7687403c4327738715a2bef5b271f10e82b065fed",
              let source = asset["program"]["source"].string,
              asset["program"]["sha256"].string == "1c2f5cf639e50ccbfa2c18793cf76f1f919cd6ad5e3d7fdb07669e0fd4877dd2",
              SHA256.hash(data: Data(source.utf8)).map({ String(format: "%02x", $0) }).joined() == asset["program"]["sha256"].string,
              let value = JSContext() else { throw HarborError(code: "music-artwork-program") }
        value.evaluateScript(source)
        guard value.exception == nil, value.objectForKeyedSubscript("harborMusicArtwork")?.isUndefined == false else { throw HarborError(code: "music-artwork-program") }
        context = value
        return value
    }
    func analyse(_ pixels: [UInt8]) throws -> MusicArtworkPalette {
        guard pixels.count <= 2304, pixels.count.isMultiple(of: 4) else { throw HarborError(code: "music-artwork-pixels") }
        try Task.checkCancellation()
        let context = try prepare(); context.exception = nil
        let input = try JSONEncoder().encode(pixels)
        let result = context.objectForKeyedSubscript("harborMusicArtwork")?.call(withArguments: [String(decoding: input, as: UTF8.self)])
        guard context.exception == nil, let raw = result?.toString(), raw.utf8.count <= 4096,
              let data = raw.data(using: .utf8) else { throw HarborError(code: "music-artwork-program") }
        let value = try JSONDecoder().decode(MusicArtworkPalette.self, from: data)
        guard value.valid else { throw HarborError(code: "music-artwork-program") }
        return value
    }
    func palette(_ data: Data) throws -> MusicArtworkPalette? {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 4 * 1024 * 1024 else { return nil }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        let pixels = try Self.pixels(data)
        let value = try analyse(pixels)
        try Task.checkCancellation()
        cache.setObject(Entry(value), forKey: key)
        return value
    }
    private static func pixels(_ data: Data) throws -> [UInt8] {
        let decoded = try ArtworkBitmapDecoder.decode(data, maxPixels: 96)
        guard let image = decoded.image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw HarborError(code: "music-artwork-pixels") }
        var pixels = Array<UInt8>(repeating: 0, count: 24 * 24 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 24, height: 24, bitsPerComponent: 8,
                                          bytesPerRow: 24 * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .high
            // A bitmap context already stores its top row first, like the
            // original canvas getImageData; a flip would reverse tie order.
            context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 24))
            return true
        }
        guard rendered else { throw HarborError(code: "music-artwork-pixels") }
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha > 0 && alpha < 255 {
                for channel in 0..<3 { pixels[index + channel] = UInt8(min(255, (Int(pixels[index + channel]) * 255 + alpha / 2) / alpha)) }
            }
        }
        return pixels
    }
}
