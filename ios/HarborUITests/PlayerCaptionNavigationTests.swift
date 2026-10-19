import Foundation
import Network
import XCTest
import UIKit
import CryptoKit

@MainActor final class PlayerCaptionNavigationTests: XCTestCase {
    func testActualIPhonePlayerShowsAbsoluteNinetyNineAndAdvancesToOneHundred() async throws { try await verifyPlayer(device: "iphone") }
    func testActualIPadPlayerShowsAbsoluteNinetyNineAndAdvancesToOneHundred() async throws { try await verifyPlayer(device: "ipad") }

    private func verifyPlayer(device: String) async throws {
        continueAfterFailure = false
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "synthetic-player-caption", withExtension: "mp4", subdirectory: "Fixtures"))
        let server = try CaptionAddonServer(clip: Data(contentsOf: file))
        defer { server.stop() }
        try await server.start()
        let app = XCUIApplication()
        app.launchArguments = ["-uiLanguage", "es", "-nativeGuide.initialized.v1", "YES", "-nativeGuide.completed.v1", "YES"]
        app.launch(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["main-menu"].waitForExistence(timeout: 45))
        let card = app.buttons.matching(NSPredicate(format: "identifier == 'continue-watching-resume' AND label == 'Continuar viendo Dragon Ball Super'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let home = app.scrollViews["home-scroll"]
        for _ in 0..<8 { if card.isHittable { break }; home.swipeUp() }
        XCTAssertTrue(card.isHittable)
        // Tap without waiting for the card's metadata presentation. The real
        // detail/resume path must supply the player's episode presentation.
        card.tap()
        try await showPlayer(app)
        XCUIDevice.shared.orientation = .landscapeLeft
        try await verifyCaption("T1 · E99", app: app)
        XCTAssertTrue(server.paths.contains("/stream/series/tt4644488:5:23.json"))
        XCTAssertTrue(server.paths.contains { $0.hasPrefix("/clip/") })
        try await capture(app, server: server, name: "synthetic-player-\(device)-episode-99")
        let next = app.buttons["player-next-episode"]
        XCTAssertTrue(next.exists)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: next)
        let nextEnabled = await XCTWaiter.fulfillment(of: [enabled], timeout: 15)
        XCTAssertEqual(nextEnabled, .completed)
        next.tap()
        let nextRequest = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.paths.contains("/stream/series/tt4644488:5:24.json") }, object: nil)
        let requestedNext = await XCTWaiter.fulfillment(of: [nextRequest], timeout: 30)
        XCTAssertEqual(requestedNext, .completed)
        try await showPlayer(app)
        try await verifyCaption("T1 · E100", app: app)
        XCTAssertTrue(server.paths.contains("/stream/series/tt4644488:5:24.json"))
        try await capture(app, server: server, name: "synthetic-player-\(device)-episode-100")
    }
    private func showPlayer(_ app: XCUIApplication) async throws {
        let surface = app.buttons["player-surface"]
        if !surface.waitForExistence(timeout: 30) {
            // The rotated player can already be above the disabled source
            // picker. Never try to activate that background button.
            if !app.buttons["player-close"].exists {
                let offer = app.buttons["stream-offer"].firstMatch
                XCTAssertTrue(offer.waitForExistence(timeout: 15)); XCTAssertTrue(offer.isEnabled); offer.tap()
            }
        }
        XCTAssertTrue(surface.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Preparado'"), object: surface)
        let rendered = await XCTWaiter.fulfillment(of: [ready], timeout: 30)
        XCTAssertEqual(rendered, .completed, "A rendered frame is required, not only an opened player")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "player-error").firstMatch.exists)
        let pause = app.buttons["player-pause"]
        if !pause.exists || !pause.isHittable { surface.tap() }
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        if pause.label == "Pausar" { pause.tap() }
    }
    private func verifyCaption(_ text: String, app: XCUIApplication) async throws {
        let caption = app.staticTexts["player-episode-caption"]
        let correct = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND hittable == true", text), object: caption)
        let result = await XCTWaiter.fulfillment(of: [correct], timeout: 45)
        XCTAssertEqual(result, .completed)
    }
    private func capture(_ app: XCUIApplication, server: CaptionAddonServer, name: String) async throws {
        let deadline = Date().addingTimeInterval(15)
        while app.frame.width <= app.frame.height && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        let caption = app.staticTexts["player-episode-caption"]
        XCTAssertTrue(caption.isHittable)
        let orientation: String
        switch XCUIDevice.shared.orientation {
        case .landscapeLeft: orientation = "landscapeLeft"
        case .landscapeRight: orientation = "landscapeRight"
        default: throw URLError(.cannotDecodeContentData)
        }
        let token = try server.requestCapture(name: name, app: app.frame, caption: caption.frame, orientation: orientation)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in server.captureReceipt(token) != nil }, object: nil)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 45)
        XCTAssertEqual(result, .completed, "The host must preserve a real full-display PNG before advancing")
        guard result == .completed, let receipt = server.captureReceipt(token) else { throw URLError(.timedOut) }
        XCTAssertGreaterThan(receipt.displayWidth, receipt.displayHeight); XCTAssertGreaterThan(receipt.displayHeight, 100)
        let geometry = XCTAttachment(string: "token=\(token); app=\(app.frame); caption=\(caption.frame); pixels=\(receipt.width)x\(receipt.height); display=\(receipt.displayWidth)x\(receipt.displayHeight); display_rotation=\(receipt.rotation); device_orientation=\(orientation); png_sha256=\(receipt.sha256)")
        geometry.name = name + "-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        let attachment = XCTAttachment(data: receipt.png, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

/// Ordinary Stremio addon and real HTTP byte ranges, bound to loopback only.
private final class CaptionAddonServer: @unchecked Sendable {
    struct CaptureRequest: Codable {
        let token: String
        let name: String
        let app: [Double]
        let caption: [Double]
        let deviceOrientation: String
    }
    struct CaptureReceipt {
        let width: Int; let height: Int; let rotation: Int; let sha256: String; let png: Data
        var displayWidth: Int { rotation == 0 ? width : height }
        var displayHeight: Int { rotation == 0 ? height : width }
    }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.player-caption-fixture")
    private let lock = NSLock()
    private let clip: Data
    private var received: [String] = []
    private var pendingCapture: CaptureRequest?
    private var captured: [String: CaptureReceipt] = [:]
    private var connections: [UUID: NWConnection] = [:] // Serial queue only.
    private var startupFinished = false // Serial queue only.
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return received }
    func requestCapture(name: String, app: CGRect, caption: CGRect, orientation: String) throws -> String {
        guard name.range(of: #"^synthetic-player-(iphone|ipad)-episode-(99|100)$"#, options: .regularExpression) != nil,
              ["landscapeLeft", "landscapeRight"].contains(orientation), app.width > app.height, app.height > 0,
              app.contains(caption), caption.width > 0, caption.height > 0 else { throw URLError(.badURL) }
        lock.lock(); defer { lock.unlock() }
        guard pendingCapture == nil else { throw URLError(.resourceUnavailable) }
        let token = UUID().uuidString
        pendingCapture = CaptureRequest(token: token, name: name,
            app: [Double(app.minX), Double(app.minY), Double(app.width), Double(app.height)],
            caption: [Double(caption.minX), Double(caption.minY), Double(caption.width), Double(caption.height)], deviceOrientation: orientation)
        return token
    }
    func captureReceipt(_ token: String) -> CaptureReceipt? { lock.lock(); defer { lock.unlock() }; return captured[token] }
    init(clip: Data) throws {
        self.clip = clip
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: 48192)!)
        listener = try NWListener(using: parameters)
    }
    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [self] state in
                guard !startupFinished else { return }
                switch state {
                case .ready: startupFinished = true; continuation.resume(returning: ())
                case .failed(let error): startupFinished = true; continuation.resume(throwing: error)
                case .cancelled: startupFinished = true; continuation.resume(throwing: URLError(.cancelled))
                default: break
                }
            }
            listener.newConnectionHandler = { [self] connection in
                guard connections.count < 8 else { connection.cancel(); return }
                let id = UUID(); connections[id] = connection
                connection.start(queue: queue); receive(connection, id: id, request: Data())
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 10) { [self] in
                guard !startupFinished else { return }
                startupFinished = true; continuation.resume(throwing: URLError(.timedOut)); listener.cancel()
            }
        }
    }
    private func receive(_ connection: NWConnection, id: UUID, request: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, ended, error in
            var request = request; if let data { request.append(data) }
            guard error == nil, request.count <= 16 * 1024 * 1024 + 16 * 1024 else { close(connection, id: id); return }
            guard let headers = request.range(of: Data("\r\n\r\n".utf8)), headers.upperBound <= 16 * 1024 else {
                if ended || request.count > 16 * 1024 { close(connection, id: id) } else { receive(connection, id: id, request: request) }; return
            }
            let lines = String(decoding: request[..<headers.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let first = (lines.first ?? "").components(separatedBy: " ")
            guard first.count >= 2, ["GET", "HEAD", "POST"].contains(first[0]) else { close(connection, id: id); return }
            let path = (first[1].components(separatedBy: "?").first ?? "").removingPercentEncoding ?? first[1]
            if first[0] == "POST" {
                guard path.hasPrefix("/qa/ack/"),
                      let raw = lines.first(where: { $0.lowercased().hasPrefix("content-length:") }),
                      let size = Int(raw.dropFirst("Content-Length:".count).trimmingCharacters(in: .whitespaces)), (32...16 * 1024 * 1024).contains(size) else { close(connection, id: id); return }
                if request.count < headers.upperBound + size {
                    if ended { close(connection, id: id) } else { receive(connection, id: id, request: request) }; return
                }
                guard request.count == headers.upperBound + size else { close(connection, id: id); return }
            }
            lock.lock(); received.append(path); lock.unlock()
            if path == "/qa/capture" {
                lock.lock(); let pending = pendingCapture; lock.unlock()
                let data = pending.flatMap { try? JSONEncoder().encode($0) } ?? Data("null".utf8)
                respond(connection, id: id, status: 200, type: "application/json", length: data.count, body: first[0] == "HEAD" ? Data() : data)
            } else if path.hasPrefix("/qa/ack/") {
                let token = String(path.dropFirst("/qa/ack/".count))
                let query = URLComponents(string: "http://127.0.0.1:48192" + first[1])?.queryItems ?? []
                let fields = Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
                let png = Data(request[headers.upperBound...])
                guard first[0] == "POST", UUID(uuidString: token) != nil,
                      let width = Int(fields["width"] ?? ""), let height = Int(fields["height"] ?? ""),
                      (101...16384).contains(width), (101...16384).contains(height), let rotation = Int(fields["rotation"] ?? ""),
                      let sha = fields["sha256"], sha.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      png.count >= 32, png.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
                      png[16..<20].reduce(0, { $0 << 8 | Int($1) }) == width,
                      png[20..<24].reduce(0, { $0 << 8 | Int($1) }) == height,
                      SHA256.hash(data: png).map({ String(format: "%02x", $0) }).joined() == sha else {
                    respond(connection, id: id, status: 400, type: "text/plain", length: 0, body: Data()); return
                }
                lock.lock()
                let pending = pendingCapture
                let accepted = pending?.token == token && pending.map { Self.captureRotation(width: width, height: height, request: $0) == rotation } == true
                if accepted { captured[token] = CaptureReceipt(width: width, height: height, rotation: rotation, sha256: sha, png: png); pendingCapture = nil }
                lock.unlock()
                respond(connection, id: id, status: accepted ? 200 : 409, type: "text/plain", length: 0, body: Data())
            } else if path.hasPrefix("/clip/") {
                sendClip(connection, id: id, head: first[0] == "HEAD", range: lines.first { $0.lowercased().hasPrefix("range:") })
            } else if path.hasPrefix("/stream/series/tt4644488:"), path.hasSuffix(".json") {
                let video = path.dropFirst("/stream/series/".count).dropLast(5)
                let components = video.split(separator: ":")
                guard components.count == 3, let season = Int(components[1]), let episode = Int(components[2]), season == 5, [23, 24].contains(episode) else {
                    respond(connection, id: id, status: 404, type: "text/plain", length: 0, body: Data()); return
                }
                let filename = String(format: "Dragon.Ball.Super.S%02dE%02d.1080p.Synthetic.Fixture.mp4", season, episode)
                let body: [String: Any] = ["streams": [["name": "1080p · Owned synthetic test clip", "title": filename + "\nOwned synthetic clip, not anime footage", "url": "http://127.0.0.1:48192/clip/\(video).mp4", "behaviorHints": ["bingeGroup": "harbor-synthetic-caption"]]]]
                sendJSON(body, connection: connection, id: id, head: first[0] == "HEAD")
            } else if path == "/manifest.json" {
                sendJSON(["id": "harbor.synthetic.caption", "version": "1.0.0", "name": "Owned synthetic test clip", "types": ["series"], "catalogs": [], "resources": [["name": "stream", "types": ["series"], "idPrefixes": ["tt4644488"]]]], connection: connection, id: id, head: first[0] == "HEAD")
            } else { respond(connection, id: id, status: 404, type: "text/plain", length: 0, body: Data()) }
        }
    }
    private static func captureRotation(width: Int, height: Int, request: CaptureRequest) -> Int? {
        let ratio = request.app[2] / request.app[3]
        if width > height, abs(Double(width) / Double(height) - ratio) < 0.03 { return 0 }
        if height > width, abs(Double(height) / Double(width) - ratio) < 0.03 {
            if request.deviceOrientation == "landscapeLeft" { return -90 }
            if request.deviceOrientation == "landscapeRight" { return 90 }
        }
        return nil
    }
    private func sendJSON(_ object: [String: Any], connection: NWConnection, id: UUID, head: Bool) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { close(connection, id: id); return }
        respond(connection, id: id, status: 200, type: "application/json", length: data.count, body: head ? Data() : data)
    }
    private func sendClip(_ connection: NWConnection, id: UUID, head: Bool, range: String?) {
        var start = 0, end = clip.count - 1
        if let range {
            let value = String(range.dropFirst("Range:".count)).trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("bytes="), !value.contains(",") else { invalidRange(connection, id: id); return }
            let parts = String(value.dropFirst(6)).components(separatedBy: "-")
            guard parts.count == 2 else { invalidRange(connection, id: id); return }
            if parts[0].isEmpty, let suffix = Int(parts[1]), suffix > 0 { start = max(0, clip.count - suffix) }
            else if let value = Int(parts[0]), value >= 0 {
                start = value
                if !parts[1].isEmpty {
                    guard let value = Int(parts[1]), value >= 0 else { invalidRange(connection, id: id); return }; end = min(end, value)
                }
            } else { invalidRange(connection, id: id); return }
            guard start < clip.count, end >= start else { invalidRange(connection, id: id); return }
        }
        let length = end - start + 1
        let extra = "Accept-Ranges: bytes\r\n" + (range == nil ? "" : "Content-Range: bytes \(start)-\(end)/\(clip.count)\r\n")
        respond(connection, id: id, status: range == nil ? 200 : 206, type: "video/mp4", length: length, body: head ? Data() : clip.subdata(in: start..<(end + 1)), extra: extra)
    }
    private func invalidRange(_ connection: NWConnection, id: UUID) {
        respond(connection, id: id, status: 416, type: "text/plain", length: 0, body: Data(), extra: "Content-Range: bytes */\(clip.count)\r\n")
    }
    private func respond(_ connection: NWConnection, id: UUID, status: Int, type: String, length: Int, body: Data, extra: String = "") {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\n\(extra)Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [self] _ in close(connection, id: id) })
    }
    private func close(_ connection: NWConnection, id: UUID) { connections.removeValue(forKey: id); connection.cancel() }
    func stop() {
        listener.cancel()
        queue.async { [self] in
            listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil
            let pending = connections; connections = [:]
            for connection in pending.values { connection.cancel() }
        }
    }
}
