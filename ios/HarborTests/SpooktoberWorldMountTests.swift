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
        true;
        """)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.values["spooktober-twilight-team"], "jacob"); XCTAssertEqual(received, 0)
        XCTAssertEqual(SpooktoberWorldStore(owner: store.owner, persistence: disk).values, store.values)
        controller.setVisible(false); let handled = await controller.back(); XCTAssertFalse(handled)
    }
    func testRealWorldThemeFontsRTLAndSixPlaylistMarksMatchExecutedDesktopStatesAfterCardReplacement() async throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "spooktober-indicator-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: fixtureURL))
        XCTAssertEqual(fixture["actual_original_indicator_and_mark_executed"], .bool(true))
        XCTAssertEqual(fixture["original_modules"].objectValue.count, 2); XCTAssertEqual(fixture["cases"].array.count, 16)
        let palette: [String: [Double]] = ["canvas": [0.04,0.05,0.06,1], "ink": [0.94,0.93,0.91,1],
            "ink-muted": [0.60,0.60,0.61,1], "ink-faint": [0.39,0.39,0.40,1], "accent": [0.97,0.13,0.43,1],
            "surface": [0.08,0.09,0.10,1], "elevated": [0.13,0.14,0.15,1], "raised": [0.17,0.18,0.19,1], "removed": [0,0,0,1]]
        let initial = SpooktoberWorldAppearance(palette: palette, font: "system", language: "en", showIMDb: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let rules = try await offlineRules()
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            let activation = OwnedSpooktoberWorldActivation()
            let store = SpooktoberWorldStore(owner: "owned-world-theme-" + label, persistence: OwnedSpooktoberWorldPersistence())
            let controller = SpooktoberWorldController(store: store, appearance: initial, active: { activation.current }, intent: { _ in })
            controller.start(); defer { controller.dispose() }
            let web = try XCTUnwrap(controller.webView); web.configuration.userContentController.add(rules)
            let host = UIViewController(); host.view.backgroundColor = .black
            window.frame = CGRect(origin: .zero, size: size); window.rootViewController = host
            web.frame = CGRect(origin: .zero, size: size); web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.view.addSubview(web); window.makeKeyAndVisible()
            try await ready(controller)
            try await expect(web, "document.documentElement.lang === 'en' && document.documentElement.dir === 'ltr'")
            try await expect(web, "root.querySelectorAll('style[data-harbor-theme]').length === 1")
            try await expect(web, "Array.from(document.fonts).filter(f=>['SpookJakarta','SpookNightmare'].includes(f.family)).filter(f=>f.status==='loaded').length === 2")
            try await expect(web, "getComputedStyle(root.querySelector('.spook-native-body')).backgroundColor === 'rgb(10, 13, 15)'")
            try await expect(web, "getComputedStyle(root.querySelector('.hero-imdb')).display !== 'none'")
            try await expect(web, "Array.from(root.querySelectorAll('.playlist-card')).map(c=>c.dataset.playlist).sort().join(',') === 'dark,darkpop,emo,goth,party,scores'")
            for row in fixture["cases"].array {
                let phase = try XCTUnwrap(SpooktoberWorldMusicState.Phase(rawValue: row["phase"].string ?? ""))
                controller.setVisible(row["active"] == .bool(true))
                controller.updateMusicState(.init(trackId: row["trackId"].string, originKind: row["originKind"].string, originId: row["originId"].string, phase: phase))
                let result = try await run(web, """
                const card=root.querySelector('.playlist-card[aria-current="true"]');
                const outer=card?.querySelector('.spook-playlist-playing');const mark=outer?.querySelector('.music-live-mark');
                return JSON.stringify({playlist:card?.dataset.playlist??null,paused:outer?.hasAttribute('data-paused')??false,
                  loading:mark?.hasAttribute('data-loading')??false,bars:mark?.querySelectorAll('.music-eq-bars i').length??0,
                  spinner:!!mark?.querySelector('svg'),label:mark?.getAttribute('aria-label')??null});
                """)
                let raw = try XCTUnwrap(result as? String)
                let actual = try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)), expected = row["expected"]
                for field in ["playlist","paused","loading","bars","spinner"] { XCTAssertEqual(actual[field], expected[field], field + " in " + phase.rawValue) }
                XCTAssertEqual(actual["label"].string, expected["labelKey"].string.flatMap { initial.labels[$0] })
                if phase == .paused, expected["playlist"].string != nil {
                    try await expect(web, "getComputedStyle(root.querySelector('.spook-playlist-playing .music-eq-bars i')).animationPlayState === 'paused'")
                }
            }
            controller.setVisible(true)
            controller.updateMusicState(.init(trackId: "owned-track", originKind: "playlist", originId: "spooktober:party", phase: .playing))
            _ = try await run(web, """
            const old=root.querySelector('.playlist-card[data-playlist="party"]');const fresh=old.cloneNode(true);
            fresh.removeAttribute('aria-current');fresh.querySelector('.spook-playlist-playing')?.remove();old.replaceWith(fresh);return true;
            """)
            try await Task.sleep(for: .milliseconds(80))
            try await expect(web, "root.querySelectorAll('.playlist-card[aria-current=\"true\"]').length===1 && root.querySelectorAll('.spook-playlist-playing').length===1")
            _ = try await run(web, "root.querySelector('.playlist-card[data-playlist=\"party\"]').scrollIntoView({block:'center',behavior:'instant'});return true")
            try await Task.sleep(for: .milliseconds(180)); capture(window, "spook-world-playing-" + label)
            var light = palette; light["removed"] = nil; light["canvas"] = [0.95,0.93,0.90,1]
            light["ink"] = [0.12,0.14,0.16,1]; light["ink-muted"] = [0.38,0.40,0.42,1]
            light["surface"] = [0.88,0.87,0.84,1]; light["elevated"] = [0.83,0.82,0.79,1]
            let arabic = SpooktoberWorldAppearance(palette: light, font: "inter", language: "ar", showIMDb: false)
            controller.updateAppearance(arabic)
            controller.updateMusicState(.init(trackId: "owned-track", originKind: "playlist", originId: "spooktober:party", phase: .resolving))
            try await expect(web, "document.documentElement.lang==='ar' && document.documentElement.dir==='rtl'")
            try await expect(web, "document.documentElement.style.getPropertyValue('--color-removed') === ''")
            try await expect(web, "getComputedStyle(root.querySelector('.hero-imdb')).display === 'none'")
            try await expect(web, "getComputedStyle(root.querySelector('.spook-native-body')).fontFamily.includes('SpookJakarta')")
            try await expect(web, "root.querySelector('.spook-playlist-playing .music-live-mark').getAttribute('aria-label') === 'جارٍ تحميل الموسيقى'")
            try await expect(web, "root.querySelector('.spook-playlist-playing svg').getAttribute('viewBox')==='0 0 24 24' && root.querySelectorAll('.spook-playlist-playing svg path').length===2")
            try await expect(web, "Array.from(root.querySelectorAll('.spook-playlist-playing svg path')).every(p=>p.getAttribute('stroke')==='currentColor')")
            try await Task.sleep(for: .milliseconds(180)); capture(window, "spook-world-rtl-resolving-" + label)
            controller.setVisible(false)
            controller.updateAppearance(initial)
            try await expect(web, "document.documentElement.lang==='ar' && !root.querySelector('.spook-playlist-playing')")
            controller.setVisible(true)
            try await expect(web, "document.documentElement.lang==='en' && root.querySelector('.spook-playlist-playing')!==null")
            activation.current = false
            controller.updateAppearance(arabic); controller.updateMusicState(.idle)
            XCTAssertEqual(controller.appearance, initial); XCTAssertEqual(controller.musicState.phase, .resolving)
            controller.setVisible(false)
            try await expect(web, "!root.querySelector('.spook-playlist-playing') && !root.querySelector('[aria-current=\"true\"]')")
            controller.dispose()
        }
    }
    private func offlineRules() async throws -> WKContentRuleList {
        let rule = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "owned-spooktober-offline",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#)
        return try XCTUnwrap(rule, "The offline world case requires an actual compiled HTTP blocking rule")
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
