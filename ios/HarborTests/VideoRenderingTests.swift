import GLKit
import CoreImage
import CoreMedia
import CoreVideo
import Libmpv
import UIKit
import XCTest
@testable import Harbor

final class VideoRenderingTests: XCTestCase {
    @available(iOS, deprecated: 12.0)
    @MainActor
    func testPictureInPictureRendererRoundTripPreservesVideoOnlyPlaybackAndSeeking() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let images = CIContext(options: [.useSoftwareRenderer: true])
        for depth in [8, 10] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "render-\(depth)bit", withExtension: "mp4", subdirectory: "Fixtures"))
            let state = PlayerState()
            let source = PlaybackSource(url: url.absoluteString, headers: nil, subtitles: nil, via: "test-fixture")
            let controller = MPVController(source: source, state: state)
            window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
            defer { controller.close(); window.rootViewController = nil }
            let surface = try XCTUnwrap(controller.view as? GLKView)
            let loaded = Date().addingTimeInterval(10)
            while Date() < loaded && (!state.loaded || state.position < 0.1 || !state.tracks.contains(where: { $0.type == "video" && $0.selected })) {
                surface.display()
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTAssertTrue(state.loaded)
            let generation = state.mediaGeneration
            let before = state.position
            let track = try XCTUnwrap(state.tracks.first { $0.type == "video" && $0.selected })
            try await controller.prepareSampleRendering()
            let frames = Date().addingTimeInterval(5)
            while Date() < frames && (controller.sampleRenderCalls < 2 || state.position <= before + 0.1) { try await Task.sleep(for: .milliseconds(30)) }
            let buffer = try XCTUnwrap(controller.sampleFrame)
            let input = CIImage(cvPixelBuffer: buffer)
            let cgImage = try XCTUnwrap(images.createCGImage(input, from: input.extent))
            let image = UIImage(cgImage: cgImage)
            let rgb = try colors(image)
            XCTAssertGreaterThan(rgb[0], 120); XCTAssertGreaterThan(rgb[0], rgb[1] + 30)
            XCTAssertGreaterThan(rgb[5], 120); XCTAssertGreaterThan(rgb[5], rgb[4] + 30)
            XCTAssertGreaterThan(controller.sampleRenderCalls, 1)
            XCTAssertGreaterThan(state.position, before)
            XCTAssertEqual(state.mediaGeneration, generation, "Changing output must not load the source again")
            XCTAssertTrue(state.tracks.contains { $0.id == track.id && $0.type == "video" && $0.selected })
            let attachment = XCTAttachment(image: image)
            attachment.name = "native-pip-source-\(depth)bit"; attachment.lifetime = .keepAlways; add(attachment)
            let position = state.position
            try await controller.seekForPictureInPicture(1)
            let seek = Date().addingTimeInterval(5)
            while Date() < seek && state.position < position + 0.5 { try await Task.sleep(for: .milliseconds(30)) }
            XCTAssertGreaterThan(state.position, position + 0.5)
            try await controller.restoreInlineRendering()
            let resumedAt = state.position
            let inline = Date().addingTimeInterval(5)
            var result: [Int] = []
            while Date() < inline {
                surface.display()
                result = try colors(drawableFrame(surface))
                if result[0] > 120 && result[0] > result[1] + 30 && result[5] > 120 && result[5] > result[4] + 30 && state.position > resumedAt + 0.1 { break }
                try await Task.sleep(for: .milliseconds(30))
            }
            XCTAssertGreaterThan(state.position, resumedAt + 0.1)
            XCTAssertGreaterThan(result[0], 120); XCTAssertGreaterThan(result[0], result[1] + 30)
            XCTAssertGreaterThan(result[5], 120); XCTAssertGreaterThan(result[5], result[4] + 30)
            XCTAssertEqual(state.mediaGeneration, generation)
            XCTAssertNil(state.error)
            XCTAssertFalse(state.ended)
            XCTAssertTrue(controller.canRestartPlayback)
        }
    }

    @MainActor
    func testSampleBufferOutputContainsDecoded8And10BitVideoAndRealTime() async throws {
        let images = CIContext(options: [.useSoftwareRenderer: true])
        for depth in [8, 10] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "render-\(depth)bit", withExtension: "mp4", subdirectory: "Fixtures"))
            let handle = try MPVConfiguration.createHandle(decoding: .off)
            var renderer: MPVSampleBufferRenderer?
            defer { renderer?.close(); MPVConfiguration.destroy(handle) }
            renderer = try MPVSampleBufferRenderer(handle: handle)
            let output = try XCTUnwrap(renderer)
            XCTAssertGreaterThanOrEqual(mpv_observe_property(handle, 1, "time-pos", MPV_FORMAT_DOUBLE), 0)
            let command: [String] = ["loadfile", url.absoluteString]
            let allocations = command.map { strdup($0) }
            defer { for pointer in allocations { free(pointer) } }
            guard allocations.allSatisfy({ $0 != nil }) else { throw HarborError(code: "player-allocation") }
            var arguments: [UnsafePointer<CChar>?] = allocations.map { $0.map { UnsafePointer<CChar>($0) } } + [nil]
            XCTAssertGreaterThanOrEqual(mpv_command_async(handle, 0, &arguments), 0)
            var position = 0.0
            var displayed = false
            var lastImage: UIImage?
            var lastBuffer: CVPixelBuffer?
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
                    if event.pointee.event_id == MPV_EVENT_PROPERTY_CHANGE, let data = event.pointee.data {
                        let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                        if property.format == MPV_FORMAT_DOUBLE, let value = property.data { position = value.assumingMemoryBound(to: Double.self).pointee }
                    }
                }
                if let buffer = try output.draw(width: 320, height: 180) {
                    lastBuffer = buffer
                    let input = CIImage(cvPixelBuffer: buffer)
                    let cgImage = try XCTUnwrap(images.createCGImage(input, from: input.extent))
                    let image = UIImage(cgImage: cgImage)
                    lastImage = image
                    let rgb = try colors(image)
                    if position > 0.1 && rgb[0] > 120 && rgb[0] > rgb[1] + 30 && rgb[0] > rgb[2] + 30 && rgb[5] > 120 && rgb[5] > rgb[4] + 30 && rgb[5] > rgb[6] + 30 {
                        let sample = try MPVSampleBufferRenderer.sample(buffer, position: position)
                        XCTAssertTrue(CMSampleBufferIsValid(sample))
                        XCTAssertTrue(CMSampleBufferDataIsReady(sample))
                        XCTAssertEqual(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)), position, accuracy: 0.001)
                        XCTAssertNotNil(CMSampleBufferGetImageBuffer(sample))
                        let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false))
                        let frame = try XCTUnwrap((attachments as NSArray).firstObject as? NSDictionary)
                        XCTAssertEqual(frame[kCMSampleAttachmentKey_DisplayImmediately as String] as? Bool, true)
                        displayed = true; break
                    }
                }
                try await Task.sleep(for: .milliseconds(30))
            }
            if let image = lastImage {
                let attachment = XCTAttachment(image: image)
                attachment.name = "native-sample-buffer-\(depth)bit"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            XCTAssertTrue(displayed, "The sample buffer must carry decoded \(depth)-bit colors and advancing mpv time, not a placeholder frame")
            XCTAssertThrowsError(try output.draw(width: 2_000, height: 2_000))
            let buffer = try XCTUnwrap(lastBuffer)
            XCTAssertThrowsError(try MPVSampleBufferRenderer.sample(buffer, position: .nan))
            output.close(); output.close()
            XCTAssertThrowsError(try output.draw(width: 320, height: 180))
        }
    }

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
            XCTAssertTrue(surface.delegate === controller, "The native GLKView must call its player renderer")
            if let version = glGetString(GLenum(GL_VERSION)), let driver = glGetString(GLenum(GL_RENDERER)) {
                print("Native fixture GL version=\(String(cString: version)), renderer=\(String(cString: driver))")
            }
            // A cold GLES/shader startup must not consume the entire fixture.
            // Clips last 30s; this bounded check exits as soon as pixels/time pass.
            let deadline = Date().addingTimeInterval(20)
            var displayed = false
            var samples: [Int] = []
            var lastSnapshot: UIImage?
            while Date() < deadline, state.error == nil, !state.ended {
                surface.display()
                let snapshot = try drawableFrame(surface)
                // Keep the last active frame if EOF clears the drawable.
                if state.ended { break }
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
            XCTAssertGreaterThan(state.renderCalls, 0, "The native rendering callback must run")
            let videoSelected = state.tracks.contains { $0.type == "video" && $0.selected }
            XCTAssertTrue(displayed, "\(depth)-bit output must contain distinct red/green video pixels and advancing time; RGB samples=\(samples), position=\(state.position), loaded=\(state.loaded), ended=\(state.ended), draws=\(state.renderCalls), videoSelected=\(videoSelected)")
        }
    }

    @available(iOS, deprecated: 12.0)
    @MainActor
    private func drawableFrame(_ surface: GLKView) throws -> UIImage {
        // Read the same nonzero framebuffer the real player renders into.
        // GLKView.snapshot can perform another draw with different bindings.
        XCTAssertTrue(EAGLContext.setCurrent(surface.context))
        surface.bindDrawable()
        let width = surface.drawableWidth, height = surface.drawableHeight
        XCTAssertGreaterThan(width, 0); XCTAssertGreaterThan(height, 0)
        let stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        pixels.withUnsafeMutableBytes { glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress) }
        XCTAssertEqual(glGetError(), GLenum(GL_NO_ERROR), "Drawable readback must not hide an OpenGL error")
        // GL's first row is the bottom; preserve real pixels in an upright PNG.
        var upright = Data(count: pixels.count)
        upright.withUnsafeMutableBytes { target in
            pixels.withUnsafeBytes { source in
                for row in 0..<height {
                    target.baseAddress!.advanced(by: row * stride).copyMemory(from: source.baseAddress!.advanced(by: (height - row - 1) * stride), byteCount: stride)
                }
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: upright as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return UIImage(cgImage: image, scale: surface.contentScaleFactor, orientation: .up)
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
