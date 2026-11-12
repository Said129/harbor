import XCTest
@testable import Harbor

/// Subtitle files that load with a local video from a picked folder (Desktop's `adjacent_subtitles`).
final class F8LocalSidecarTests: XCTestCase {
    func testSingleVideoFolderTakesEverySubtitle() {
        let names = ["Movie.2020.mkv", "English.srt", "notes.txt", "Other.ass"]
        XCTAssertEqual(LocalSubtitleSidecars.matches(video: "Movie.2020.mkv", siblings: names), ["English.srt", "Other.ass"])
    }

    func testSeveralVideosMatchBySuffixOnly() {
        let names = ["Show.S01E01.mkv", "Show.S01E02.mkv", "Show.S01E01.en.srt", "Show.S01E01-forced.vtt", "Show.S01E010.srt", "Show.S01E02.srt"]
        XCTAssertEqual(LocalSubtitleSidecars.matches(video: "Show.S01E01.mkv", siblings: names), ["Show.S01E01-forced.vtt", "Show.S01E01.en.srt"])
    }

    func testNonSubtitleFilesAreIgnored() {
        let names = ["Clip.mkv", "Clip.mp4", "Clip.jpg", "Clip.pdf"]
        XCTAssertTrue(LocalSubtitleSidecars.matches(video: "Clip.mkv", siblings: names).isEmpty)
    }

    func testFolderSidecarsAreListedBesideTheVideo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("f8-sidecar-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["Film.mkv", "Film.en.srt", "Film.notes.txt"] {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        let urls = LocalSubtitleSidecars.urls(for: folder.appendingPathComponent("Film.mkv"))
        XCTAssertEqual(urls.map(\.lastPathComponent), ["Film.en.srt"])
    }
}
