import Foundation
import ImageIO

/// Prepare only a verified wide URL. The mounted Artwork view confirms actual
/// pixel decoding before the row reserves its expanded width.
actor ExpandingCardArtwork {
    static let shared = ExpandingCardArtwork()
    typealias FetchImage = @Sendable (String) async throws -> Data
    typealias Candidates = @Sendable (Media, MetadataConfiguration) async -> [String]
    private let image: FetchImage
    private let candidates: Candidates
    private let gate = AnimeMetadataGate()
    private var prepared: [String: (url: String, at: Date)] = [:]
    private var pending: [String: Task<String?, Never>] = [:]
    private var failed: [String: Date] = [:]
    init(image: @escaping FetchImage = { try await ArtworkStore.shared.data($0) },
        candidates: @escaping Candidates = { await CardArtworkResolver.shared.wideCandidates($0, configuration: $1) }) {
        self.image = image; self.candidates = candidates
    }
    nonisolated static func key(_ media: Media, _ configuration: MetadataConfiguration) -> String {
        CardArtworkResolver.cacheKey(media, configuration)
    }
    func prepare(_ media: Media, configuration: MetadataConfiguration) async -> String? {
        guard !Task.isCancelled else { return nil }
        let key = Self.key(media, configuration)
        if let saved = prepared[key] { return saved.url }
        if let task = pending[key] { return await task.value }
        let task = Task { await self.perform(media, configuration: configuration) }
        pending[key] = task
        let value = await task.value; pending[key] = nil
        if let value {
            if prepared.count >= 300, let oldest = prepared.min(by: { $0.value.at < $1.value.at })?.key { prepared[oldest] = nil }
            prepared[key] = (value, Date())
        }
        return value
    }
    func invalidate(key: String, url: String) {
        if prepared[key]?.url == url { prepared[key] = nil }
        if failed.count >= 300, let oldest = failed.min(by: { $0.value < $1.value })?.key { failed[oldest] = nil }
        failed[url] = Date()
    }
    private func perform(_ media: Media, configuration: MetadataConfiguration) async -> String? {
        let immediate = PosterBehaviorPolicy.alternatives([media.background].compactMap { $0 }, poster: media.poster, failed: Set(failed.keys))
        var tried = Set<String>()
        for url in immediate {
            tried.insert(url)
            if await suitable(url) { return url }
        }
        let values = await candidates(media, configuration)
        for url in PosterBehaviorPolicy.alternatives(values, poster: media.poster, failed: Set(failed.keys)).prefix(8) where tried.insert(url).inserted {
            if await suitable(url) { return url }
        }
        return nil
    }
    private func suitable(_ url: String) async -> Bool {
        let image = image
        return (try? await gate.run {
            let data = try await image(url)
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let rawWidth = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue,
                  let rawHeight = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue else { return false }
            let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
            let swapped = [5, 6, 7, 8].contains(orientation)
            return PosterBehaviorPolicy.suitableWideImage(width: swapped ? rawHeight : rawWidth, height: swapped ? rawWidth : rawHeight)
        }) ?? false
    }
}
