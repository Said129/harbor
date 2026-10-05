import XCTest
@testable import Harbor

final class MPVConfigurationTests: XCTestCase {
    @MainActor
    func testProductionOptionsInitializeTheEmbeddedPlayer() throws {
        // No source is loaded: this verifies the actual native configuration,
        // independently of network availability or media playback. Calls enter
        // the app host's factory; the test does not link a second media stack.
        for mode in [HardwareDecoding.auto, .off] {
            let handle = try MPVConfiguration.createHandle(decoding: mode, playback: PlaybackOptions())
            MPVConfiguration.destroy(handle)
        }
        var options = PlaybackOptions()
        options.fit = .fill; options.speed = 1.5; options.audioLanguage = "spa,es"
        options.audioDelay = -0.3; options.subtitleDelay = 0.4
        options.subtitleStyle = "box"; options.subtitleASS = "force"
        options.subtitleFont = "rounded"; options.subtitleSpacing = 3
        options.hideSDH = true; options.subtitleBoxColor = "#102030"
        options.bufferSize = .medium
        options.brightness = 4; options.gamma = 12
        let configured = try MPVConfiguration.createHandle(decoding: .off, playback: options)
        MPVConfiguration.destroy(configured)
    }
}
