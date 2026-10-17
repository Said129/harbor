import UIKit
import WebKit
import XCTest
@testable import Harbor

final class SubmanhwaAdBlockerTests: XCTestCase {
    @MainActor
    func testWebKitHidesAdContainersWithoutRemovingReaderOrLoginContent() async throws {
        let rules = try await SubmanhwaAdBlocker.contentRules()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(rules)
        let web = WKWebView(frame: .zero, configuration: configuration)
        let controller = WebPageController(webView: web)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { controller.close(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let html = """
        <html><body>
        <div class="home-ad"><div class="home-ad-label">Advertisement</div><div class="ads-large">Banner</div></div>
        <div class="ads-sqre1">Ad</div><div class="ads-sqre2">Ad</div>
        <main id="reader"><img id="page" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7" /></main>
        <form id="login"><input name="username" value="fixture"/><input type="password" name="password"/></form>
        <button id="gacha" onclick="this.textContent='ready'">Gacha</button>
        <script>localStorage.setItem('harbor-ad-test', 'kept'); document.getElementById('gacha').click();</script>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://submanhwa.com/"))
        try await loaded(web, host: "submanhwa.com")
        let hidden = try await evaluate(web, """
        return ['.home-ad', '.ads-large', '.ads-sqre1', '.ads-sqre2'].every(selector => getComputedStyle(document.querySelector(selector)).display === 'none')
            && getComputedStyle(document.getElementById('reader')).display !== 'none'
            && document.getElementById('page').complete && document.getElementById('page').naturalWidth === 1
            && document.querySelector('#login [name=username]').value === 'fixture'
            && !!document.querySelector('#login [type=password]')
            && document.getElementById('gacha').textContent === 'ready'
            && localStorage.getItem('harbor-ad-test') === 'kept';
        """)
        XCTAssertTrue(hidden, "The actual WebKit rules must hide ads while preserving reader images, forms, scripts and site storage")

        // Cosmetic names are site-specific; they must not hide an unrelated
        // website's content when an explicit external link is followed.
        web.loadHTMLString(html, baseURL: URL(string: "https://example.org/"))
        try await loaded(web, host: "example.org")
        let visible = try await evaluate(web, "return getComputedStyle(document.querySelector('.home-ad')).display !== 'none';")
        XCTAssertTrue(visible)
    }

    @MainActor
    func testPopunderPolicyPreservesSameSiteActionsAndExplicitExternalLinks() {
        for address in ["https://poweredby.jads.co/js/jads.js", "https://js.juicyads.com/jp.php", "https://massive-hall.com/", "https://ads.doubleclick.net/"] {
            XCTAssertTrue(SubmanhwaAdBlocker.blocks(URL(string: address)))
            XCTAssertFalse(SubmanhwaAdBlocker.allowsNewWindow(URL(string: address), navigation: .linkActivated))
        }
        for address in ["https://submanhwa.com/", "https://w1.submanhwa.com/", "https://challenges.cloudflare.com/", "https://fonts.googleapis.com/", "https://juicyads.com.example.org/"] {
            XCTAssertFalse(SubmanhwaAdBlocker.blocks(URL(string: address)), "Domain matching must not block site assets, authentication or similarly named hosts")
        }
        XCTAssertTrue(SubmanhwaAdBlocker.allowsNewWindow(URL(string: "https://submanhwa.com/gacha"), navigation: .other))
        XCTAssertTrue(SubmanhwaAdBlocker.allowsNewWindow(URL(string: "https://discord.gg/"), navigation: .linkActivated))
        XCTAssertFalse(SubmanhwaAdBlocker.allowsNewWindow(URL(string: "https://unknown-popup.example/"), navigation: .other))
        XCTAssertFalse(SubmanhwaAdBlocker.allowsNewWindow(URL(string: "https://submanhwa.com.example.org/"), navigation: .other))
    }

    @MainActor
    private func loaded(_ web: WKWebView, host: String) async throws {
        let deadline = Date().addingTimeInterval(30)
        while (web.isLoading || web.estimatedProgress < 1 || web.url?.host != host) && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(web.isLoading)
        XCTAssertEqual(web.estimatedProgress, 1)
        XCTAssertEqual(web.url?.host, host)
    }

    @MainActor
    private func evaluate(_ web: WKWebView, _ script: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result.map { $0 as? Bool ?? false })
            }
        }
    }
}
