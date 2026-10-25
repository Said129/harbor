import SwiftUI
import UIKit
import ImageIO

/// Only a hovered/keyboard-focused card decodes an animation. Images are
/// immutable once handed from the decoder to the main-thread image view.
struct SourceDecodedAnimation: @unchecked Sendable {
    let images: [UIImage]
    let duration: Double
    let repeats: Int
}
enum SourceAnimationDecoder {
    static func decode(_ data: Data) throws -> SourceDecodedAnimation {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { throw HarborError(code: "invalid-artwork") }
        let count = CGImageSourceGetCount(source), step = max(1, Int(ceil(Double(count) / 160)))
        let selectedCount = Int(ceil(Double(count) / Double(step)))
        let pixels = min(480, max(64, Int(sqrt(Double(12 * 1_024 * 1_024) / Double(selectedCount * 4)))))
        var frames: [(UIImage, Int)] = [], total = 0
        for index in stride(from: 0, to: count, by: step) {
            try Task.checkCancellation()
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { continue }
            var milliseconds = 0
            for frame in index..<min(index + step, count) {
                try Task.checkCancellation()
                let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [String: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
                let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)?.doubleValue
                    ?? (gif?[kCGImagePropertyGIFDelayTime as String] as? NSNumber)?.doubleValue ?? 0.1
                milliseconds += Int((delay >= 0.02 ? min(delay, 60) : 0.1) * 1_000)
            }
            frames.append((UIImage(cgImage: image), max(20, milliseconds))); total += max(20, milliseconds)
        }
        guard !frames.isEmpty else { throw HarborError(code: "invalid-artwork") }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let quantum = max(10, max(frames.reduce(0) { gcd($0, $1.1) }, Int(ceil(Double(total) / 2_000))))
        let images = frames.flatMap { Array(repeating: $0.0, count: max(1, Int((Double($0.1) / Double(quantum)).rounded()))) }
        let properties = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let repeats = (gif?[kCGImagePropertyGIFLoopCount as String] as? NSNumber)?.intValue ?? 0
        return SourceDecodedAnimation(images: images, duration: Double(total) / 1_000, repeats: max(0, repeats))
    }
}

struct SourceFocusArtwork: View {
    let url: String
    @State private var animation: SourceDecodedAnimation?
    var body: some View {
        Group { if let animation { SourceAnimationImage(animation: animation) } else { Color.clear } }
            .allowsHitTesting(false).accessibilityHidden(true).task(id: url) {
                animation = nil
                do {
                    let data = try await ArtworkStore.shared.data(url); try Task.checkCancellation()
                    let decoder = Task.detached(priority: .utility) { try SourceAnimationDecoder.decode(data) }
                    let result = try await withTaskCancellationHandler(operation: { try await decoder.value }, onCancel: { decoder.cancel() })
                    try Task.checkCancellation(); animation = result
                } catch { animation = nil }
            }
    }
}
private struct SourceAnimationImage: UIViewRepresentable {
    let animation: SourceDecodedAnimation
    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(); view.contentMode = .scaleAspectFill; view.clipsToBounds = true
        view.isAccessibilityElement = false; view.accessibilityElementsHidden = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }
    func updateUIView(_ view: UIImageView, context: Context) {
        view.image = animation.images.first; view.animationImages = animation.images
        view.animationDuration = animation.duration; view.animationRepeatCount = animation.repeats
        if animation.images.count > 1 { view.startAnimating() }
    }
    static func dismantleUIView(_ view: UIImageView, coordinator: ()) { view.stopAnimating(); view.animationImages = nil; view.image = nil }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? { proposal.replacingUnspecifiedDimensions() }
}
