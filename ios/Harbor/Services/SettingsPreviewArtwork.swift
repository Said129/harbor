import Foundation
import ImageIO
import CoreGraphics

enum SettingsPreviewArtwork {
    private static let files = ["the-general-poster", "the-general-still", "sherlock-jr-poster", "the-kid-poster", "safety-last-poster"]
    static let films: [Media] = [
        film("the-general", "The General", poster: "the-general-poster", background: "the-general-still", year: "1926", description: "Buster Keaton sets off to recover his stolen locomotive."),
        film("sherlock-jr", "Sherlock Jr.", poster: "sherlock-jr-poster"),
        film("the-kid", "The Kid", poster: "the-kid-poster"),
        film("safety-last", "Safety Last!", poster: "safety-last-poster")
    ]
    private static func film(_ id: String, _ name: String, poster: String, background: String? = nil, year: String? = nil, description: String? = nil) -> Media {
        Media(id: "settings-preview-" + id, type: "movie", name: name, poster: source(poster), background: background.map(source), description: description, releaseInfo: year)
    }
    private static func source(_ name: String) -> String { "harbor-settings-preview://" + name }
    static func resource(_ raw: String, bundle: Bundle = .main) -> URL? {
        guard let name = files.first(where: { source($0) == raw }) else { return nil }
        return bundle.url(forResource: name, withExtension: "png", subdirectory: "SettingsPreview")
    }
    static func usablePoster(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) else { return false }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32)); return true
        }
        guard rendered else { return true }
        var dark = 0, light = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if max(pixels[index], max(pixels[index + 1], pixels[index + 2])) < 24 { dark += 1 }
            if min(pixels[index], min(pixels[index + 1], pixels[index + 2])) > 235 { light += 1 }
        }
        return Double(dark) / 1_024 < 0.92 && Double(light) / 1_024 < 0.92
    }
}

/// Desktop shares one hourly sample refresh. Offline settings always have bundled art.
actor SettingsPreviewSamples {
    static let shared = SettingsPreviewSamples()
    typealias Fetch = @Sendable (String) async throws -> JSONValue
    typealias Image = @Sendable (String) async throws -> Data
    private let fetch: Fetch
    private let image: Image
    private var cached = SettingsPreviewArtwork.films
    private var refreshedAt: Date?
    private var pending: Task<[Media], Never>?
    init(fetch: @escaping Fetch = { try await HTTPClient().json($0) }, image: @escaping Image = { try await ArtworkStore.shared.data($0) }) {
        self.fetch = fetch; self.image = image
    }
    func samples() async -> [Media] {
        if let refreshedAt, Date().timeIntervalSince(refreshedAt) < 3_600 { return cached }
        if let pending { return await pending.value }
        let task = Task { await self.refresh() }; pending = task
        let value = await task.value; pending = nil; refreshedAt = Date(); cached = value; return value
    }
    private func refresh() async -> [Media] {
        for kind in ["series", "movie"] {
            let response = try? await fetch("https://v3-cinemeta.strem.io/catalog/\(kind)/top.json")
            let candidates = (response?["metas"].array ?? []).compactMap { Media.parse($0, kind: kind) }
                .filter { $0.poster != nil && $0.background != nil && (Double($0.imdbRating ?? "") ?? 0) > 0 && $0.adult != true }.prefix(20)
            var picks: [Media] = []
            let items = Array(candidates)
            for index in stride(from: 0, to: items.count, by: 4) {
                let batch = Array(items[index..<min(index + 4, items.count)]), image = image
                let usable = await withTaskGroup(of: (Int, Bool).self) { group in
                    for (offset, media) in batch.enumerated() {
                        group.addTask {
                            guard let poster = media.poster, let bytes = try? await image(poster) else { return (offset, false) }
                            return (offset, SettingsPreviewArtwork.usablePoster(bytes))
                        }
                    }
                    var accepted = Set<Int>(); for await (offset, valid) in group { if valid { accepted.insert(offset) } }; return accepted
                }
                picks += batch.enumerated().compactMap { usable.contains($0.offset) ? $0.element : nil }
            }
            if !picks.isEmpty {
                let first = picks[0], detailKind = first.type == "movie" ? "movie" : "series"
                if first.description?.isEmpty != false, first.id.range(of: "^tt[0-9]{7,12}$", options: .regularExpression) != nil,
                   let detail = try? await fetch("https://v3-cinemeta.strem.io/meta/\(detailKind)/\(first.id).json"),
                   let base = response?["metas"].array.first(where: { $0["id"].string == first.id }),
                   var media = Media.parse(.object(base.objectValue.merging(detail["meta"].objectValue) { _, value in value }), kind: detailKind) {
                    media.poster = picks[0].poster; picks[0] = media
                }
                return picks
            }
        }
        return SettingsPreviewArtwork.films
    }
}
