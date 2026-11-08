import XCTest
@testable import Harbor

/// Manga reader and Suwayomi gaps closed against Desktop 0.9.132: pure decisions only, no network and no UI.
final class G1MangaTests: XCTestCase {
    func testZoomStepperMovesByTenthsWithinDesktopBounds() {
        XCTAssertEqual(MangaReaderRules.zoomed(1, by: 0.1), 1.1, accuracy: 0.0001)
        XCTAssertEqual(MangaReaderRules.zoomed(1, by: -0.1), 0.9, accuracy: 0.0001)
        XCTAssertEqual(MangaReaderRules.zoomed(1.2, by: 0.1), 1.3, accuracy: 0.0001)
        XCTAssertEqual(MangaReaderRules.zoomed(0.5, by: -0.1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(MangaReaderRules.zoomed(3, by: 0.1), 3, accuracy: 0.0001)
    }

    func testZoomPresetsAreDesktopsFivePercentages() {
        XCTAssertEqual(MangaReaderRules.zoomPresets, [0.5, 1, 1.5, 2, 3])
    }

    func testOriginalFitIsContainerWidthTimesZoom() {
        XCTAssertEqual(MangaReaderRules.displayWidth(fit: "original", width: 400, height: 800, ratio: 0.5, zoom: 1.5), 600, accuracy: 0.001)
        XCTAssertEqual(MangaReaderRules.displayWidth(fit: "original", width: 400, height: 800, ratio: 0.1, zoom: 1), 400, accuracy: 0.001)
    }

    func testWidthAndHeightFitsKeepTheirOwnRule() {
        XCTAssertEqual(MangaReaderRules.displayWidth(fit: "width", width: 400, height: 800, ratio: 0.5, zoom: 2), 800, accuracy: 0.001)
        XCTAssertEqual(MangaReaderRules.displayWidth(fit: "height", width: 400, height: 800, ratio: 0.5, zoom: 1), 400, accuracy: 0.001)
    }

    func testProgressMeterFractionClampsAndKeepsTheSyncMark() {
        XCTAssertEqual(MangaReaderRules.progressFraction(current: 0, total: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(MangaReaderRules.progressFraction(current: 4, total: 10), 4.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(MangaReaderRules.progressFraction(current: 50, total: 10), 1, accuracy: 0.0001)
        XCTAssertEqual(MangaReaderRules.progressFraction(current: 0, total: 1), 0)
        XCTAssertEqual(MangaReaderRules.syncThreshold, 0.8, accuracy: 0.0001)
    }

    func testConnectionFailuresAreToldApart() {
        XCTAssertEqual(MangaProbeFailure.classify(status: nil), .unreachable)
        XCTAssertEqual(MangaProbeFailure.classify(status: 401), .auth)
        XCTAssertEqual(MangaProbeFailure.classify(status: 403), .auth)
        XCTAssertEqual(MangaProbeFailure.classify(status: 404), .notFound)
        XCTAssertEqual(MangaProbeFailure.classify(status: 500), .unsupported)
        XCTAssertEqual(MangaProbeFailure.classify(status: 200), .unsupported)
    }

    func testArchiveChapterTakesItsFileNameWithoutExtension() {
        XCTAssertEqual(MangaFolderChapterRules.archiveChapter(stem: "Vol 1 Ch 2", taken: []), "Vol 1 Ch 2")
    }

    func testDuplicateArchiveNamesStaySeparateChapters() {
        XCTAssertEqual(MangaFolderChapterRules.archiveChapter(stem: "Ch 1", taken: ["Ch 1"]), "Ch 1 (2)")
        XCTAssertEqual(MangaFolderChapterRules.archiveChapter(stem: "Ch 1", taken: ["Ch 1", "Ch 1 (2)"]), "Ch 1 (3)")
    }

    func testStoredPagesGroupByTheirChapterFolder() {
        XCTAssertEqual(MangaFolderChapterRules.chapterKey("Ch 1/001.jpg"), "Ch 1")
        XCTAssertEqual(MangaFolderChapterRules.chapterKey("001.jpg"), "local")
    }

    func testArchiveImagesAreStoredUnderTheirChapterWithAFlatName() {
        XCTAssertEqual(MangaFolderChapterRules.entryPath(chapter: "Ch 1", inner: "001.jpg"), "Ch 1/001.jpg")
        XCTAssertEqual(MangaFolderChapterRules.entryPath(chapter: "Ch 1", inner: "sub/002.png"), "Ch 1/sub_002.png")
        XCTAssertEqual(MangaFolderChapterRules.chapterKey(MangaFolderChapterRules.entryPath(chapter: "Ch 1", inner: "sub/002.png")), "Ch 1")
    }
}
