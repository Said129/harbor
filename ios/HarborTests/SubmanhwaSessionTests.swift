import UIKit
import WebKit
import XCTest
@testable import Harbor

final class SubmanhwaSessionTests: XCTestCase {
    @MainActor
    func testReopeningPendingAndCompletedPagesPreservesNavigationWithoutReplayingForms() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }

        for method in ["GET", "POST"] {
            let server = PageServer()
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.setURLSchemeHandler(server, forURLScheme: "harbor-session")
            let session = SubmanhwaSession(configuration: configuration)
            let web = session.web
            defer { web.stopLoading(); web.navigationDelegate = nil }
            let first = WebPageController(webView: web)
            window.rootViewController = first; window.makeKeyAndVisible()
            let url = try XCTUnwrap(URL(string: "harbor-session://fixture/" + method.lowercased()))
            var request = URLRequest(url: url)
            request.httpMethod = method
            if method == "POST" { request.httpBody = Data("value=fixture".utf8) }
            web.load(request)
            try await waitUntil { server.pending != nil && session.loading }

            first.detach()
            window.rootViewController = nil
            XCTAssertNil(web.uiDelegate)
            // The response is deliberately withheld until after the original
            // presentation is gone and the user has opened the page again.
            let second = WebPageController(webView: web)
            window.rootViewController = second
            await session.openIfNeeded()
            XCTAssertTrue(session.loading)
            XCTAssertEqual(server.methods, [method])
            XCTAssertEqual(server.stopped, 0)
            try server.complete()
            try await waitUntil { !session.loading && !web.isLoading && web.estimatedProgress == 1 }
            XCTAssertNil(session.error)
            XCTAssertEqual(web.url, url)
            let initial = try await web.evaluateJavaScript("window.fixtureCounter = 42; document.getElementById('content').textContent")
            XCTAssertEqual(initial as? String, "Finished")

            second.detach()
            window.rootViewController = nil
            let third = WebPageController(webView: web)
            window.rootViewController = third
            defer { third.close(); window.rootViewController = nil }
            await session.openIfNeeded()
            let preserved = try await web.evaluateJavaScript("window.fixtureCounter")
            XCTAssertEqual((preserved as? NSNumber)?.intValue, 42)
            XCTAssertEqual(server.methods, [method], "Reopening must not repeat a navigation or a submitted POST")
            XCTAssertFalse(session.loading)
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "WebKit did not reach the required navigation state")
    }

    @MainActor
    private final class PageServer: NSObject, WKURLSchemeHandler {
        var pending: (any WKURLSchemeTask)?
        var methods: [String] = []
        var stopped = 0
        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            methods.append(urlSchemeTask.request.httpMethod ?? "GET")
            pending = urlSchemeTask
        }
        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
            stopped += 1
            pending = nil
        }
        func complete() throws {
            let task = try XCTUnwrap(pending)
            let url = try XCTUnwrap(task.request.url)
            pending = nil
            let data = Data("<html><body><p id='content'>Finished</p></body></html>".utf8)
            task.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
            task.didReceive(data)
            task.didFinish()
        }
    }
}
