import Foundation
import Network
@testable import Harbor

/// An owned Jellyfin music endpoint; no public server or user account is needed.
final class JellyfinMusicFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.owned.jellyfin-http")
    private let lock = NSLock()
    private let audio: Data
    private let authDelay: Double
    private var captured: [String] = []
    private var started = false
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return captured }
    init(audio: Data, authDelay: Double = 0) throws {
        self.audio = audio; self.authDelay = authDelay
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
                    if let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/jellyfin") { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: HarborError(code: "owned-jellyfin-publisher")) }
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
            guard error == nil, data.count <= 128 * 1024 else { connection.cancel(); return }
            guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
                if ended { connection.cancel() } else { receive(connection, request: data) }; return
            }
            let header = String(decoding: data[..<boundary.lowerBound], as: UTF8.self)
            let lines = header.components(separatedBy: "\r\n")
            let length = lines.first { $0.lowercased().hasPrefix("content-length:") }.flatMap { Int($0.dropFirst(15).trimmingCharacters(in: .whitespaces)) } ?? 0
            guard data.count - boundary.upperBound >= length else {
                if ended { connection.cancel() } else { receive(connection, request: data) }; return
            }
            let text = String(decoding: data, as: UTF8.self)
            lock.lock(); captured.append(text); lock.unlock()
            let target = lines.first?.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let components = URLComponents(string: "http://owned.test" + target)
            let path = components?.path ?? "/"
            let parameters = Dictionary(components?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { first, _ in first })
            if path == "/jellyfin/System/Info/Public" { json(connection, #"{"ServerName":"Owned music"}"#); return }
            if path == "/jellyfin/Users/AuthenticateByName" {
                queue.asyncAfter(deadline: .now() + authDelay) { [self] in json(connection, #"{"AccessToken":"owned-token","User":{"Id":"u1","Name":"Owned listener"}}"#) }; return
            }
            guard header.contains("Token=\"owned-token\"") || parameters["ApiKey"] == "owned-token" else { send(connection, body: Data(), status: 401, type: "text/plain"); return }
            if path == "/jellyfin/UserViews" { json(connection, #"{"Items":[{"Id":"lib1","CollectionType":"music"}]}"#); return }
            if path.hasSuffix("/PlaybackInfo") {
                json(connection, #"{"MediaSources":[{"Id":"m1","Container":"wav","Bitrate":128000,"SupportsDirectPlay":true,"SupportsDirectStream":true}],"PlaySessionId":"ownedps1"}"#); return
            }
            if path.hasPrefix("/jellyfin/Sessions/Playing") { send(connection, body: Data(), status: 204, type: "application/json"); return }
            if path == "/jellyfin/Audio/a1/universal" {
                let range = lines.first { $0.lowercased().hasPrefix("range: bytes=") }
                let offset = range.flatMap { Int($0.dropFirst("range: bytes=".count).split(separator: "-", omittingEmptySubsequences: false).first ?? "") } ?? 0
                guard offset >= 0, offset < audio.count else { send(connection, body: Data(), status: 416, type: "audio/wav"); return }
                let extra = range == nil ? "" : "Content-Range: bytes \(offset)-\(audio.count - 1)/\(audio.count)\r\n"
                send(connection, body: Data(audio.dropFirst(offset)), status: range == nil ? 200 : 206, type: "audio/wav", extra: extra); return
            }
            if path == "/jellyfin/Items" || path == "/jellyfin/Playlists/p1/Items" || path.hasSuffix("/InstantMix") {
                let kinds = parameters["includeItemTypes"] ?? "Audio"
                let items: String
                if kinds.contains(",") { items = Self.song + "," + Self.album + "," + Self.artist + "," + Self.playlist }
                else { switch kinds { case "MusicAlbum": items = Self.album; case "MusicArtist": items = Self.artist; case "Playlist": items = Self.playlist; default: items = Self.song } }
                json(connection, "{\"Items\":[" + items + "]}"); return
            }
            if path == "/jellyfin/Items/r1" { json(connection, Self.artist); return }
            if path == "/jellyfin/Items/a1" { json(connection, Self.song); return }
            send(connection, body: Data(), status: 404, type: "text/plain")
        }
    }
    private static let song = #"{"Id":"a1","Name":"Owned tone","Type":"Audio","Artists":["Owned artist"],"Album":"Owned album","RunTimeTicks":80000000}"#
    private static let album = #"{"Id":"b1","Name":"Owned album","Type":"MusicAlbum","AlbumArtist":"Owned artist","ChildCount":1}"#
    private static let artist = #"{"Id":"r1","Name":"Owned artist","Type":"MusicArtist"}"#
    private static let playlist = #"{"Id":"p1","Name":"Owned playlist","Type":"Playlist","ChildCount":1}"#
    private func json(_ connection: NWConnection, _ text: String) { send(connection, body: Data(text.utf8), status: 200, type: "application/json") }
    private func send(_ connection: NWConnection, body: Data, status: Int, type: String, extra: String = "") {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\(extra)Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    func stop() { listener.cancel(); listener.newConnectionHandler = nil; listener.stateUpdateHandler = nil }
}
