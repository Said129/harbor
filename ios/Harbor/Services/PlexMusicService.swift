import Foundation
import Observation

@MainActor protocol PlexMusicPersistence {
    func read(owner: String) throws -> PlexMusicAccount?
    func write(_ account: PlexMusicAccount, owner: String) throws
    func remove(owner: String) throws
}
@MainActor struct KeychainPlexMusic: PlexMusicPersistence {
    private func key(_ owner: String) -> String { "music-plex-account-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> PlexMusicAccount? { try KeychainStore().read(key(owner), as: PlexMusicAccount.self) }
    func write(_ account: PlexMusicAccount, owner: String) throws { try KeychainStore().write(account, key: key(owner)) }
    func remove(owner: String) throws { try KeychainStore().remove(key(owner)) }
}

@MainActor @Observable final class PlexMusicService: MusicCatalogCalling {
    let scope: PluginExecutionScope
    private var storedAccount: PlexMusicAccount?
    var account: PlexMusicAccount? { !disposed && scope == currentScope() ? storedAccount : nil }
    private(set) var health = MusicSourceCandidate.Health.unknown
    private(set) var storageFailure = false
    private(set) var credentialVersion = UUID()
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let persistence: any PlexMusicPersistence
    @ObservationIgnored private let network: any MusicCatalogNetworking
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var operations: [UUID: Task<HarborNetworkResponse, Error>] = [:]
    @ObservationIgnored private let covers = NSCache<NSString, NSData>()
    @ObservationIgnored private var coverTasks: [String: Task<Data, Error>] = [:]
    var configured: Bool { !disposed && scope == currentScope() && account != nil }
    var statusKey: String {
        if storageFailure || health == .offline || health == .degraded { return "music.connections.statusError" }
        return configured ? "music.connections.statusConnected" : "music.connections.statusDisconnected"
    }
    init(scope: PluginExecutionScope, network: any MusicCatalogNetworking = HarborNativeNetwork(),
         persistence: (any PlexMusicPersistence)? = nil, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope; self.network = network; self.persistence = persistence ?? KeychainPlexMusic(); self.currentScope = currentScope
        covers.totalCostLimit = 16 * 1024 * 1024
        do { storedAccount = try self.persistence.read(owner: scope.owner) } catch { storageFailure = true }
    }
    func validate(_ version: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope(), version == nil || version == credentialVersion else { throw CancellationError() }
    }
    func dispose() { disposed = true; cancelPending(); storedAccount = nil }
    func cancelPending() {
        credentialVersion = UUID(); operations.values.forEach { $0.cancel() }; operations.removeAll()
        coverTasks.values.forEach { $0.cancel() }; coverTasks.removeAll(); covers.removeAllObjects()
    }
    private func send(_ request: PlexMusicRequest, version: UUID) async throws -> Data {
        try validate(version)
        let token = UUID(), network = network
        let task = Task { try await network.performMusicCatalog(.init(operation: "plex", request: .plex(request))) }
        operations[token] = task
        defer { operations[token] = nil }
        do {
            let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try validate(version)
            guard response.ok else {
                health = response.status == 504 ? .offline : .degraded
                throw HarborError(code: "music-plex-unavailable")
            }
            health = .healthy
            return try response.bytes()
        } catch {
            try validate(version)
            if error is CancellationError { throw CancellationError() }
            if (error as? HarborError)?.code != "music-plex-unavailable" { health = .offline }
            throw HarborError(code: "music-plex-unavailable")
        }
    }
    private func call<T: Decodable & Sendable>(_ command: PlexMusicCommand, as type: T.Type) async throws -> T {
        try validate(); guard let account else { throw HarborError(code: "music-plex-disconnected") }
        let version = credentialVersion
        let data = try await send(.init(action: "connected", config: account, command: command), version: version)
        let value: T
        do { value = try JSONDecoder().decode(type, from: data) }
        catch { throw HarborError(code: "music-plex-unreadable") }
        try validate(version); return value
    }
    func connect(address: String, token: String) async throws {
        try validate(); cancelPending(); let version = credentialVersion
        let clientId = "harbor-ios-" + UUID().uuidString.lowercased()
        let data = try await send(.init(action: "connect", address: address, token: token, clientId: clientId), version: version)
        let result: PlexMusicAccount
        do { result = try JSONDecoder().decode(PlexMusicAccount.self, from: data) }
        catch { throw HarborError(code: "music-plex-unreadable") }
        try validate(version)
        do { try persistence.write(result, owner: scope.owner) }
        catch { storageFailure = true; throw HarborError(code: "music-plex-storage") }
        storedAccount = result; storageFailure = false
    }
    func disconnect() throws {
        try validate(); cancelPending()
        do { try persistence.remove(owner: scope.owner) }
        catch { storageFailure = true; throw HarborError(code: "music-plex-storage") }
        storedAccount = nil; storageFailure = false; health = .unknown
    }
    func home() async throws -> [MusicCatalogRow] {
        try validate(); guard configured else { return [] }
        return try await call(.init(action: "home"), as: [MusicCatalogRow].self)
    }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch {
        try await call(.init(action: "search", query: query, limit: limit), as: MusicCatalogSearch.self)
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] {
        guard album.connectorId == "plex" else { throw HarborError(code: "music-plex-recording") }
        return try await call(.init(action: "albumTracks", album: album), as: [MusicTrack].self)
    }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] {
        guard artist.connectorId == "plex" else { throw HarborError(code: "music-plex-recording") }
        return try await call(.init(action: "artistTop", artist: artist), as: [MusicTrack].self)
    }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] { try validate(); return [] }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        guard artist.connectorId == "plex", cursor == nil else { throw HarborError(code: "music-plex-recording") }
        return try await call(.init(action: "artistCatalog", artist: artist, kind: kind), as: MusicCatalogPage.self)
    }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] {
        guard playlist.connectorId == "plex" else { throw HarborError(code: "music-plex-recording") }
        return try await call(.init(action: "playlistTracks", playlist: playlist), as: [MusicTrack].self)
    }
    func stationTracks(_ station: MusicCatalogStation) async throws -> [MusicTrack] {
        guard station.connectorId == "plex" else { throw HarborError(code: "music-plex-recording") }
        return try await call(.init(action: "stationTracks", station: station), as: [MusicTrack].self)
    }
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution {
        try validate(); let version = credentialVersion
        let value = try await call(.init(action: "resolve", track: track, sessionId: UUID().uuidString.lowercased()), as: JellyfinMusicResolution.Stream.self)
        let stream = MusicAudioStream(url: value.url, httpHeaders: value.httpHeaders ?? [:], mimeType: value.mimeType, bitrate: value.bitrate)
        return .init(stream: stream, valid: { [weak self] in
            guard let self else { return false }; return self.configured && version == self.credentialVersion
        })
    }
    func artwork(_ reference: String) async throws -> Data {
        try validate(); let version = credentialVersion
        guard let account, let components = URLComponents(string: reference), components.scheme == "harbor-music-art",
              components.host == "plex", components.path == "/" + account.clientId else { throw HarborError(code: "music-plex-artwork") }
        if let data = covers.object(forKey: reference as NSString) { return data as Data }
        if let task = coverTasks[reference] { let value = try await task.value; try validate(version); return value }
        let task = Task { @MainActor [weak self] () throws -> Data in
            guard let self else { throw CancellationError() }
            struct Response: Decodable, Sendable { let data: String }
            let response = try await self.call(.init(action: "artwork", reference: reference), as: Response.self)
            guard let data = Data(base64Encoded: response.data), data.count <= 2 * 1024 * 1024 else { throw HarborError(code: "music-plex-artwork") }
            return data
        }
        coverTasks[reference] = task
        defer { if version == credentialVersion { coverTasks[reference] = nil } }
        let data = try await task.value; try validate(version)
        covers.setObject(data as NSData, forKey: reference as NSString, cost: data.count); return data
    }
}
