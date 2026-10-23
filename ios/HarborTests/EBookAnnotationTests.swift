import CoreText
import SwiftUI
import UIKit
import XCTest
@testable import Harbor

private actor AnnotationWriteGate: EBookAnnotationPersistence {
    private(set) var values: [EBookAnnotation]
    var rejects = true
    init(_ values: [EBookAnnotation]) { self.values = values }
    func read() -> [EBookAnnotation] { values }
    func write(_ values: [EBookAnnotation]) throws { if rejects { throw HarborError(code: "owned-note-write") }; self.values = values }
    func allowWrites() { rejects = false }
}

@MainActor private final class AnnotationAppearanceHost<Content: View>: UIHostingController<Content> {
    private(set) var appeared = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appeared = true }
}

final class EBookAnnotationTests: XCTestCase {
    func testActualJavaScriptCoreMatchesElevenOriginalReferenceRangeOverlapAndBatchCases() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-annotation-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file)), program = EBookAnnotationProgram()
        XCTAssertEqual(fixture["cases"].array.count, 11)
        let inks = try await program.apply(.object(["operation": .string("inks")]))
        XCTAssertEqual(inks, fixture["palette"]); XCTAssertEqual(inks.array.compactMap(\.string), EBookAnnotation.inks)
        for row in fixture["cases"].array { let result = try await program.apply(row["input"]); XCTAssertEqual(result, row["expected"], row["name"].string ?? "Annotation") }
        let document = EBookAnnotationDocument(blocks: [.init(id: 9, text: "Café"), .init(id: 27, text: "Another\n\nCafé")])
        var note = EBookAnnotation(chapterID: "source:one", ranges: [.init(line: 0, start: 0, end: 4)], text: "Café"); note.reference = true
        let paint = try await program.paint(document, chapterID: "source:other", annotations: [note])
        XCTAssertEqual(paint[9]?.map(\.range), [.init(location: 0, length: 4)])
        XCTAssertEqual(paint[27]?.map(\.range), [.init(location: 9, length: 4)])
    }

    func testNativeSelectionMapsCrossParagraphUTF16RangesWithoutIncludingImageOrSeparatorCharacters() throws {
        let document = EBookAnnotationDocument(blocks: [.init(id: 9, text: "😀 First cafe."), .init(id: 12, text: "Picture", image: Data([1])), .init(id: 27, text: "Second paragraph.\n\nThird.")])
        XCTAssertEqual(document.paragraphs.map(\.block), [9, 27, 27]); XCTAssertEqual(document.paragraphs.map(\.blockStart), [0, 0, 19])
        let selected = (document.text as NSString).range(of: "First cafe.\n\nSecond paragraph.\n\nThi")
        let selection = try XCTUnwrap(document.selection(selected))
        XCTAssertEqual(selection.ranges, [.init(line: 0, start: 3, end: 14), .init(line: 1, start: 0, end: 17), .init(line: 2, start: 0, end: 3)])
        XCTAssertEqual(selection.text, "First cafe.\n\nSecond paragraph.\n\nThi")
        XCTAssertNil(document.selection(.init(location: NSNotFound, length: 1))); XCTAssertNil(document.selection(.init(location: 0, length: Int.max)))
        XCTAssertNil(document.selection(.init(location: 14, length: 2))); XCTAssertNil(document.selection(.init(location: 0, length: 0)))
    }

    @MainActor func testProtectedAnnotationFilesKeepBookProfileIdentityNewestOrderCapAndEditedCreationTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("annotations-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try EBookAnnotationFile(owner: "owner", book: "book", directory: directory)
        let seed = (0..<1000).map { index -> EBookAnnotation in
            var note = EBookAnnotation(chapterID: "source:one", ranges: [.init(line: 0, start: 0, end: 4)], text: "Café"); note.id = "owned-" + String(index); return note
        }
        try await file.write(seed)
        let store = try EBookAnnotationStore(owner: "owner", book: "book", persistence: file); await store.load(); XCTAssertTrue(store.ready)
        var added = EBookAnnotation(chapterID: "source:one", ranges: [.init(line: 0, start: 0, end: 4)], text: "Café"); added.body = "Owned note"; added.tags = ["study", "quote"]
        try await store.save(added)
        XCTAssertEqual(store.items.count, 1000); XCTAssertEqual(store.items.first?.id, added.id); XCTAssertFalse(store.items.contains { $0.id == "owned-999" })
        let created = added.createdAt; added.body = "Edited note"; try await store.save(added)
        let reopened = try EBookAnnotationStore(owner: "owner", book: "book", persistence: EBookAnnotationFile(owner: "owner", book: "book", directory: directory)); await reopened.load()
        XCTAssertEqual(reopened.items.first?.body, "Edited note"); XCTAssertEqual(reopened.items.first?.createdAt, created); XCTAssertEqual(reopened.items.filter { $0.id == added.id }.count, 1)
        let otherOwner = try EBookAnnotationFile(owner: "other", book: "book", directory: directory), otherBook = try EBookAnnotationFile(owner: "owner", book: "other", directory: directory)
        let otherValues = try await otherOwner.read(), otherBooks = try await otherBook.read(); XCTAssertTrue(otherValues.isEmpty); XCTAssertTrue(otherBooks.isEmpty)
        try await reopened.remove(added.id); let remaining = try await file.read(); XCTAssertFalse(remaining.contains { $0.id == added.id })
    }

    @MainActor func testRejectedAnnotationWriteKeepsThePreviousListAndAllowsRetryWithoutChangingTheNoteID() async throws {
        let original = EBookAnnotation(chapterID: "source:one", ranges: [.init(line: 0, start: 0, end: 4)], text: "Café")
        let gate = AnnotationWriteGate([original]), store = try EBookAnnotationStore(owner: "owned", book: "owned", persistence: gate)
        await store.load(); let revision = store.revision
        var changed = original; changed.body = "Retried note"
        do { try await store.save(changed); XCTFail("A failed write must not replace the displayed or durable note") } catch {}
        XCTAssertEqual(store.items, [original]); XCTAssertEqual(store.revision, revision); XCTAssertFalse(store.busy)
        let unchanged = await gate.values; XCTAssertEqual(unchanged, [original])
        await gate.allowWrites(); try await store.save(changed)
        XCTAssertEqual(store.items, [changed]); XCTAssertEqual(store.items.first?.id, original.id); XCTAssertEqual(store.revision, revision + 1)
        var invalid = changed; invalid.density = .nan
        do { try await store.save(invalid); XCTFail("Invalid styling must preserve the saved note") } catch {}
        XCTAssertEqual(store.items, [changed])
    }

    @MainActor func testMountedNativeHighlightDrawsDensityAndRetainsImportedFontAttributesAndSourceText() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "owned-reader-woff2", withExtension: "ttf", subdirectory: "Fixtures"))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(contentsOf: file) as CFData)), graphic = try XCTUnwrap(CGFont(provider)), font = CTFontCreateWithGraphicsFont(graphic, 24, nil, nil)
        let paint = [EBookAnnotationPaint(range: .init(location: 0, length: 3), id: "owned", color: EBookAnnotation.inks[0], density: 58)]
        let attributed = EBookAnnotationStyle.attributed("ABC ABC", paint: paint, font: font, ink: .white, lineSpacing: 10, rtl: false, brightness: 100)
        XCTAssertEqual(attributed.string, "ABC ABC"); XCTAssertNotNil(attributed.attribute(.backgroundColor, at: 0, effectiveRange: nil)); XCTAssertNil(attributed.attribute(.backgroundColor, at: 4, effectiveRange: nil))
        let bridged = try XCTUnwrap(attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(bridged.fontName, "HarborOwned-woff2")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first), previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = .init(x: 0, y: 0, width: 390, height: 700)
        let host = AnnotationAppearanceHost(rootView: EBookAnnotatedPassage(text: "ABC ABC", paint: paint, font: font, ink: .white, spacing: 10, rtl: false, brightness: 100) { _ in }.frame(width: 280, height: 120).background(.black))
        host.view.backgroundColor = .black; window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        for _ in 0..<100 { if host.appeared { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(host.appeared, "Complete the actual native appearance before detaching its test window")
        func labels(_ view: UIView) -> [UILabel] { (view as? UILabel).map { [$0] } ?? view.subviews.flatMap(labels) }
        let label = try XCTUnwrap(labels(host.view).first { $0.accessibilityIdentifier == "ebook-reader-text" })
        XCTAssertTrue(label.isAccessibilityElement); XCTAssertTrue(label.accessibilityTraits.contains(.staticText)); XCTAssertEqual(label.accessibilityLabel, "ABC ABC")
        var pixels = 0
        for _ in 0..<40 {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { window.layer.render(in: $0.cgContext) }
            let bitmap = try XCTUnwrap(image.cgImage), context = try XCTUnwrap(CGContext(data: nil, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(bitmap, in: .init(x: 0, y: 0, width: CGFloat(bitmap.width), height: CGFloat(bitmap.height)))
            let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: bitmap.width * bitmap.height * 4)
            pixels = stride(from: 0, to: bitmap.width * bitmap.height * 4, by: 4).reduce(0) { count, index in count + (bytes[index] > 80 && bytes[index + 1] > 50 && bytes[index + 2] < 120 && bytes[index] > bytes[index + 1] ? 1 : 0) }
            if pixels > 30 { break }; try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(pixels, 30, "An attributed string alone does not prove visible highlight pixels in the native reader")
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "HarborOwned-woff2")
    }
}
