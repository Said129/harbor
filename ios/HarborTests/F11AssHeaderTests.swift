import XCTest
@testable import Harbor

/// F11 S227: where the ASS header for size normalisation comes from, and that a header alone is enough to measure it.
@MainActor
final class F11AssHeaderTests: XCTestCase {
    private let header = """
    [Script Info]
    PlayResY: 720

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour
    Style: Default,Arial,36,&H00FFFFFF
    Style: Signs,Arial,20,&H00FFFFFF

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
    """

    private func track(external: Bool, filename: String) -> PlayerState.Track {
        var value = PlayerState.Track(id: 4, type: "sub", label: "Sub", selected: true)
        value.codec = "ass"
        value.external = external
        value.externalFilename = filename
        return value
    }

    func testEmbeddedTrackUsesTheHeaderMpvHolds() {
        XCTAssertEqual(SubtitleAssHeaderSource.choose(for: track(external: false, filename: "")), .mpvHeader)
    }

    func testExternalLocalPathAndFileURLAreReadFromDisk() {
        let path = SubtitleAssHeaderSource.choose(for: track(external: true, filename: "/tmp/episode.ass"))
        XCTAssertEqual(path, .localFile(URL(fileURLWithPath: "/tmp/episode.ass")))
        let url = SubtitleAssHeaderSource.choose(for: track(external: true, filename: "file:///tmp/episode.ass"))
        XCTAssertEqual(url, .localFile(URL(string: "file:///tmp/episode.ass")!))
    }

    func testExternalRemoteAddressIsFetched() {
        let chosen = SubtitleAssHeaderSource.choose(for: track(external: true, filename: "https://example.test/sub/episode.ass"))
        XCTAssertEqual(chosen, .remoteFile(URL(string: "https://example.test/sub/episode.ass")!))
    }

    func testRemoteAddressNeedsHttpHostAndNoCredentials() {
        XCTAssertNil(SubtitleAssHeaderSource.remoteURL("ftp://example.test/a.ass"))
        XCTAssertNil(SubtitleAssHeaderSource.remoteURL("https://user:pass@example.test/a.ass"))
        XCTAssertNil(SubtitleAssHeaderSource.remoteURL("https:///a.ass"))
        XCTAssertNotNil(SubtitleAssHeaderSource.remoteURL("http://example.test/a.ass"))
    }

    func testAnExternalNameThatIsNeitherFileNorAddressFallsBackToMpv() {
        XCTAssertEqual(SubtitleAssHeaderSource.choose(for: track(external: true, filename: "weird://scheme/a.ass")), .mpvHeader)
        XCTAssertEqual(SubtitleAssHeaderSource.choose(for: track(external: true, filename: "")), .mpvHeader)
    }

    func testAHeaderWithoutDialogueStillGivesAFactor() {
        // 36 / 720 is inside Desktop's 2 to 22 percent window, and the Default style is the fallback when no line is counted.
        let factor = AssSizeNormalization.baseFactor(assText: header)
        XCTAssertEqual(factor ?? -1, 720.0 / (720.0 * 36.0), accuracy: 1e-9)
    }

    func testLocalFileReadingKeepsUTF8AndRejectsEmptyOrMissingFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("F11Ass-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let good = folder.appendingPathComponent("good.ass")
        try Data(header.utf8).write(to: good)
        XCTAssertEqual(SubtitleAssHeaderLoader.text(forFileAt: good), header)
        let empty = folder.appendingPathComponent("empty.ass")
        try Data().write(to: empty)
        XCTAssertNil(SubtitleAssHeaderLoader.text(forFileAt: empty))
        XCTAssertNil(SubtitleAssHeaderLoader.text(forFileAt: folder.appendingPathComponent("missing.ass")))
    }

    func testDecodeRejectsNulBytesAndOversizeData() {
        XCTAssertNil(SubtitleAssHeaderLoader.decode(Data([0x5B, 0x00, 0x5D])))
        XCTAssertNil(SubtitleAssHeaderLoader.decode(Data()))
        XCTAssertNil(SubtitleAssHeaderLoader.decode(Data(count: SubtitleAssHeaderLoader.byteLimit + 1)))
    }

    func testDecodeReadsUTF16WithAByteOrderMark() {
        var data = Data([0xFF, 0xFE])
        data.append("[Script Info]".data(using: .utf16LittleEndian) ?? Data())
        XCTAssertEqual(SubtitleAssHeaderLoader.decode(data), "[Script Info]")
    }
}
