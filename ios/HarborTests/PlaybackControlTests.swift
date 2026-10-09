import AVKit
import GLKit
import UIKit
import XCTest
@testable import Harbor

// Exercise the real mpv clock and AVKit presentation, including a paused first
// frame. Renderer-only coverage cannot detect a floating-window start failure.
@available(iOS, deprecated: 12.0)
final class PlaybackControlTests: XCTestCase {
    @MainActor
    func testPausedResumeAndBackwardJumpReachTheRequestedPosition() async throws {
        let (window, previous, controller, state, surface) = try player()
        defer { controller.close(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await wait(surface, state: state) { state.loaded && state.paused && state.duration > 29 }
        let generation = state.mediaGeneration
        let resumed = try await controller.seekForResume(7_000)
        XCTAssertEqual(resumed, 7_000)
        try await wait(surface, state: state) { abs(state.position - 7) < 0.2 }
        controller.seekRelative(10)
        try await wait(surface, state: state) { abs(state.position - 17) < 0.2 }
        controller.seekRelative(-10)
        try await wait(surface, state: state) { abs(state.position - 7) < 0.2 }
        XCTAssertTrue(state.paused)
        XCTAssertEqual(state.mediaGeneration, generation)

        // Desktop restarts near the end; the returned checkpoint must describe
        // that actual start, rather than saving the stale near-end timestamp.
        let restarted = try await controller.seekForResume(28_000)
        XCTAssertEqual(restarted, 0)
        try await wait(surface, state: state) { state.position < 0.2 }
        XCTAssertEqual(state.mediaGeneration, generation)
        XCTAssertNil(state.error)
    }

    @MainActor
    func testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession() async throws {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { throw XCTSkip("AVKit does not support PiP on this test destination") }
        let (window, previous, controller, state, surface) = try player()
        defer { controller.close(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try await wait(surface, state: state) { state.loaded && state.paused && state.tracks.contains { $0.type == "video" && $0.selected } }
        XCTAssertTrue(state.pictureInPictureSupported)
        let generation = state.mediaGeneration
        controller.togglePictureInPicture()
        try await wait(nil, state: state, timeout: 18) { !state.pictureInPictureChanging }
        XCTAssertNil(state.playbackIssue)
        XCTAssertTrue(state.pictureInPictureActive, "AVKit must actually enter PiP, rather than merely prepare its renderer")
        guard state.pictureInPictureActive else { return }
        XCTAssertNotNil(controller.sampleFrame, "Paused playback still needs a first decoded frame")
        XCTAssertTrue(state.paused)
        XCTAssertEqual(state.mediaGeneration, generation)
        try await controller.seekForPictureInPicture(2)
        try await wait(nil, state: state) { abs(state.position - 2) < 0.2 }
        controller.togglePictureInPicture()
        try await wait(surface, state: state) { !state.pictureInPictureActive && !state.pictureInPictureChanging && controller.sampleFrame == nil && controller.canRestartPlayback }
        XCTAssertTrue(state.paused)
        XCTAssertEqual(state.mediaGeneration, generation)
        XCTAssertNil(state.error)
    }

    @MainActor
    func testPlaybackRequestsLandscapeAndRestoresAfterTheLastPresentation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = OrientationController()
        window.makeKeyAndVisible()
        try await wait(nil, state: nil) { scene.interfaceOrientation != .unknown }
        let initial = scene.interfaceOrientation
        let connecting = PlayerOrientation.begin(in: window)
        let playback = PlayerOrientation.begin(in: window)
        defer {
            PlayerOrientation.end(connecting); PlayerOrientation.end(playback)
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
        }
        try await wait(nil, state: nil) { scene.interfaceOrientation.isLandscape }
        XCTAssertEqual(PlayerOrientation.supportedOrientations(for: window), .landscape)
        PlayerOrientation.end(connecting)
        XCTAssertTrue(scene.interfaceOrientation.isLandscape)
        XCTAssertEqual(PlayerOrientation.supportedOrientations(for: window), .landscape)
        PlayerOrientation.end(playback)
        try await wait(nil, state: nil) { scene.interfaceOrientation == initial }
        XCTAssertEqual(PlayerOrientation.supportedOrientations(for: window), .allButUpsideDown)
    }

    @MainActor
    private func player() throws -> (UIWindow, UIWindow?, MPVController, PlayerState, GLKView) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let video = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "render-8bit", withExtension: "mp4", subdirectory: "Fixtures"))
        let state = PlayerState()
        let controller = MPVController(source: .init(url: video.absoluteString, headers: nil, subtitles: nil, via: "test-fixture"), state: state, startPaused: true)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.layoutIfNeeded()
        return (window, previous, controller, state, try XCTUnwrap(controller.view as? GLKView))
    }

    @MainActor
    private func wait(_ surface: GLKView?, state: PlayerState?, timeout: Double = 12, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            surface?.display()
            if let error = state?.error { XCTFail(error); throw HarborError(code: "player-not-ready") }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertTrue(condition(), "The native playback transition did not complete within its deadline")
    }
}

@MainActor
private final class OrientationController: UIViewController {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { PlayerOrientation.supportedOrientations(for: viewIfLoaded?.window) }
}
