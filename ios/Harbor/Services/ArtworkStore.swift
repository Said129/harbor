import Foundation
import ImageIO
import SwiftUI
import UIKit

actor ArtworkStore {
    static let shared = ArtworkStore()
    private let cache = NSCache<NSString, NSData>()
    private var pending: [String: Task<Data, Error>] = [:]
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 25
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 0)
        session = URLSession(configuration: config)
        cache.totalCostLimit = 24 * 1024 * 1024
    }
    func data(_ raw: String) async throws -> Data {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw HarborError(code: "invalid-artwork") }
        if let found = cache.object(forKey: raw as NSString) { return found as Data }
        if let task = pending[raw] { return try await task.value }
        let session = session
        let task = Task<Data, Error> {
            var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw HarborError(code: "artwork-unavailable") }
            let limit = 12 * 1024 * 1024
            guard response.expectedContentLength <= Int64(limit) else { throw HarborError(code: "artwork-too-large") }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw HarborError(code: "artwork-too-large") }
                data.append(byte)
            }
            return data
        }
        pending[raw] = task
        defer { pending[raw] = nil }
        let data = try await task.value
        guard CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw HarborError(code: "invalid-artwork") }
        cache.setObject(data as NSData, forKey: raw as NSString, cost: data.count)
        return data
    }
}

/// Shared loading prevents a hero, poster and detail from starting duplicate
/// downloads. ImageIO downsampling bounds decoded memory on a physical iPhone.
struct BoundedArtworkImage: UIViewRepresentable {
    let image: UIImage
    let fit: ContentMode
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true; view.isAccessibilityElement = false; view.accessibilityElementsHidden = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = image; view.contentMode = fit == .fit ? .scaleAspectFit : .scaleAspectFill
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        // UIImageView draws within its bounds. A scaled SwiftUI Image instead
        // exposes its uncropped bitmap bounds to the hero's AX container.
        proposal.replacingUnspecifiedDimensions()
    }
}

struct Artwork: View {
    let url: String?
    var fallback: String? = nil
    var fallbacks: [String] = []
    var fit: ContentMode = .fill
    var maxPixels = 1000
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            if let image { BoundedArtworkImage(image: image, fit: fit) }
            else {
                Rectangle().fill(.white.opacity(0.045))
                if failed {
                    Image("nav-movies").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white.opacity(0.35))
                } else if url != nil { ProgressView().controlSize(.small) }
            }
        }.clipped().task(id: "\(url ?? "")|\(fallback ?? "")|\(fallbacks.joined(separator: "|"))") {
            image = nil; failed = false
            var seen = Set<String>()
            for raw in ([url, fallback].compactMap({ $0 }) + fallbacks).filter({ !$0.isEmpty && seen.insert($0).inserted }) {
                do {
                    let data = try await ArtworkStore.shared.data(raw)
                    try Task.checkCancellation()
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels] as CFDictionary) else { continue }
                    image = UIImage(cgImage: cgImage); return
                } catch is CancellationError { return }
                catch { continue }
            }
            failed = true
        }
    }
}
