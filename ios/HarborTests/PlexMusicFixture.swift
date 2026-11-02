import Foundation
import Network
@testable import Harbor

/// An owned Plex music endpoint; no public server or user account is needed.
final class PlexMusicFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "harbor.owned.plex-http")
    private let lock = NSLock()
    private let audio: Data
    private let artwork: Data
    private let authDelay: Double
    private var captured: [String] = []
    private var started = false
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return captured }
    init(audio: Data, artwork: Data = Data(), authDelay: Double = 0) throws {
        self.audio = audio; self.artwork = artwork; self.authDelay = authDelay
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
                    else { continuation.resume(throwing: HarborError(code: "owned-plex-publisher")) }
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
            guard header.lowercased().contains("x-plex-token: owned-plex-token") || parameters["X-Plex-Token"] == "owned-plex-token" else { send(connection, body: Data(), status: 401, type: "text/plain"); return }
            if path == "/library/sections" {
                queue.asyncAfter(deadline: .now() + authDelay) { [self] in json(connection, #"{"MediaContainer":{"Directory":[{"key":"3","type":"artist","uuid":"owned-library"}]}}"#) }; return
            }
            if path == "/photo/:/transcode" { send(connection, body: artwork, status: 200, type: "image/png"); return }
            if path == "/hubs/search" || path == "/hubs/sections/3" {
                json(connection, "{\"MediaContainer\":{\"Hub\":[" +
                     "{\"title\":\"Owned tracks\",\"hubIdentifier\":\"owned-tracks\",\"type\":\"track\",\"Metadata\":[" + Self.song + "]}," +
                     "{\"title\":\"Owned albums\",\"hubIdentifier\":\"owned-albums\",\"type\":\"album\",\"Metadata\":[" + Self.album + "]}," +
                     "{\"title\":\"Owned artists\",\"hubIdentifier\":\"owned-artists\",\"type\":\"artist\",\"Metadata\":[" + Self.artist + "]}," +
                     "{\"title\":\"Owned playlists\",\"hubIdentifier\":\"owned-playlists\",\"type\":\"playlist\",\"Metadata\":[" + Self.playlist + "]}," +
                     "{\"title\":\"Owned stations\",\"hubIdentifier\":\"owned-stations\",\"context\":\"station\",\"type\":\"playlist\",\"Metadata\":[" + Self.station + "]}]}}"); return
            }
            if path == "/library/metadata/1" {
                json(connection, "{\"MediaContainer\":{\"Metadata\":[" + Self.songWithMedia + "]}}"); return
            }
            if path == "/library/metadata/2/children" || path == "/library/sections/3/all" || path == "/playlists/7/items" || path == "/library/metadata/5/station/2" {
                json(connection, "{\"MediaContainer\":{\"Metadata\":[" + Self.song + "]}}"); return
            }
            if path == "/library/parts/1/file.wav" {
                let range = lines.first { $0.lowercased().hasPrefix("range: bytes=") }
                let offset = range.flatMap { Int($0.dropFirst("range: bytes=".count).split(separator: "-", omittingEmptySubsequences: false).first ?? "") } ?? 0
                guard offset >= 0, offset < audio.count else { send(connection, body: Data(), status: 416, type: "audio/wav"); return }
                let extra = range == nil ? "" : "Content-Range: bytes \(offset)-\(audio.count - 1)/\(audio.count)\r\n"
                send(connection, body: Data(audio.dropFirst(offset)), status: range == nil ? 200 : 206, type: "audio/wav", extra: extra); return
            }
            send(connection, body: Data(), status: 404, type: "text/plain")
        }
    }
    private static let song = #"{"ratingKey":"1","type":"track","title":"Owned tone","grandparentTitle":"Owned artist","parentTitle":"Owned album","duration":8000,"thumb":"/library/metadata/1/thumb/1"}"#
    private static let songWithMedia = String(song.dropLast()) + #", "Media":[{"bitrate":128,"audioCodec":"pcm","container":"wav","Part":[{"key":"/library/parts/1/file.wav","container":"wav"}]}]}"#
    private static let album = #"{"ratingKey":"2","type":"album","title":"Owned album","parentTitle":"Owned artist","leafCount":1,"thumb":"/library/metadata/2/thumb/1"}"#
    private static let artist = #"{"ratingKey":"5","type":"artist","title":"Owned artist","thumb":"/library/metadata/5/thumb/1"}"#
    private static let playlist = #"{"ratingKey":"7","type":"playlist","title":"Owned playlist","leafCount":1,"composite":"/playlists/7/composite/1"}"#
    private static let station = #"{"key":"/library/metadata/5/station/2","type":"playlist","title":"Owned station","thumb":"/library/metadata/5/thumb/1"}"#
    private func json(_ connection: NWConnection, _ text: String) { send(connection, body: Data(text.utf8), status: 200, type: "application/json") }
    private func send(_ connection: NWConnection, body: Data, status: Int, type: String, extra: String = "") {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\n\(extra)Connection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
    func stop() { listener.cancel(); listener.newConnectionHandler = nil; listener.stateUpdateHandler = nil }
}
