import CoreMedia
import CoreVideo
import Foundation
import Libmpv

/// CPU output for AVKit's sample-buffer path. The caller must remove the old
/// renderer first and close this context before destroying the same mpv core.
/// Ordinary playback continues to use the existing GLES renderer.
@MainActor
final class MPVSampleBufferRenderer {
    private var context: OpaquePointer?
    private var pool: CVPixelBufferPool?
    private var size: (width: Int, height: Int)?

    init(handle: OpaquePointer) throws {
        let status = "sw".withCString { api in
            var parameters = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(mutating: api)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
            ]
            return mpv_render_context_create(&context, handle, &parameters)
        }
        guard status >= 0 else { throw HarborError(code: "mpv-\(status)") }
    }

    func draw(width: Int, height: Int, force: Bool = false) throws -> CVPixelBuffer? {
        guard let context else { throw HarborError(code: "player-not-ready") }
        guard (32...1_280).contains(width), (32...1_280).contains(height), width * height <= 921_600 else { throw HarborError(code: "player-frame-size") }
        let changed = mpv_render_context_update(context) & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0
        guard changed || force else { return nil }
        let pool = try bufferPool(width: width, height: height)
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey: 6] as CFDictionary
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, attributes, &buffer)
        // AVKit may still own the preceding frames. Drop a new frame rather
        // than growing an unbounded queue while its display is busy.
        if status == kCVReturnWouldExceedAllocationThreshold {
            var skip: Int32 = 1
            let result = withUnsafeMutablePointer(to: &skip) { skip in
                var parameters = [mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: skip), mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)]
                return mpv_render_context_render(context, &parameters)
            }
            guard result >= 0 else { throw HarborError(code: "mpv-\(result)") }
            mpv_render_context_report_swap(context)
            return nil
        }
        guard status == kCVReturnSuccess, let buffer, CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw HarborError(code: "player-frame-buffer") }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let pixels = CVPixelBufferGetBaseAddress(buffer) else { throw HarborError(code: "player-frame-buffer") }
        var stride = UInt(CVPixelBufferGetBytesPerRow(buffer))
        guard stride >= UInt(width * 4), stride % 4 == 0, UInt(bitPattern: pixels) % 4 == 0 else { throw HarborError(code: "player-frame-buffer") }
        var dimensions: [Int32] = [Int32(width), Int32(height)]
        let result = dimensions.withUnsafeMutableBufferPointer { dimensions in
            withUnsafeMutablePointer(to: &stride) { stride in
                "bgr0".withCString { format in
                    var parameters = [
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: dimensions.baseAddress),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: UnsafeMutableRawPointer(mutating: format)),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: stride),
                        mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pixels),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                    ]
                    return mpv_render_context_render(context, &parameters)
                }
            }
        }
        guard result >= 0 else { throw HarborError(code: "mpv-\(result)") }
        // bgr0 is a documented mpv output format. Its fourth byte is undefined;
        // set opaque alpha explicitly for CoreVideo's BGRA interpretation.
        let bytes = pixels.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            let start = row * Int(stride)
            for column in 0..<width { bytes[start + column * 4 + 3] = 255 }
        }
        mpv_render_context_report_swap(context)
        return buffer
    }

    private func bufferPool(width: Int, height: Int) throws -> CVPixelBufferPool {
        if let pool, size?.width == width, size?.height == height { return pool }
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
            kCVPixelBufferBytesPerRowAlignmentKey: 64,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]
        ]
        var created: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary, attributes as CFDictionary, &created)
        guard status == kCVReturnSuccess, let created else { throw HarborError(code: "player-frame-buffer") }
        pool = created; size = (width, height)
        return created
    }

    static func sample(_ buffer: CVPixelBuffer, position: Double) throws -> CMSampleBuffer {
        guard position.isFinite, position >= 0 else { throw HarborError(code: "player-frame-time") }
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &format) == 0,
              let format else { throw HarborError(code: "player-frame-buffer") }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: position, preferredTimescale: 60_000), decodeTimeStamp: .invalid)
        var created: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &created) == 0,
              let created else { throw HarborError(code: "player-frame-buffer") }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(created, createIfNecessary: true),
              let first = (attachments as NSArray).firstObject as? NSMutableDictionary else { throw HarborError(code: "player-frame-buffer") }
        first[kCMSampleAttachmentKey_DisplayImmediately as String] = true
        return created
    }

    func close() {
        if let context { mpv_render_context_free(context); self.context = nil }
        pool = nil; size = nil
    }
}
