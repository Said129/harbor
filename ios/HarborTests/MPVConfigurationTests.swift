import Libmpv
import XCTest
@testable import Harbor

final class MPVConfigurationTests: XCTestCase {
    func testProductionOptionsInitializeTheEmbeddedPlayer() throws {
        let handle = try XCTUnwrap(mpv_create())
        defer { mpv_terminate_destroy(handle) }
        for (name, value) in MPVConfiguration.options {
            XCTAssertGreaterThanOrEqual(mpv_set_option_string(handle, name, value), 0, "Required option: \(name)")
        }
        XCTAssertGreaterThanOrEqual(mpv_initialize(handle), 0)
        // No source is loaded: this verifies the actual native configuration,
        // independently of network availability or media playback.
    }
}
