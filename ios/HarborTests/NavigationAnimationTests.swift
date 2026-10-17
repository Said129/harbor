import CryptoKit
import Lottie
import UIKit
import XCTest
@testable import Harbor

@MainActor final class NavigationAnimationTests: XCTestCase {
    func testOriginalDesktopNavigationVectorsDecodeAndMatchPinnedHashes() throws {
        let expected = [
            "home", "catalogs", "movies", "shows", "music", "anime", "manga", "ebook", "live-tv", "playlists", "calendar", "library", "collections", "downloads", "addons", "settings"
        ]
        XCTAssertEqual(DesktopNavigationAnimation.resources, expected)
        let manifestURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "navigation-animation-hashes", withExtension: "json", subdirectory: "Fixtures"))
        let hashes = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(Set(hashes.keys), Set(expected))
        for name in expected {
            let file = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "DesktopAnimations/nav"))
            let data = try Data(contentsOf: file)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), hashes[name])
            let animation = try XCTUnwrap(LottieAnimation.named(name, bundle: .main, subdirectory: "DesktopAnimations/nav"))
            XCTAssertGreaterThan(animation.endFrame, animation.startFrame)
            XCTAssertGreaterThan(animation.framerate, 0)
        }
        XCTAssertNil(DesktopNavigationAnimation.resource(for: .search))
        XCTAssertEqual(DesktopNavigationAnimation.resource(for: .live), "live-tv")
        XCTAssertEqual(DesktopNavigationAnimation.resource(for: .vod), "playlists")
    }
    func testMotionStopsWhenDisabledReducedOrBackgroundedAndIdleNeverLoops() {
        let play = DesktopNavigationAnimation.shouldPlay
        XCTAssertTrue(play(true, false, true, true, false))
        XCTAssertTrue(play(true, false, true, false, true))
        XCTAssertFalse(play(true, false, true, false, false))
        XCTAssertFalse(play(false, false, true, true, true))
        XCTAssertFalse(play(true, true, true, true, true))
        XCTAssertFalse(play(true, false, false, true, true))
    }
    func testOriginalHomeVectorRendersDifferentNativeFrames() throws {
        let animation = try XCTUnwrap(LottieAnimation.named("home", bundle: .main, subdirectory: "DesktopAnimations/nav"))
        let view = LottieAnimationView(animation: animation, configuration: LottieConfiguration(renderingEngine: .mainThread))
        view.frame = CGRect(x: 0, y: 0, width: 256, height: 256); view.contentMode = .scaleAspectFit
        var frames: [Data] = []
        for progress in [0.0, 0.35, 0.7] {
            view.currentProgress = progress; view.forceDisplayUpdate(); view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: view.bounds.size).image { view.layer.render(in: $0.cgContext) }
            frames.append(try XCTUnwrap(image.pngData()))
            let capture = XCTAttachment(image: image); capture.name = "original-desktop-home-vector-\(progress)"; capture.lifetime = .keepAlways; add(capture)
        }
        XCTAssertGreaterThan(Set(frames).count, 1, "The native renderer must preserve the actual animated geometry")
    }
}
