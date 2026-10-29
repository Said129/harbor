import SwiftUI
import UIKit
import XCTest
@testable import Harbor

@MainActor final class MusicServerConnectionMountTests: XCTestCase {
    func testProductionPrivateServerFormAndConnectedStateMountInBothNativeSizes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let oldLanguage = UserDefaults.standard.object(forKey: "uiLanguage")
        UserDefaults.standard.set("en", forKey: "uiLanguage")
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKey()
            if let oldLanguage { UserDefaults.standard.set(oldLanguage, forKey: "uiLanguage") } else { UserDefaults.standard.removeObject(forKey: "uiLanguage") }
        }
        for (label, size) in [("compact", CGSize(width: 390, height: 844)), ("regular", CGSize(width: 834, height: 1194))] {
            for connected in [false, true] {
                let scope = PluginExecutionScope(owner: "owned-server-interface-" + label, activation: UUID())
                let disk = MountedServerDisk()
                if connected { disk.pairing = .salted(baseUrl: "https://owned.example.test", username: "Owned listener", password: "owned", salt: "owned") }
                let service = SubsonicMusicService(scope: scope, currentScope: { scope }, transport: MountedServerNoNetwork(), persistence: disk)
                let host = UIHostingController(rootView: MusicServerConnectionView(service: service) { XCTFail("A read-only mount must not change the connection") }
                    .environment(\.locale, Locale(identifier: "en")).environment(\.layoutDirection, .leftToRight)
                    .environment(\.horizontalSizeClass, size.width > 600 ? .regular : .compact).preferredColorScheme(.dark))
                window.frame = CGRect(origin: .zero, size: size); window.rootViewController = host; window.makeKeyAndVisible()
                window.frame = CGRect(origin: .zero, size: size); host.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded(); host.view.layoutIfNeeded()
                XCTAssertEqual(host.view.bounds.width, size.width, accuracy: 1)
                XCTAssertEqual(host.view.bounds.height, size.height, accuracy: 1)
                XCTAssertEqual(service.configured, connected)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds, format: format).image { _ in
                    XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "music-server-" + (connected ? "connected-" : "form-") + label
                attachment.lifetime = .keepAlways; add(attachment)
                service.dispose()
            }
        }
    }
}
@MainActor private final class MountedServerDisk: SubsonicPairingPersistence {
    var pairing: SubsonicPairing?
    func read(owner: String) throws -> SubsonicPairing? { pairing }
    func write(_ pairing: SubsonicPairing, owner: String) throws { XCTFail("Mount must not write credentials") }
    func remove(owner: String) throws { XCTFail("Mount must not remove credentials") }
}
private struct MountedServerNoNetwork: MusicServiceHTTPTransport {
    func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse { XCTFail("Mount must not contact any music service"); throw SubsonicMusicError.network }
}
