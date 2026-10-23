import CoreGraphics
import ImageIO
import XCTest
@testable import Harbor

final class ReadingBrightnessTests: XCTestCase {
    func testNativeRGBAndRealBookPNGBrightnessKeepAlphaLayoutAndSeparateCachedPages() async throws {
        XCTAssertEqual(ReadingBrightness.bounded(.nan), 100)
        XCTAssertEqual(ReadingBrightness.bounded(0), 55); XCTAssertEqual(ReadingBrightness.bounded(200), 120)
        let space = CGColorSpaceCreateDeviceRGB()
        let color = try XCTUnwrap(CGColor(colorSpace: space, components: [0.25, 0.5, 0.75, 0.6]))
        let dim = try XCTUnwrap(ReadingBrightness.color(color, percent: 55).components)
        XCTAssertEqual(dim[0], 0.1375, accuracy: 0.00001); XCTAssertEqual(dim[3], 0.6, accuracy: 0.00001)
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 8)
        let input: [UInt8] = [40, 80, 120, 128, 200, 100, 50, 255]
        for index in input.indices { bytes[index] = input[index] }
        try ReadingBrightness.apply(context, percent: 120)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes, count: 8)), [48, 96, 128, 128, 240, 120, 60, 255])
        let renderer = EBookPageRenderer(), blocks = [EBookBlock(id: 0, text: "Actual native book brightness.")]
        var ids = Set<String>(), layout: EBookPrintLayout?
        for percent in [55.0, 100.0, 120.0] {
            let document = try await renderer.prepare(blocks: blocks, font: .init(face: "literary"), fontSize: 19, lineHeight: 1.85, paper: .dark, rtl: false, title: "Chapter", owner: "owned", brightness: percent)
            ids.insert(document.id)
            if let layout { XCTAssertEqual(document.layout, layout, "Brightness must not change reading coordinates") } else { layout = document.layout }
            let data = try await renderer.page(document, index: 0)
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let pixel = try XCTUnwrap(image.cropping(to: CGRect(x: 900, y: 1000, width: 1, height: 1)))
            let probe = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            probe.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let actual = try XCTUnwrap(probe.data).bindMemory(to: UInt8.self, capacity: 4)
            for (channel, value) in [23.0, 24.0, 27.0].enumerated() { XCTAssertEqual(Double(actual[channel]), (value * percent / 100).rounded(), accuracy: 1) }
            XCTAssertEqual(actual[3], 255)
        }
        XCTAssertEqual(ids.count, 3, "A brightness change must not reuse a PNG with the old pixel values")
    }
}
