import XCTest
@testable import Harbor

final class R19PlayerTests: XCTestCase {
    /// `[(String, String)]` is not Equatable, so the option lists are compared as `name=value` lines.
    private func lines(_ options: [(String, String)]) -> [String] {
        options.map { "\($0.0)=\($0.1)" }
    }

    func testBufferBoostLiftsOnlyAutoToLarge() {
        XCTAssertEqual(BufferSize.effective(.auto, boost: true), .large)
        XCTAssertEqual(BufferSize.effective(.auto, boost: false), .auto)
        XCTAssertEqual(BufferSize.effective(.small, boost: true), .small)
        XCTAssertEqual(BufferSize.effective(.max, boost: true), .max)
    }

    func testAutoAddsNoCacheOptions() {
        XCTAssertTrue(BufferSize.auto.mpvOptions.isEmpty)
    }

    func testBoostedLargeKeepsDesktopDurationsWithinTheMemoryBudget() {
        let boosted = lines(BufferSize.effective(.auto, boost: true).mpvOptions)
        XCTAssertTrue(boosted.contains("cache-secs=600"))
        XCTAssertTrue(boosted.contains("demuxer-readahead-secs=600"))
        let prefix = "demuxer-max-bytes="
        let bytes = boosted.first { $0.hasPrefix(prefix) }.flatMap { UInt64($0.dropFirst(prefix.count)) }
        XCTAssertNotNil(bytes)
        // BufferSize's budget is at most 512 MiB on any device, so the boosted forward cache can never ask for the 1 GiB Desktop maximum.
        XCTAssertLessThanOrEqual(bytes ?? UInt64.max, UInt64(512 * 1024 * 1024))
    }

    func testHdrToSdrOffAddsNoMpvOptions() {
        XCTAssertTrue(UISettingsPolicy.hdrToSdrMpvOptions(false).isEmpty)
    }

    func testHdrToSdrOnListsDesktopBlockInDesktopOrder() {
        XCTAssertEqual(lines(UISettingsPolicy.hdrToSdrMpvOptions(true)), [
            "tone-mapping=spline", "gamut-mapping-mode=perceptual", "hdr-compute-peak=yes",
            "hdr-contrast-recovery=0.30", "hdr-peak-percentile=99.995", "dither-depth=auto",
            "target-trc=bt.1886", "target-prim=bt.709"
        ])
    }

    func testBothSettingsDefaultToOffWhenUnset() {
        let suite = "r19.player.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(defaults.bool(forKey: BufferSize.boostKey))
        XCTAssertFalse(defaults.bool(forKey: UISettingsPolicy.hdrToSdrKey))
        XCTAssertTrue(UISettingsPolicy.hdrToSdrMpvOptions(defaults.bool(forKey: UISettingsPolicy.hdrToSdrKey)).isEmpty)
    }

    func testBothSettingsAreProfileKeys() {
        XCTAssertEqual(BufferSize.boostKey, "mpvBufferBoost")
        XCTAssertEqual(UISettingsPolicy.hdrToSdrKey, "playerHdrToSdr")
        XCTAssertTrue(ProfileSettingsStore.keys.contains("mpvBufferBoost"))
        XCTAssertTrue(ProfileSettingsStore.keys.contains("playerHdrToSdr"))
    }
}
