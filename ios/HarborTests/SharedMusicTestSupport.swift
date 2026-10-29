import Foundation
import Network
@testable import Harbor

@MainActor final class SharedMusicScope {
    var scope = PluginExecutionScope(owner: "owned-shared-music-" + UUID().uuidString, activation: UUID())
}
@MainActor final class SharedMusicDisk: MusicPlaylistPersistence {
    var value: MusicPlaylistDocument?
    func read(owner: String) throws -> MusicPlaylistDocument? { value }
    func write(_ value: MusicPlaylistDocument, owner: String) throws { self.value = value }
}
@MainActor final class SharedMusicPairingDisk: SubsonicPairingPersistence {
    var value: SubsonicPairing?
    func read(owner: String) throws -> SubsonicPairing? { value }
    func write(_ pairing: SubsonicPairing, owner: String) throws { value = pairing }
    func remove(owner: String) throws { value = nil }
}
actor SharedMusicGate {
    private var pending: CheckedContinuation<Void, Never>?
    func hold() async { await withCheckedContinuation { pending = $0 } }
    func waiting() -> Bool { pending != nil }
    func release() { pending?.resume(); pending = nil }
}
@MainActor final class SharedMusicResolver: MusicPlaybackResolving {
    let scope: PluginExecutionScope
    var active = true, revision = UUID()
    var gate: SharedMusicGate?
    var records: [MusicRecord] = []
    private(set) var scrobbled: [String] = []
    init(scope: PluginExecutionScope = .init(owner: "owned-shared-resolver-" + UUID().uuidString, activation: UUID())) { self.scope = scope }
    func validate() throws { if !active { throw CancellationError() } }
    func localRecord(_ track: MusicTrack) -> MusicRecord? { records.first { $0.id == track.id } }
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution {
        try validate(); let version = revision
        if track.sourceId == "slow", let gate { await gate.hold() }
        return .init(stream: .init(url: URL(string: "https://owned.example.test/" + (track.sourceId ?? "owned") + ".wav")!, httpHeaders: [:], mimeType: "audio/wav", bitrate: 0),
            valid: { [weak self] in self?.active == true && self?.revision == version })
    }
    func scrobble(_ track: MusicTrack, startedAt: UInt64) async throws { try validate(); scrobbled.append(track.id) }
}
actor SharedMusicControlledEngine: MusicAudioEngineOperating {
    private var newest: UInt64 = 0
    private var events: [MusicAudioEvent] = []
    private(set) var opened: [String] = []
    private(set) var stopped: [UInt64] = []
    func open(_ stream: MusicAudioStream, request: UInt64, volume: Double, paused: Bool) async throws {
        guard request >= newest else { throw CancellationError() }; newest = request
        opened.append(stream.url.lastPathComponent)
        events = [.started, .duration(8), .paused(paused), .loaded, .time(0.25)]
    }
    func read(request: UInt64) async -> [MusicAudioEvent] { guard request == newest else { return [] }; let value = events; events = []; return value }
    func command(_ command: MusicAudioCommand, request: UInt64) async throws {
        guard request == newest else { return }
        switch command { case .paused(let value): events.append(.paused(value)); case .seek(let value): events.append(.time(value)); case .volume(let value): events.append(.volume(value)) }
    }
    func stop(request: UInt64) async { guard request >= newest else { return }; newest = request; stopped.append(request); events = [] }
    func emit(_ value: [MusicAudioEvent]) { events += value }
}

/// Only loopback is bound. The actual URLSession/libmpv clients use owned WAV,
/// artwork and Subsonic responses, including HTTP range requests for seeking.
final class SharedMusicPublisher: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.owned.shared-music-http")
    private let lock = NSLock()
    private let audio: Data, artwork: Data
    private var captured: [String] = []
    private var started = false
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return captured }
    init(audio: Data, artwork: Data = Data()) throws {
        self.audio = audio; self.artwork = artwork
        let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                guard !started else { return }
                switch state {
                case .ready:
                    started = true
                    if let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)") { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: HarborError(code: "owned-music-publisher")) }
                case .failed(let error): started = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }; connection.start(queue: queue); receive(connection, request: Data())
            }
            listener.start(queue: queue)
        }
    }
    private func receive(_ connection: NWConnection, request: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [self] chunk, _, ended, error in
            var data = request; if let chunk { data.append(chunk) }
            guard error == nil, data.count <= 32 * 1024 else { connection.cancel(); return }
            guard data.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if ended { connection.cancel() } else { receive(connection, request: data) }; return
            }
            let text = String(decoding: data, as: UTF8.self)
            lock.lock(); captured.append(text); lock.unlock()
            let lines = text.components(separatedBy: "\r\n")
            let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let path = URLComponents(string: "http://owned.test" + target)?.path ?? "/"
            if path == "/rest/scrobble" || path == "/rest/ping" {
                send(connection, body: Data(#"{"subsonic-response":{"status":"ok"}}"#.utf8), status: 200, type: "application/json"); return
            }
            if path == "/cover.png" { send(connection, body: artwork, status: 200, type: "image/png"); return }
            if path == "/rest/stream" || path == "/audio.wav" {
                let range = lines.first { $0.lowercased().hasPrefix("range: bytes=") }
                let offset = range.flatMap { Int($0.dropFirst("range: bytes=".count).split(separator: "-", omittingEmptySubsequences: false).first ?? "") } ?? 0
                guard offset >= 0, offset < audio.count else { send(connection, body: Data(), status: 416, type: "audio/wav"); return }
                let body = Data(audio.dropFirst(offset))
                let extra = range == nil ? "" : "Content-Range: bytes \(offset)-\(audio.count - 1)/\(audio.count)\r\n"
                send(connection, body: body, status: range == nil ? 200 : 206, type: "audio/wav", extra: extra); return
            }
            send(connection, body: Data(), status: 404, type: "text/plain")
        }
    }
    private func send(_ connection: NWConnection, body: Data, status: Int, type: String, extra: String = "") {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\(extra)Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    func stop() { listener.cancel(); listener.newConnectionHandler = nil; listener.stateUpdateHandler = nil }
}
