import XCTest
@testable import Harbor

/// Desktop `hideContent.adult` is on by default; the iPhone toggle writes the same key that the stream options read.
@MainActor final class F9ContentFilterTests: XCTestCase {
    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAdultStreamsAreHiddenWhenNoChoiceIsSaved() {
        let defaults = freshDefaults("F9ContentFilterTests.default")
        XCTAssertTrue(HarborPluginStreamOptions.current(defaults: defaults).hideAdult)
        defaults.removePersistentDomain(forName: "F9ContentFilterTests.default")
    }

    func testSavingTheToggleOffShowsAdultStreams() {
        let name = "F9ContentFilterTests.off"
        let defaults = freshDefaults(name)
        defaults.set(false, forKey: "hideContent.adult")
        XCTAssertFalse(HarborPluginStreamOptions.current(defaults: defaults).hideAdult)
        defaults.removePersistentDomain(forName: name)
    }
}
