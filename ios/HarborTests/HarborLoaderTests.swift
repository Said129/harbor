import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import Harbor

final class HarborLoaderTests: XCTestCase {
    @MainActor
    func testOriginalBundledBoatRendersAndAnimatesWithoutNetwork() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: HarborLoaderArtwork().frame(width: 128, height: 128))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        var web: WKWebView?
        var ready = false
        // A cold WebKit process may outlive document progress updates. Wait for
        // the original animation itself, rather than querying an empty page.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            web = webView(in: window)
            if let web, !web.isLoading, web.estimatedProgress == 1 {
                ready = (try? await web.evaluateJavaScript("Boolean(window.harborLoader?.isLoaded && document.querySelectorAll('#boat svg path').length > 0)")) as? Bool == true
                if ready { break }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let browser = try XCTUnwrap(web)
        XCTAssertEqual(browser.url, HarborLoaderArtwork.index)
        XCTAssertEqual(browser.configuration.websiteDataStore.isPersistent, false)
        let state = try await browser.evaluateJavaScript("JSON.stringify({ ready: document.readyState, visibility: document.visibilityState, loaded: Boolean(window.harborLoader?.isLoaded), paths: document.querySelectorAll('#boat svg path').length, bounds: document.getElementById('boat')?.getBoundingClientRect().toJSON() })")
        let diagnostic = XCTAttachment(string: "applicationState=\(UIApplication.shared.applicationState.rawValue), keyWindow=\(window.isKeyWindow), loading=\(browser.isLoading), progress=\(browser.estimatedProgress), page=\(String(describing: state))")
        diagnostic.name = "native-loader-state"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(ready, "The bundled boat must finish loading and render actual SVG paths")
        guard ready else { throw NSError(domain: "HarborLoaderTests", code: 1) }
        let hasPaths = try await browser.evaluateJavaScript("document.querySelectorAll('#boat svg path').length > 0") as? Bool
        XCTAssertEqual(hasPaths, true, "The original animation must actually render its SVG paths")
        let firstValue = try await browser.evaluateJavaScript("window.harborLoader.currentFrame")
        let first = try XCTUnwrap(firstValue as? Double)
        let firstMarkup = try await browser.evaluateJavaScript("document.querySelector('#boat svg').innerHTML")
        let firstArtwork = try XCTUnwrap(firstMarkup as? String)
        let firstImage = try await snapshot(browser)
        attach(firstImage, name: "native-loader-before")
        try await Task.sleep(for: .milliseconds(300))
        let laterValue = try await browser.evaluateJavaScript("window.harborLoader.currentFrame")
        let later = try XCTUnwrap(laterValue as? Double)
        XCTAssertNotEqual(first, later, "A static logo does not prove the desktop animation works")
        let laterMarkup = try await browser.evaluateJavaScript("document.querySelector('#boat svg').innerHTML")
        let laterArtwork = try XCTUnwrap(laterMarkup as? String)
        XCTAssertTrue(firstArtwork != laterArtwork, "The rendered artwork must move, not just its frame counter")
        let laterImage = try await snapshot(browser)
        attach(laterImage, name: "native-loader-after")
        _ = try await browser.evaluateJavaScript("window.harborLoaderMotion.stop()")
        try await Task.sleep(for: .milliseconds(300))
        let stopped = try await browser.evaluateJavaScript("window.harborLoader.currentFrame") as? Double
        XCTAssertEqual(stopped, 0, "Reduce Motion must leave the original boat still")
    }
    @MainActor private func snapshot(_ browser: WKWebView) async throws -> UIImage {
        let image: UIImage? = try await withCheckedThrowingContinuation { continuation in
            browser.takeSnapshot(with: nil) { image, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: image) }
            }
        }
        return try XCTUnwrap(image, "WebKit must supply the rendered boat image")
    }
    @MainActor private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func webView(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.compactMap { webView(in: $0) }.first
    }
}
