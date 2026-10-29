import Foundation
import Observation

struct MusicServiceHTTPResponse: Sendable { let status: Int; let data: Data }
protocol MusicServiceHTTPTransport: Sendable { func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse }
struct URLSessionMusicServiceTransport: MusicServiceHTTPTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()
    func perform(_ request: URLRequest) async throws -> MusicServiceHTTPResponse {
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SubsonicMusicError.network }
        return .init(status: response.statusCode, data: data)
    }
}
@MainActor protocol SubsonicPairingPersistence {
    func read(owner: String) throws -> SubsonicPairing?
    func write(_ pairing: SubsonicPairing, owner: String) throws
    func remove(owner: String) throws
}
@MainActor struct KeychainSubsonicPairing: SubsonicPairingPersistence {
    private func key(_ owner: String) -> String { "music-subsonic-pairing-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> SubsonicPairing? { try KeychainStore().read(key(owner), as: SubsonicPairing.self)?.loaded() }
    func write(_ pairing: SubsonicPairing, owner: String) throws { try KeychainStore().write(pairing, key: key(owner)) }
    func remove(owner: String) throws { try KeychainStore().remove(key(owner)) }
}

@MainActor @Observable final class SubsonicMusicService {
    let scope: PluginExecutionScope
    private var storedPairing: SubsonicPairing?
    var pairing: SubsonicPairing? { !disposed && scope == currentScope() ? storedPairing : nil }
    private(set) var health = MusicSourceCandidate.Health.unknown
    private(set) var storageFailure = false
    private(set) var credentialVersion = UUID()
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let transport: any MusicServiceHTTPTransport
    @ObservationIgnored private let persistence: any SubsonicPairingPersistence
    @ObservationIgnored private let newSalt: @MainActor () -> String
    @ObservationIgnored private var disposed = false
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope,
         transport: any MusicServiceHTTPTransport = URLSessionMusicServiceTransport(),
         persistence: (any SubsonicPairingPersistence)? = nil,
         newSalt: @escaping @MainActor () -> String = { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)) }) {
        self.scope = scope; self.currentScope = currentScope; self.transport = transport
        self.persistence = persistence ?? KeychainSubsonicPairing(); self.newSalt = newSalt
        do { storedPairing = try self.persistence.read(owner: scope.owner)?.loaded() }
        catch { storageFailure = true }
    }
    var connectionStatus: String { pairing == nil ? (storageFailure ? "error" : "disconnected") : health == .offline ? "error" : "connected" }
    var configured: Bool { pairing != nil && !disposed && scope == currentScope() }
    func dispose() { disposed = true; storedPairing = nil; credentialVersion = UUID() }
    private func validate(_ version: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope() else { dispose(); throw CancellationError() }
        if let version, version != credentialVersion { throw CancellationError() }
    }
    private func require() throws -> SubsonicPairing { try validate(); guard let pairing else { throw SubsonicMusicError.disconnected }; return pairing }
    private func send(_ url: URL, method: String = "GET", body: Data? = nil, version: UUID) async throws -> MusicServiceHTTPResponse {
        try validate(version)
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
        request.setValue("Harbor/1.0", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        do { let result = try await transport.perform(request); try validate(version); return result }
        catch { try validate(version); if error is CancellationError { throw error }; throw SubsonicMusicError.network }
    }
    private func call(_ method: String, pairing: SubsonicPairing, parameters: [(String,String)] = [], version: UUID) async throws -> SubsonicBody {
        let result = try await send(pairing.endpoint(method, parameters: parameters, json: true), version: version)
        guard (200...299).contains(result.status) else { throw SubsonicMusicError.http(result.status) }
        let body: SubsonicBody
        do { body = try await Self.decodeBody(result.data) }
        catch { try validate(version); throw error }
        try validate(version)
        guard body.status == "ok" else {
            if let error = body.error { throw SubsonicMusicError.api(error.code, error.message) }; throw SubsonicMusicError.rejected
        }
        return body
    }
    nonisolated private static func decodeBody(_ data: Data) async throws -> SubsonicBody {
        try Task.checkCancellation()
        do { return try JSONDecoder().decode(SubsonicEnvelope.self, from: data).response }
        catch { throw SubsonicMusicError.unreadable }
    }
    private func outcome<T: Sendable>(_ version: UUID, operation: @MainActor () async throws -> T) async throws -> T {
        do { let value = try await operation(); try validate(version); health = .healthy; return value }
        catch { try validate(version); if let error = error as? SubsonicMusicError { health = error.health }; throw error }
    }
    func connect(address: String, username: String, password: String) async throws {
        try validate()
        for (value,label) in [(address,"address"),(username,"username"),(password,"password")] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SubsonicMusicError.field(label) }
        }
        let bases = try SubsonicPairing.bases(address)
        credentialVersion = UUID(); let version = credentialVersion
        try await outcome(version) {
            var connected: SubsonicPairing?, last: Error = SubsonicMusicError.network
            for base in bases {
                do { connected = try await pair(base: base, username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password, version: version); break }
                catch { try validate(version); if error is CancellationError { throw error }; last = error }
            }
            guard let connected else { throw last }; try validate(version)
            do { try persistence.write(connected, owner: scope.owner) }
            catch { storageFailure = true; throw SubsonicMusicError.storage }
            storedPairing = connected; storageFailure = false
        }
    }
    private func pair(base: String, username: String, password: String, version: UUID) async throws -> SubsonicPairing {
        var exchanged: SubsonicPairing?
        if let url = URL(string: base + "/auth/login") {
            do {
                let data = try JSONEncoder().encode(["username":username,"password":password])
                let response = try await send(url, method: "POST", body: data, version: version)
                if (200...299).contains(response.status), let login = try? JSONDecoder().decode(SubsonicAuthLogin.self, from: response.data),
                   let salt = login.subsonicSalt, salt.utf8.count >= 6, let token = login.subsonicToken, token.utf8.count == 32 {
                    exchanged = .init(baseUrl: base, username: login.username ?? username, salt: salt, token: token)
                }
            } catch { try validate(version); if error is CancellationError { throw error } }
        }
        let result = exchanged ?? SubsonicPairing.salted(baseUrl: base, username: username, password: password, salt: newSalt())
        _ = try await call("ping", pairing: result, version: version); return result
    }
    func disconnect() throws {
        try validate(); credentialVersion = UUID()
        do { try persistence.remove(owner: scope.owner) }
        catch { storageFailure = true; throw SubsonicMusicError.storage }
        storedPairing = nil; storageFailure = false; health = .unknown
    }
    func resolve(_ track: MusicTrack) async throws -> MusicAudioStream {
        let paired = try require(), version = credentialVersion
        return try await outcome(version) {
            let id = try SubsonicPairing.safeID(track.sourceId ?? track.id)
            let url = try paired.endpoint("stream", parameters: [("id",id),("format","raw")])
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.call("scrobble", pairing: paired, parameters: [("id",id),("submission","false")], version: version)
            }
            return .init(url: url, httpHeaders: [:], mimeType: "audio/*", bitrate: 0)
        }
    }
    func scrobble(_ track: MusicTrack, startedAtMilliseconds: UInt64?) async throws {
        let paired = try require(), version = credentialVersion, id = try SubsonicPairing.safeID(track.sourceId ?? track.id)
        var parameters = [("id",id),("submission",startedAtMilliseconds == nil ? "false" : "true")]
        if let time = startedAtMilliseconds { parameters.append(("time",String(time))) }
        _ = try await call("scrobble", pairing: paired, parameters: parameters, version: version)
    }
    func submitScrobble(_ track: MusicTrack, startedAtSeconds: UInt64) async throws -> Bool {
        try validate()
        guard track.connectorId == "subsonic", pairing != nil else { return false }
        let (milliseconds, overflow) = startedAtSeconds.multipliedReportingOverflow(by: 1000)
        try await scrobble(track, startedAtMilliseconds: overflow ? .max : milliseconds); return true
    }
    private func searchBody(_ query: String, artists: Int, albums: Int, songs: Int, pairing: SubsonicPairing, version: UUID) async throws -> SubsonicSearch? {
        try await call("search3", pairing: pairing, parameters: [("query",query),("artistCount",String(artists)),("albumCount",String(albums)),("songCount",String(songs))], version: version).searchResult3
    }
    func searchTracks(_ query: String, limit: Int = 24) async throws -> [MusicTrack] {
        try validate(); let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.utf8.count <= 200 else { throw SubsonicMusicError.searchLength }; if query.isEmpty { return [] }
        let paired = try require(), version = credentialVersion
        return try await outcome(version) {
            let body = try await searchBody(query, artists: 0, albums: 0, songs: min(100,max(1,limit)), pairing: paired, version: version)
            return body?.song.map { $0.recording(paired) } ?? []
        }
    }
    func search(_ query: String, limit: Int = 24) async throws -> MusicCatalogSearch {
        try validate(); let query = query.trimmingCharacters(in: .whitespacesAndNewlines), limit = min(100,max(1,limit))
        guard query.utf8.count <= 200 else { throw SubsonicMusicError.searchLength }
        if query.isEmpty { return .init(top: nil, tracks: [], albums: [], artists: [], playlists: []) }
        let paired = try require(), version = credentialVersion
        return try await outcome(version) {
            let body = try await searchBody(query, artists: limit, albums: limit, songs: limit, pairing: paired, version: version)
            let tracks = body?.song.map { $0.recording(paired) } ?? [], albums = body?.album.map { $0.reference(paired) } ?? []
            return .init(top: tracks.first.map(MusicCatalogItem.track) ?? albums.first.map(MusicCatalogItem.album), tracks: tracks, albums: albums, artists: body?.artist.map { $0.reference(paired) } ?? [], playlists: [])
        }
    }
    private func batches(_ requests: [(String,[(String,String)])], pairing: SubsonicPairing, version: UUID) async throws -> [Result<SubsonicBody,SubsonicMusicError>?] {
        let values = await withTaskGroup(of: (Int,Result<SubsonicBody,SubsonicMusicError>?).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask { @MainActor in
                    do { return (index,.success(try await self.call(request.0, pairing: pairing, parameters: request.1, version: version))) }
                    catch is CancellationError { return (index,nil) }
                    catch { return (index,.failure(error as? SubsonicMusicError ?? .unreadable)) }
                }
            }
            var values = [Result<SubsonicBody,SubsonicMusicError>?](repeating: nil, count: requests.count)
            for await (index, value) in group { values[index] = value }
            return values
        }
        try validate(version); return values
    }
    private func ordered(_ songs: [SubsonicSong]) -> [SubsonicSong] {
        songs.enumerated().sorted {
            let a = $0.element, b = $1.element
            if (a.discNumber ?? 1) != (b.discNumber ?? 1) { return (a.discNumber ?? 1) < (b.discNumber ?? 1) }
            if (a.track ?? 0) != (b.track ?? 0) { return (a.track ?? 0) < (b.track ?? 0) }
            return $0.offset < $1.offset
        }.map(\.element)
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] {
        let paired = try require(), version = credentialVersion, id = try SubsonicPairing.safeID(album.id)
        return try await outcome(version) {
            let body = try await call("getAlbum", pairing: paired, parameters: [("id",id)], version: version)
            return ordered(body.album?.values ?? []).map { $0.recording(paired) }
        }
    }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] {
        let paired = try require(), version = credentialVersion, id = try SubsonicPairing.safeID(artist.id)
        return try await outcome(version) {
            let body = try await call("getArtist", pairing: paired, parameters: [("id",id)], version: version)
            let requests = (body.artist?.values ?? []).prefix(4).map { ("getAlbum",[("id",$0.id)]) }
            let albums = try await batches(Array(requests), pairing: paired, version: version)
            var tracks: [MusicTrack] = [], failure: SubsonicMusicError?
            for album in albums {
                switch album {
                case .some(.success(let value)): tracks += ordered(value.album?.values ?? []).map { $0.recording(paired) }
                case .some(.failure(let error)): failure = error
                case nil: break
                }
            }
            if tracks.isEmpty, let failure { throw failure }; return Array(tracks.prefix(30))
        }
    }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] {
        let paired = try require(), version = credentialVersion, id = try SubsonicPairing.safeID(playlist.id)
        return try await outcome(version) {
            let body = try await call("getPlaylist", pairing: paired, parameters: [("id",id)], version: version)
            return (body.playlist?.values ?? []).map { $0.recording(paired) }
        }
    }
    func home() async throws -> [MusicCatalogRow] {
        try validate(); guard let paired = pairing else { return [] }; let version = credentialVersion
        return try await outcome(version) {
            let requests: [(String,[(String,String)])] = [
                ("getAlbumList2",[("type","newest"),("size","24")]),
                ("getAlbumList2",[("type","frequent"),("size","24")]),
                ("getAlbumList2",[("type","random"),("size","24")]),
                ("getStarred2",[]),("getArtists",[]),("getPlaylists",[])
            ]
            let ids = ["newest","frequent","random","starred","artists","playlists"]
            let titles = ["serverNewest","serverFrequent","serverRandom","serverStarred","serverArtists","serverPlaylists"]
            let replies = try await batches(requests, pairing: paired, version: version)
            var rows: [MusicCatalogRow] = [], failure: SubsonicMusicError?
            for (index, reply) in replies.enumerated() {
                switch reply {
                case .some(.failure(let error)): failure = error
                case .some(.success(let body)):
                    let items: [MusicCatalogItem], layout: MusicCatalogLayout
                    switch index {
                    case 0...2: items = (body.albumList2?.values ?? []).map { .album($0.reference(paired)) }; layout = .covers
                    case 3: items = (body.starred2?.values ?? []).prefix(24).map { .track($0.recording(paired)) }; layout = .trackGrid
                    case 4: items = (body.artists?.values ?? []).flatMap(\.values).prefix(24).map { .artist($0.reference(paired)) }; layout = .circles
                    default: items = (body.playlists?.values ?? []).prefix(24).map { .playlist($0.reference(paired)) }; layout = .covers
                    }
                    if !items.isEmpty { rows.append(.init(id: "subsonic:home:" + ids[index], title: "music.row." + titles[index], titleLiteral: false, subtitle: nil, layout: layout, source: "subsonic", items: items)) }
                case nil: break
                }
            }
            if rows.isEmpty, let failure { throw failure }; return rows
        }
    }
}
