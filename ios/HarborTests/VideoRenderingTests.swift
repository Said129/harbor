import GLKit
import UIKit
import XCTest
@testable import Harbor

final class VideoRenderingTests: XCTestCase {
    // The renderer being exercised is already deprecated. This test deliberately
    // checks its real output until a separately validated Metal renderer replaces it.
    @available(iOS, deprecated: 12.0)
    @MainActor
    func testNativeRendererDisplaysDistinctColorsFrom8And10BitVideo() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }

        for depth in [8, 10] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "render-\(depth)bit", withExtension: "mp4", subdirectory: "Fixtures"))
            let state = PlayerState()
            let source = PlaybackSource(url: url.absoluteString, headers: nil, subtitles: nil, via: "test-fixture")
            let controller = MPVController(source: source, state: state)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            defer { controller.close(); window.rootViewController = nil }
            let surface = try XCTUnwrap(controller.view as? GLKView)
            let deadline = Date().addingTimeInterval(10)
            var displayed = false
            var samples: [Int] = []
            var lastSnapshot: UIImage?
            while Date() < deadline, state.error == nil {
                let snapshot = surface.snapshot
                lastSnapshot = snapshot
                samples = try colors(snapshot)
                if state.hasPosition && state.position > 0.1 &&
                    samples[0] > 120 && samples[0] > samples[1] + 30 && samples[0] > samples[2] + 30 &&
                    samples[5] > 120 && samples[5] > samples[4] + 30 && samples[5] > samples[6] + 30 {
                    displayed = true
                    break
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            if let snapshot = lastSnapshot {
                let attachment = XCTAttachment(image: snapshot)
                attachment.name = "native-render-\(depth)bit"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertNil(state.error)
            XCTAssertTrue(displayed, "\(depth)-bit output must contain distinct red/green video pixels and advancing time; RGB samples=\(samples)")
        }
    }

    private func colors(_ image: UIImage) throws -> [Int] {
        let source = try XCTUnwrap(image.cgImage)
        let left = try XCTUnwrap(source.cropping(to: CGRect(x: CGFloat(source.width) / 4, y: CGFloat(source.height) / 2, width: 1, height: 1)))
        let right = try XCTUnwrap(source.cropping(to: CGRect(x: CGFloat(source.width) * 3 / 4, y: CGFloat(source.height) / 2, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 8)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(left, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            context.draw(right, in: CGRect(x: 1, y: 0, width: 1, height: 1))
        }
        return bytes.map(Int.init)
    }
}
