import UIKit
import WebKit
import XCTest
@testable import Harbor

@MainActor final class SpooktoberWorldMountTests: XCTestCase {
    func testActualBundledDesktopWorldCatalogSearchBooksAndDetailRenderOfflineInBothNativeSizes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let rules = try await offlineRules()
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            let store = SpooktoberWorldStore(owner: "owned-world-" + label, persistence: OwnedSpooktoberWorldPersistence())
            var intents: [SpooktoberWorldIntent] = []
            let controller = SpooktoberWorldController(store: store, active: { true }, intent: { intents.append($0) })
            controller.start(); defer { controller.dispose() }
            let web = try XCTUnwrap(controller.webView)
            web.configuration.userContentController.add(rules)
            let host = UIViewController(); host.view.backgroundColor = .black
            window.frame = CGRect(origin: .zero, size: size); window.rootViewController = host
            web.frame = CGRect(origin: .zero, size: size); web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.addSubview(web); window.makeKeyAndVisible()
            try await ready(controller)
            try await expect(web, "root.querySelector('#catalog-search') !== null")
            try await expect(web, "root.querySelectorAll('.media-card').length > 20")
            try await expect(web, "!Array.from(root.querySelectorAll('button')).some(e => e.textContent.trim() === 'Games')")
            capture(window, "spook-world-home-" + label)
            _ = try await run(web, "root.querySelector('#catalog-title').scrollIntoView({block:'start',behavior:'instant'}); return true")
            try await Task.sleep(for: .milliseconds(350))
            capture(window, "spook-world-catalog-" + label)
            _ = try await run(web, "const field=root.querySelector('#catalog-search');field.value='Halloween';field.dispatchEvent(new Event('input',{bubbles:true}));return true")
            try await Task.sleep(for: .milliseconds(500))
            try await expect(web, "root.querySelector('#catalog-grid .media-card') !== null")
            _ = try await run(web, "root.querySelector('#catalog-grid .media-card').click();return true")
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(intents.contains { if case .media = $0 { return true }; return false })
            _ = try await run(web, "const field=root.querySelector('#catalog-search');field.value='';field.dispatchEvent(new Event('input',{bubbles:true}));root.querySelector('#catalog-type').click();return true")
            _ = try await run(web, "root.querySelector('#catalog-type-options [data-index=\"3\"]').click();return true")
            try await Task.sleep(for: .milliseconds(500))
            try await expect(web, "root.querySelector('#catalog-type').textContent.includes('Books')")
            _ = try await run(web, "root.querySelector('#catalog-title').scrollIntoView({block:'start',behavior:'instant'});return true")
            capture(window, "spook-world-books-" + label)
            _ = try await run(web, "root.querySelector('#catalog-grid .media-card').click();return true")
            try await Task.sleep(for: .milliseconds(400))
            try await expect(web, "root.querySelector('#detail').hasAttribute('open')")
            capture(window, "spook-world-book-detail-" + label)
            let handled = await controller.back(); XCTAssertTrue(handled)
            try await expect(web, "root.querySelector('#detail').hasAttribute('open')", expected: false)
            controller.dispose()
        }
    }
    func testRealWorldBridgeCannotWriteOrRouteAfterTheProfileLeaseEnds() async throws {
        let activation = OwnedSpooktoberWorldActivation(), disk = OwnedSpooktoberWorldPersistence()
        let store = SpooktoberWorldStore(owner: "owned-world-isolation", persistence: disk)
        var received = 0
        let controller = SpooktoberWorldController(store: store, active: { activation.current }, intent: { _ in received += 1 })
        controller.start(); defer { controller.dispose() }
        let web = try XCTUnwrap(controller.webView)
        web.configuration.userContentController.add(try await offlineRules())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIViewController(); window.rootViewController = host
        web.frame = window.bounds; host.view.addSubview(web); window.makeKeyAndVisible()
        try await ready(controller)
        _ = try await web.evaluateJavaScript("localStorage.setItem('spooktober-twilight-team','jacob')")
        for _ in 0..<50 {
            if store.values["spooktober-twilight-team"] == "jacob" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.values["spooktober-twilight-team"], "jacob")
        activation.current = false
        _ = try await web.evaluateJavaScript("""
        localStorage.setItem('spooktober-twilight-team','edward');
        window.webkit.messageHandlers.spooktober.postMessage(JSON.stringify({kind:'intent',message:{channel:'harbor-spooktober',intent:'playlist',id:'party'}}));
        """)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.values["spooktober-twilight-team"], "jacob"); XCTAssertEqual(received, 0)
        XCTAssertEqual(SpooktoberWorldStore(owner: store.owner, persistence: disk).values, store.values)
        controller.setVisible(false); let handled = await controller.back(); XCTAssertFalse(handled)
    }
    private func offlineRules() async throws -> WKContentRuleList {
        try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "owned-spooktober-offline",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#)
    }
    private func ready(_ controller: SpooktoberWorldController) async throws {
        for _ in 0..<650 {
            if controller.ready { try await Task.sleep(for: .milliseconds(250)); return }
            if controller.failed { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("The actual original module must load with bundled resources: " + (controller.diagnostic ?? "no ready notification"))
        throw HarborError(code: "owned-spooktober-world")
    }
    private func run(_ web: WKWebView, _ body: String) async throws -> Any? {
        try await web.callAsyncJavaScript("const root=document.getElementById('world').shadowRoot;" + body, arguments: [:], in: nil, contentWorld: .page)
    }
    private func expect(_ web: WKWebView, _ expression: String, expected: Bool = true, file: StaticString = #filePath, line: UInt = #line) async throws {
        let actual = try await run(web, "return Boolean(" + expression + ")") as? Bool ?? false
        XCTAssertEqual(actual, expected, expression, file: file, line: line)
    }
    private func capture(_ window: UIWindow, _ name: String) {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
@MainActor private final class OwnedSpooktoberWorldActivation { var current = true }
