import XCTest
import UIKit
@testable import Harbor

@MainActor private final class SyntheticProfilePlayback: ProfilePlaybackControlling {
    var closes = 0
    func close() { closes += 1 }
}
@MainActor final class ProfilePlaybackRegistryTests: XCTestCase {
    func testProfileChangeStopsEveryRegisteredSurfaceAndRejectsLateCreation() {
        let registry = ProfilePlaybackRegistry(), first = SyntheticProfilePlayback(), second = SyntheticProfilePlayback()
        let previous = registry.generation
        XCTAssertTrue(registry.register(first, generation: previous)); XCTAssertTrue(registry.register(second, generation: previous))
        registry.stopForProfileChange()
        XCTAssertEqual(first.closes, 1); XCTAssertEqual(second.closes, 1)
        XCTAssertNotEqual(registry.generation, previous)
        let late = SyntheticProfilePlayback()
        XCTAssertFalse(registry.register(late, generation: previous)); XCTAssertEqual(late.closes, 1)
        registry.stopForProfileChange(); XCTAssertEqual(first.closes, 1); XCTAssertEqual(second.closes, 1)
    }
    func testRegistrationDoesNotRetainAClosedOrReleasedSurface() {
        let registry = ProfilePlaybackRegistry()
        var released: SyntheticProfilePlayback? = SyntheticProfilePlayback()
        weak var weakReleased = released
        XCTAssertTrue(registry.register(released!, generation: registry.generation))
        released = nil; XCTAssertNil(weakReleased)
        let removed = SyntheticProfilePlayback()
        XCTAssertTrue(registry.register(removed, generation: registry.generation)); registry.remove(removed)
        registry.stopForProfileChange(); XCTAssertEqual(removed.closes, 0)
    }
    func testAControllerRejectedBeforeViewCreationCannotInitializePlaybackLater() {
        let registry = ProfilePlaybackRegistry(), stale = registry.generation
        registry.stopForProfileChange()
        let state = PlayerState()
        let controller = MPVController(source: .init(url: "https://example.invalid/should-never-load.mp4", headers: nil, subtitles: nil, via: "fixture"), state: state)
        XCTAssertFalse(registry.register(controller, generation: stale))
        controller.loadViewIfNeeded()
        XCTAssertTrue(type(of: controller.view!) == UIView.self)
        XCTAssertNil(state.controller); XCTAssertFalse(state.loaded); XCTAssertFalse(state.renderReady)
        XCTAssertEqual(state.renderCalls, 0); XCTAssertNil(state.error); XCTAssertFalse(state.pictureInPictureSupported)
    }
}
