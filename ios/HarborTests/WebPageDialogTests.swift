import UIKit
import WebKit
import XCTest
@testable import Harbor

final class WebPageDialogTests: XCTestCase {
    @MainActor private final class Response {
        var calls = 0
        var result = false
        var failure: Error?
    }
    @MainActor
    func testClosingBrowserCancelsSiteDialogsAndUnblocksJavaScript() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }

        for script in ["return confirm('Guardar cambios') === false", "return prompt('Nombre', 'Harbor') === null", "alert('Error del sitio'); return true"] {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let web = WKWebView(frame: .zero, configuration: configuration)
            let controller = WebPageController(webView: web)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { controller.close(); window.rootViewController = nil }
            web.loadHTMLString("<p>Harbor</p>", baseURL: URL(string: "https://example.org/"))
            // A cold simulator can take over 17 seconds to launch WebContent.
            let loadDeadline = Date().addingTimeInterval(30)
            while (web.isLoading || web.estimatedProgress < 1 || web.url?.host != "example.org"), Date() < loadDeadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertFalse(web.isLoading)
            XCTAssertEqual(web.estimatedProgress, 1)
            XCTAssertEqual(web.url?.host, "example.org")

            let response = Response()
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { value in
                switch value {
                case .success(let value): response.result = value as? Bool ?? false
                case .failure(let error): response.failure = error
                }
                response.calls += 1
            }
            let dialogDeadline = Date().addingTimeInterval(5)
            while controller.presentedViewController == nil, Date() < dialogDeadline { try await Task.sleep(for: .milliseconds(50)) }
            let dialog = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
            XCTAssertEqual(dialog.title, "example.org", "A website dialog must identify the page that controls its content")
            controller.close()
            controller.close()
            let completionDeadline = Date().addingTimeInterval(5)
            while response.calls == 0, Date() < completionDeadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertEqual(response.calls, 1, "Closing a browser twice must complete its pending JavaScript dialog exactly once")
            XCTAssertNil(response.failure)
            XCTAssertTrue(response.result, "Closing must cancel confirmations/prompts rather than accepting the website action")
        }
    }
}
