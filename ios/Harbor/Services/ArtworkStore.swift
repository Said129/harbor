import Foundation
import ImageIO
import Observation
import SwiftUI
import UIKit

@MainActor @Observable
final class ArtworkRefresh {
    static let shared = ArtworkRefresh()
    private(set) var revision = 0
    func retryFailedImages() { revision &+= 1 }
}

actor ArtworkStore {
    static let shared = ArtworkStore()
    private struct Pending {
        let id: UUID
        let task: Task<Data, Error>
    }
    private let cache = NSCache<NSString, NSData>()
    private var pending: [String: Pending] = [:]
    private var cachedKeys = Set<String>()
    private var generation = 0
    private var session: URLSession

    init(configuration: URLSessionConfiguration? = nil) {
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 25
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 0)
        session = URLSession(configuration: config)
        cache.totalCostLimit = 24 * 1024 * 1024
    }
    deinit { session.invalidateAndCancel() }

    func data(_ raw: String) async throws -> Data {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw HarborError(code: "invalid-artwork") }
        if let found = cache.object(forKey: raw as NSString) { return found as Data }
        if let entry = pending[raw] { return try await entry.task.value }
        let session = session, epoch = generation, requestID = UUID()
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
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) != nil,
                  CGImageSourceGetCount(source) > 0, CGImageSourceGetStatus(source) == .statusComplete else {
                session.configuration.urlCache?.removeCachedResponse(for: request)
                throw HarborError(code: "invalid-artwork")
            }
            return data
        }
        pending[raw] = Pending(id: requestID, task: task)
        defer { if pending[raw]?.id == requestID { pending[raw] = nil } }
        let data = try await task.value
        if epoch == generation {
            cache.setObject(data as NSData, forKey: raw as NSString, cost: data.count)
            cachedKeys.insert(raw)
            if cachedKeys.count > 256 { cachedKeys = cachedKeys.filter { cache.object(forKey: $0 as NSString) != nil } }
        }
        return data
    }

    func cachedBytes() -> Int64 {
        cachedKeys = cachedKeys.filter { cache.object(forKey: $0 as NSString) != nil }
        let encoded = cachedKeys.reduce(Int64(0)) { $0 + Int64(cache.object(forKey: $1 as NSString)?.length ?? 0) }
        return encoded + Int64(max(0, session.configuration.urlCache?.currentMemoryUsage ?? 0))
    }

    func clearCache() {
        generation &+= 1
        cache.removeAllObjects(); cachedKeys.removeAll(); pending.removeAll()
        let old = session, configuration = old.configuration
        old.configuration.urlCache?.removeAllCachedResponses()
        // In-flight views finish against their old session. Its responses cannot
        // refill the new session's HTTP cache or erase a newer pending request.
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 0)
        session = URLSession(configuration: configuration)
        old.finishTasksAndInvalidate()
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
    var fitAlignment: UnitPoint? = nil
    var maxPixels = 1000
    var failureIcon = "nav-movies"
    var showsPlaceholder = true
    var onImageAvailability: ((Bool) -> Void)? = nil
    var onLoadCompletion: ((Bool) -> Void)? = nil
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retryRevision = 0
    var body: some View {
        ZStack {
            if let image {
                if fit == .fit, let fitAlignment { AlignedArtworkImage(image: image, alignment: fitAlignment) }
                else { BoundedArtworkImage(image: image, fit: fit) }
            }
            else if showsPlaceholder {
                Rectangle().fill(.white.opacity(0.045))
                if failed {
                    Image(failureIcon).resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white.opacity(0.35))
                } else if url != nil { ProgressView().controlSize(.small) }
            }
        }.clipped().allowsHitTesting(false).task(id: "\(url ?? "")|\(fallback ?? "")|\(fallbacks.joined(separator: "|"))|\(maxPixels)|\(retryRevision)") {
            image = nil; failed = false; onImageAvailability?(false)
            var seen = Set<String>()
            for raw in ([url, fallback].compactMap({ $0 }) + fallbacks).filter({ !$0.isEmpty && seen.insert($0).inserted }) {
                do {
                    let data = try await ArtworkStore.shared.data(raw)
                    try Task.checkCancellation()
                    let decoded = try await ArtworkBitmapDecoder.thumbnail(data, maxPixels: maxPixels)
                    try Task.checkCancellation()
                    image = decoded.image; onImageAvailability?(true); onLoadCompletion?(true); return
                } catch is CancellationError { return }
                catch { continue }
            }
            failed = true; onLoadCompletion?(false)
        }
        .onChange(of: ArtworkRefresh.shared.revision) { _, _ in if failed { retryRevision &+= 1 } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if failed { retryRevision &+= 1 }
        }
    }
}
