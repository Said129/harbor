import Foundation
@preconcurrency import Network

/// An owned HTTP file with real byte ranges, served only on loopback.
final class SubtitleRangeFixture: @unchecked Sendable {
    private let data: Data
    private let listener: NWListener
    private let queue = DispatchQueue(label: "owned-subtitle-ranges")
    private let lock = NSLock()
    private var ready = false
    private var connections: [NWConnection] = []
    private var starts: [Int] = []
    init(data: Data) throws {
        self.data = data
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .ready = state { locked { ready = true } }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            locked { connections.append(connection) }
            connection.start(queue: queue); receive(connection, bytes: Data())
        }
        listener.start(queue: queue)
    }
    private func locked<T>(_ operation: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return operation() }
    func start() async throws -> URL {
        for _ in 0..<200 {
            if locked({ ready }), let port = listener.port { return URL(string: "http://127.0.0.1:\(port.rawValue)/owned.mkv")! }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(domain: "owned-subtitle-server", code: 1)
    }
    var requestedOffsets: [Int] { locked { starts } }
    func stop() { listener.cancel(); let values = locked { connections }; values.forEach { $0.cancel() } }
    private func receive(_ connection: NWConnection, bytes: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] chunk, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var request = bytes; if let chunk { request.append(chunk) }
            guard request.count <= 32_768 else { connection.cancel(); return }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil { reply(connection, request: request); return }
            if complete { connection.cancel() } else { receive(connection, bytes: request) }
        }
    }
    private func reply(_ connection: NWConnection, request: Data) {
        let text = String(decoding: request, as: UTF8.self), lines = text.lowercased().components(separatedBy: "\r\n")
        let range = lines.first { $0.hasPrefix("range: bytes=") }.map { String($0.dropFirst("range: bytes=".count)) }
        let parts = range?.split(separator: "-", omittingEmptySubsequences: false)
        let start = parts?.first.flatMap { Int($0) } ?? 0
        guard start >= 0, start < data.count else { connection.cancel(); return }
        let end = min(data.count - 1, parts.flatMap { $0.count == 2 ? Int($0[1]) : nil } ?? data.count - 1)
        guard end >= start else { connection.cancel(); return }
        locked { starts.append(start) }
        let status = range == nil ? "200 OK" : "206 Partial Content"
        var header = "HTTP/1.1 \(status)\r\nContent-Type: video/x-matroska\r\nAccept-Ranges: bytes\r\nContent-Length: \(end - start + 1)\r\nConnection: close\r\n"
        if range != nil { header += "Content-Range: bytes \(start)-\(end)/\(data.count)\r\n" }
        var response = Data((header + "\r\n").utf8)
        if !lines[0].hasPrefix("head ") { response.append(data[start...end]) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
