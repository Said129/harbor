import XCTest
@testable import Harbor

final class MPVConfigurationTests: XCTestCase {
    @MainActor
    func testProductionOptionsInitializeTheEmbeddedPlayer() throws {
        let handle = try MPVConfiguration.createHandle()
        defer { MPVConfiguration.destroy(handle) }
        // No source is loaded: this verifies the actual native configuration,
        // independently of network availability or media playback. Calls enter
        // the app host's factory; the test does not link a second media stack.
    }
}
