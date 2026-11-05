import XCTest
@testable import Harbor

/// Desktop's playback stats card (`components/player/stats-overlay.tsx`).
final class PlaybackStatsTests: XCTestCase {
    func testStatsAreReadFromMpvStringsAndEmptyOnesAreDropped() {
        let values = ["video-bitrate": "4500000.000000", "audio-bitrate": "192000", "decoder-frame-drop-count": "3", "frame-drop-count": "12",
                      "estimated-vf-fps": "23.976024", "container-fps": "24", "video-codec": "h264", "audio-codec": "", "hwdec-current": "no",
                      "cache-buffering-state": "100"]
        let stats = PlaybackStats.read { values[$0] }
        XCTAssertEqual(stats.videoBitrate, 4_500_000); XCTAssertEqual(stats.audioBitrate, 192_000)
        XCTAssertEqual(stats.decoderDrops, 3); XCTAssertEqual(stats.outputDrops, 12)
        XCTAssertEqual(try XCTUnwrap(stats.estimatedFPS), 23.976024, accuracy: 0.000001); XCTAssertEqual(stats.containerFPS, 24)
        XCTAssertEqual(stats.videoCodec, "h264"); XCTAssertNil(stats.audioCodec, "An empty codec is no codec")
        XCTAssertNil(stats.hardwareDecoder, "mpv answers no when nothing decodes in hardware"); XCTAssertEqual(stats.cacheBuffering, 100)
        XCTAssertEqual(PlaybackStats.read { _ in nil }, PlaybackStats())
        XCTAssertNil(PlaybackStats.read { _ in "nan" }.videoBitrate, "A value that is not a finite number is dropped")
    }

    func testBitratesUseDesktopsUnits() {
        XCTAssertEqual(PlaybackStats.bitrate(500), "500 bps")
        XCTAssertEqual(PlaybackStats.bitrate(192_000), "192 kbps")
        XCTAssertEqual(PlaybackStats.bitrate(4_500_000), "4.50 Mbps")
        XCTAssertEqual(PlaybackStats.bitrate(999_999), "1000 kbps")
    }

    func testRowsFollowDesktopsOrderAndLeaveOutWhatIsUnknown() {
        let stats = PlaybackStats(videoBitrate: 4_500_000, decoderDrops: 1, estimatedFPS: 23.976, videoCodec: "h264", audioCodec: "aac",
                                  hardwareDecoder: "videotoolbox", cacheBuffering: 100)
        let context = PlaybackStats.Context(width: 1920, height: 1080, audioTrack: "English", subtitleTrack: nil, speed: 1.5, volume: 80, muted: true)
        let rows = stats.rows(context)
        XCTAssertEqual(rows.map(\.label), ["Engine", "Resolution", "Frame rate", "Video codec", "Audio codec", "HW decode", "Video bitrate",
                                           "Dropped (decode / vo)", "Cache buffering", "Audio track", "Subtitle track", "Speed", "Volume"])
        XCTAssertEqual(rows.map(\.value), ["libmpv", "1920×1080", "23.98 fps", "h264", "aac", "videotoolbox", "4.50 Mbps", "1 / —", "100%",
                                           "English", "Off", "1.50×", "80% · muted"])
        let bare = PlaybackStats().rows(PlaybackStats.Context())
        XCTAssertEqual(bare.map(\.label), ["Engine", "Resolution", "Audio track", "Subtitle track", "Speed", "Volume"])
        XCTAssertEqual(bare.map(\.value), ["libmpv", "—", "—", "Off", "1.00×", "100%"])
        XCTAssertEqual(PlaybackStats(containerFPS: 25).rows(PlaybackStats.Context()).first { $0.label == "Frame rate" }?.value, "25.00 fps",
                       "The container's rate stands in when mpv has not estimated one")
    }

    func testRowsPassEveryLabelThroughTheTranslator() {
        let rows = PlaybackStats().rows(PlaybackStats.Context(muted: true), text: { "«" + $0 + "»" })
        XCTAssertEqual(rows.first?.label, "«Engine»"); XCTAssertEqual(rows.last?.value, "100%«" + " · muted" + "»")
        XCTAssertTrue(rows.contains { $0.value == "«Off»" })
    }
}
