import Foundation
import Network
@testable import Harbor

final class LastFmMusicFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.owned.lastfm")
    private let lock = NSLock()
    private let authDelay: Double
    private var started = false
    private var captured: [[String: String]] = []
    private var connections: [NWConnection] = []
    private var failing = false
    var requests: [[String: String]] { locked { captured } }
    func failScrobbles() { locked { failing = true } }
    init(authDelay: Double = 0) throws {
        self.authDelay = authDelay
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    private func locked<T>(_ value: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return value() }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                guard !self.started else { return }
                switch state {
                case .ready:
                    self.started = true
                    if let port = self.listener.port { continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/2.0/")!) }
                    else { continuation.resume(throwing: HarborError(code: "owned-lastfm-server")) }
                case .failed(let error): self.started = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.locked { self.connections.append(connection) }
                connection.start(queue: self.queue); self.receive(connection, bytes: Data())
            }
            listener.start(queue: queue)
        }
    }
    func stop() {
        listener.cancel(); listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil
        let values = locked { connections }; values.forEach { $0.cancel() }
    }
    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] chunk, _, ended, error in
            guard let self, error == nil else { connection.cancel(); return }
            var data = bytes; if let chunk { data.append(chunk) }
            guard data.count <= 128 * 1024 else { connection.cancel(); return }
            guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
                if ended { connection.cancel() } else { self.receive(connection, bytes: data) }; return
            }
            let header = String(decoding: data[..<boundary.lowerBound], as: UTF8.self)
            let lines = header.components(separatedBy: "\r\n")
            let length = lines.first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
            guard length > 0, data.count - boundary.upperBound >= length else {
                if ended { connection.cancel() } else { self.receive(connection, bytes: data) }; return
            }
            let body = String(decoding: data[boundary.upperBound...], as: UTF8.self)
            let items = URLComponents(string: "http://owned.invalid/?" + body.replacingOccurrences(of: "+", with: "%20"))?.queryItems ?? []
            let fields = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
            self.locked { self.captured.append(fields) }
            guard header.hasPrefix("POST /2.0/ "), fields["api_key"] == "key", fields["format"] == "json", fields["api_sig"]?.count == 32 else {
                self.send(connection, json: #"{"error":6}"#); return
            }
            switch fields["method"] {
            case "auth.getToken": self.send(connection, json: #"{"token":"owned-auth-token"}"#)
            case "auth.getSession":
                self.queue.asyncAfter(deadline: .now() + self.authDelay) { [weak self] in
                    self?.send(connection, json: #"{"session":{"name":"Owned Listener","key":"owned-session-key"}}"#)
                }
            case "track.scrobble":
                self.send(connection, json: self.locked { self.failing } ? #"{"error":9,"message":"Owned rejected session"}"# : #"{"scrobbles":{"@attr":{"accepted":1}}}"#)
            default: self.send(connection, json: #"{"error":3}"#)
            }
        }
    }
    private func send(_ connection: NWConnection, json: String) {
        let body = Data(json.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Only this test transport rewrites the fixed provider URL to an owned
/// loopback server. Production requests retain public-only HTTPS and no redirect.
actor OwnedLastFmNetwork: HarborNativeNetworkCalling {
    let endpoint: URL
    private(set) var requests: [HarborNetworkRequest] = []
    init(endpoint: URL) { self.endpoint = endpoint }
    func perform(_ request: HarborNetworkRequest) async throws -> HarborNetworkResponse {
        requests.append(request)
        guard request.url == "https://ws.audioscrobbler.com/2.0/", request.method == "POST",
              request.publicNetworkOnly, !request.followRedirects, request.strictLimit else { throw HarborError(code: "owned-lastfm-policy") }
        let routed = HarborNetworkRequest(url: endpoint.absoluteString, method: request.method, headers: request.headers,
            bodyBase64: request.bodyBase64, timeoutMs: request.timeoutMs, followRedirects: false,
            maxResponseBytes: request.maxResponseBytes, strictLimit: true, publicNetworkOnly: false, allowLocalNetwork: true)
        let response = try await HarborNativeNetwork().perform(routed)
        return .init(status: response.status, ok: response.ok, headers: response.headers, bodyBase64: response.bodyBase64, url: request.url)
    }
}
