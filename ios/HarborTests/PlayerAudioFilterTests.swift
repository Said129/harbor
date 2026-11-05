import XCTest
@testable import Harbor

/// Desktop's playback audio filters (`applyAudioFilters` and `AUDIO_PROFILE_AF` in `lib/player/mpv.ts`).
final class PlayerAudioFilterTests: XCTestCase {
    private let normalizer = "dynaudnorm=f=500:g=31:p=0.9:m=4:b=1"
    private let limiter = "lavfi=[alimiter=limit=0.97]"

    func testNothingIsAskedOfLibmpvWhileTheFiltersAreOff() {
        let options = PlaybackOptions()
        XCTAssertEqual(options.audioFilters, "")
        XCTAssertFalse(options.mpvOptions.contains { $0.0 == "af" }, "A player without filters never sets an audio filter chain")
    }

    func testTheNormalizerAndEachProfileFollowDesktopsChains() {
        var options = PlaybackOptions()
        options.audioNormalize = true
        XCTAssertEqual(options.audioFilters, normalizer + "," + limiter)
        options.audioNormalize = false
        let expected: [String: String] = [
            "bass": "lavfi=[bass=g=7:f=110:w=0.6]",
            "voice": "lavfi=[equalizer=f=300:t=q:w=1:g=-3,equalizer=f=2800:t=q:w=1:g=5]",
            "bass-reduce": "lavfi=[bass=g=-8:f=110:w=0.6]",
            "night": "lavfi=[acompressor=ratio=3:threshold=-20dB:attack=20:release=300:makeup=4dB]"]
        for (profile, filter) in expected {
            options.audioProfile = profile
            XCTAssertEqual(options.audioFilters, filter + "," + limiter, profile)
        }
        XCTAssertEqual(Set(AudioProfile.allCases.map(\.rawValue)), Set(expected.keys).union(["off"]))
    }

    func testTheProfileStacksAfterTheNormalizerAndAnUnknownOneIsIgnored() {
        var options = PlaybackOptions()
        options.audioNormalize = true; options.audioProfile = "night"
        XCTAssertEqual(options.audioFilters, normalizer + ",lavfi=[acompressor=ratio=3:threshold=-20dB:attack=20:release=300:makeup=4dB]," + limiter)
        options.audioProfile = "not-a-profile"
        XCTAssertEqual(options.audioFilters, normalizer + "," + limiter)
        options.audioNormalize = false
        XCTAssertEqual(options.audioFilters, "", "Nothing is left to limit")
    }

    func testTheChainReachesLibmpvOnlyWhenThereIsOne() {
        var options = PlaybackOptions()
        options.audioNormalize = true
        XCTAssertEqual(options.mpvOptions.filter { $0.0 == "af" }.map(\.1), [normalizer + "," + limiter])
    }

    func testSavedOptionsFromBeforeTheFiltersExistedStillDecode() throws {
        let saved = try JSONEncoder().encode(PlaybackOptions())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        object["audioNormalize"] = nil; object["audioProfile"] = nil
        var merged = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaybackOptions())) as? [String: Any])
        merged.merge(object) { _, saved in saved }
        let decoded = try JSONDecoder().decode(PlaybackOptions.self, from: JSONSerialization.data(withJSONObject: merged))
        XCTAssertFalse(decoded.audioNormalize); XCTAssertEqual(decoded.audioProfile, "off")
    }
}
