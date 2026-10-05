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
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 25
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024)
        session = URLSession(configuration: config)
        cache.totalCostLimit = 24 * 1024 * 1024
    }
    func data(_ raw: String) async throws -> Data {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw HarborError(code: "invalid-artwork") }
        if let found = cache.object(forKey: raw as NSString) { return found as Data }
        if let task = pending[raw] { return try await task.value }
        let session = session
        let task = Task<Data, Error> {
            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 25)
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
        cache.setObject(data as NSData, forKey: raw as NSString, cost: data.count)
        return data
    }
}

/// Shared loading prevents a hero, poster and detail from starting duplicate
/// downloads. ImageIO downsampling bounds decoded memory on a physical iPhone.
struct Artwork: View {
    let url: String?
    var fallback: String? = nil
    var fit: ContentMode = .fill
    var maxPixels = 1000
    @State private var image: UIImage?
    @State private var failed = false
    @State private var revision = 0
    var body: some View {
        ZStack {
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: fit) }
            else {
                Rectangle().fill(.white.opacity(0.045))
                if failed {
                    Image("nav-movies").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white.opacity(0.35))
                } else if url != nil { ProgressView().controlSize(.small) }
            }
        }.clipped().task(id: "\(url ?? "")|\(fallback ?? "")|\(revision)") {
            image = nil; failed = false
            for raw in [url, fallback].compactMap({ $0 }).filter({ !$0.isEmpty }) {
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
