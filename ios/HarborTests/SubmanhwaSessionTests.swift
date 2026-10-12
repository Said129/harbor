import UIKit
import WebKit
import XCTest
@testable import Harbor

final class SubmanhwaSessionTests: XCTestCase {
    @MainActor
    func testReopeningPendingAndCompletedGETPreservesNavigation() async throws {
        try await reopening(method: "GET")
    }

    @MainActor
    func testReopeningPendingAndCompletedPOSTDoesNotReplayTheForm() async throws {
        try await reopening(method: "POST")
    }

    @MainActor
    private func reopening(method: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }

        print("Submanhwa session \(method): start pending navigation")
        let server = PageServer()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(server, forURLScheme: "harbor-session")
        let session = SubmanhwaSession(configuration: configuration)
        let web = session.web
        defer { web.stopLoading(); web.navigationDelegate = nil }
        let host = UIViewController()
        let first = WebPageController(webView: web)
        window.rootViewController = host
        host.addChild(first)
        first.view.frame = host.view.bounds
        first.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(first.view)
        first.didMove(toParent: host)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        XCTAssertFalse(first.view === web, "A persistent page must not be owned as a presentation's root view")
        XCTAssertTrue(web.superview === first.view)
        let url = try XCTUnwrap(URL(string: "harbor-session://fixture/" + method.lowercased()))
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method == "POST" { request.httpBody = Data("value=fixture".utf8) }
        web.load(request)
        try await waitUntil { server.pending != nil && session.loading }
        print("Submanhwa session \(method): detach and reopen pending navigation")

        first.detach()
        print("Submanhwa session \(method): first presentation detached")
        XCTAssertNil(web.superview)
        XCTAssertNil(web.uiDelegate)
        print("Submanhwa session \(method): presentation delegate cleared")
        // The response is deliberately withheld until after the original
        // presentation is gone and the user has opened the page again.
        let second = WebPageController(webView: web)
        print("Submanhwa session \(method): second presentation created")
        await replace(first, with: second, in: host)
        print("Submanhwa session \(method): previous presentation removed")
        window.layoutIfNeeded()
        XCTAssertFalse(first.view === second.view)
        XCTAssertTrue(web.superview === second.view)
        XCTAssertEqual(web.frame, second.view.bounds)
        first.detach()
        XCTAssertTrue(web.superview === second.view, "A late detach must not remove the new presentation's page")
        XCTAssertTrue(web.uiDelegate === second)
        print("Submanhwa session \(method): second presentation installed")
        await session.openIfNeeded()
        print("Submanhwa session \(method): openIfNeeded returned without loading again")
        XCTAssertTrue(session.loading)
        XCTAssertEqual(server.methods, [method])
        XCTAssertEqual(server.stopped, 0)
        try server.complete()
        print("Submanhwa session \(method): response delivered")
        try await waitUntil { !session.loading && !web.isLoading && web.estimatedProgress == 1 }
        print("Submanhwa session \(method): response finished")
        XCTAssertNil(session.error)
        XCTAssertEqual(web.url, url)
        let initial = try await evaluate(web, "window.fixtureCounter = 42; return document.getElementById('content').textContent;")
        XCTAssertEqual(initial, "Finished")

        second.detach()
        XCTAssertNil(web.superview)
        let third = WebPageController(webView: web)
        await replace(second, with: third, in: host)
        window.layoutIfNeeded()
        XCTAssertFalse(second.view === third.view)
        XCTAssertTrue(web.superview === third.view)
        defer { third.close() }
        await session.openIfNeeded()
        let preserved = try await evaluate(web, "return String(window.fixtureCounter);")
        XCTAssertEqual(preserved, "42")
        XCTAssertEqual(server.methods, [method], "Reopening must not repeat a navigation or a submitted POST")
        XCTAssertFalse(session.loading)
        print("Submanhwa session \(method): completed page preserved without a second request")
    }

    @MainActor
    private func replace(_ old: UIViewController, with next: UIViewController, in host: UIViewController) async {
        // Match representable containment and await UIKit's actual completion,
        // rather than interrupting root-window appearance transitions.
        old.willMove(toParent: nil)
        host.addChild(next)
        next.view.frame = host.view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            host.transition(from: old, to: next, duration: 0, options: [], animations: nil) { _ in
                old.removeFromParent()
                next.didMove(toParent: host)
                continuation.resume()
            }
        }
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        guard condition() else { throw NSError(domain: "SubmanhwaSessionTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "WebKit did not reach the required navigation state"]) }
    }

    @MainActor
    private func evaluate(_ web: WKWebView, _ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result.map { $0 as? String ?? "" })
            }
        }
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
