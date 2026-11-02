import Foundation
import Observation

@MainActor protocol JellyfinMusicPersistence {
    func read(owner: String) throws -> JellyfinMusicAccount?
    func write(_ account: JellyfinMusicAccount, owner: String) throws
    func remove(owner: String) throws
}
@MainActor struct KeychainJellyfinMusic: JellyfinMusicPersistence {
    private func key(_ owner: String) -> String { "music-jellyfin-account-" + EBookShelf.hash(owner) }
    func read(owner: String) throws -> JellyfinMusicAccount? { try KeychainStore().read(key(owner), as: JellyfinMusicAccount.self) }
    func write(_ account: JellyfinMusicAccount, owner: String) throws { try KeychainStore().write(account, key: key(owner)) }
    func remove(owner: String) throws { try KeychainStore().remove(key(owner)) }
}

@MainActor @Observable final class JellyfinMusicService: MusicCatalogCalling {
    let scope: PluginExecutionScope
    private(set) var account: JellyfinMusicAccount?
    private(set) var health = MusicSourceCandidate.Health.unknown
    private(set) var storageFailure = false
    private(set) var credentialVersion = UUID()
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private let persistence: any JellyfinMusicPersistence
    @ObservationIgnored private let network: any MusicCatalogNetworking
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var operations: [UUID: Task<HarborNetworkResponse, Error>] = [:]
    @ObservationIgnored private var reports: Task<Void, Never>?
    var configured: Bool { !disposed && scope == currentScope() && account != nil }
    var statusKey: String {
        if storageFailure || health == .offline || health == .degraded { return "music.connections.statusError" }
        return configured ? "music.connections.statusConnected" : "music.connections.statusDisconnected"
    }
    init(scope: PluginExecutionScope, network: any MusicCatalogNetworking = HarborNativeNetwork(),
         persistence: (any JellyfinMusicPersistence)? = nil, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope; self.network = network; self.persistence = persistence ?? KeychainJellyfinMusic(); self.currentScope = currentScope
        do { account = try self.persistence.read(owner: scope.owner) } catch { storageFailure = true }
    }
    func validate(_ version: UUID? = nil) throws {
        try Task.checkCancellation()
        guard !disposed, scope == currentScope(), version == nil || version == credentialVersion else { throw CancellationError() }
    }
    func dispose() { disposed = true; cancelPending(); account = nil }
    func cancelPending() {
        credentialVersion = UUID(); operations.values.forEach { $0.cancel() }; operations.removeAll()
        reports?.cancel(); reports = nil
    }
    private func send(_ request: JellyfinMusicRequest, version: UUID) async throws -> Data {
        try validate(version)
        let token = UUID(), network = network
        let task = Task { try await network.performMusicCatalog(.init(operation: "jellyfin", request: request)) }
        operations[token] = task
        defer { operations[token] = nil }
        do {
            let response = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try validate(version)
            guard response.ok else {
                health = response.status == 504 ? .offline : .degraded
                throw HarborError(code: "music-jellyfin-unavailable")
            }
            health = .healthy
            return try response.bytes()
        } catch {
            try validate(version)
            if error is CancellationError { throw CancellationError() }
            if (error as? HarborError)?.code != "music-jellyfin-unavailable" { health = .offline }
            throw HarborError(code: "music-jellyfin-unavailable")
        }
    }
    private func call<T: Decodable & Sendable>(_ command: JellyfinMusicCommand, as type: T.Type) async throws -> T {
        try validate(); guard let account else { throw HarborError(code: "music-jellyfin-disconnected") }
        let version = credentialVersion
        let data = try await send(.init(action: "connected", config: account, command: command), version: version)
        let value: T
        do { value = try JSONDecoder().decode(type, from: data) }
        catch { throw HarborError(code: "music-jellyfin-unreadable") }
        try validate(version); return value
    }
    func connect(address: String, username: String, password: String) async throws {
        try validate(); cancelPending(); let version = credentialVersion
        let deviceId = account?.deviceId ?? "harbor-ios-" + UUID().uuidString.lowercased()
        let data = try await send(.init(action: "signIn", address: address, username: username, password: password, deviceId: deviceId), version: version)
        let result: JellyfinMusicAccount
        do { result = try JSONDecoder().decode(JellyfinMusicAccount.self, from: data) }
        catch { throw HarborError(code: "music-jellyfin-unreadable") }
        try validate(version)
        do { try persistence.write(result, owner: scope.owner) }
        catch { storageFailure = true; throw HarborError(code: "music-jellyfin-storage") }
        account = result; storageFailure = false
    }
    func disconnect() throws {
        try validate(); cancelPending()
        do { try persistence.remove(owner: scope.owner) }
        catch { storageFailure = true; throw HarborError(code: "music-jellyfin-storage") }
        account = nil; storageFailure = false; health = .unknown
    }
    func home() async throws -> [MusicCatalogRow] {
        try validate(); guard configured else { return [] }
        return try await call(.init(action: "home"), as: [MusicCatalogRow].self)
    }
    func search(_ query: String, limit: Int) async throws -> MusicCatalogSearch {
        try await call(.init(action: "search", query: query, limit: limit), as: MusicCatalogSearch.self)
    }
    func albumTracks(_ album: MusicCatalogAlbum) async throws -> [MusicTrack] {
        guard album.connectorId == "jellyfin" else { throw HarborError(code: "music-jellyfin-recording") }
        return try await call(.init(action: "albumTracks", id: album.id), as: [MusicTrack].self)
    }
    func artistTop(_ artist: MusicCatalogArtist) async throws -> [MusicTrack] {
        guard artist.connectorId == "jellyfin" else { throw HarborError(code: "music-jellyfin-recording") }
        return try await call(.init(action: "artistTop", id: artist.id), as: [MusicTrack].self)
    }
    func artistRows(_ artist: MusicCatalogArtist) async throws -> [MusicCatalogRow] { try validate(); return [] }
    func artistCatalog(_ artist: MusicCatalogArtist, kind: MusicCatalogKind, cursor: String?) async throws -> MusicCatalogPage {
        guard artist.connectorId == "jellyfin", cursor == nil else { throw HarborError(code: "music-jellyfin-recording") }
        return try await call(.init(action: "artistCatalog", id: artist.id, kind: kind), as: MusicCatalogPage.self)
    }
    func playlistTracks(_ playlist: MusicCatalogPlaylist) async throws -> [MusicTrack] {
        guard playlist.connectorId == "jellyfin" else { throw HarborError(code: "music-jellyfin-recording") }
        return try await call(.init(action: "playlistTracks", id: playlist.id), as: [MusicTrack].self)
    }
    func stationTracks(_ station: MusicCatalogStation) async throws -> [MusicTrack] {
        guard station.connectorId == "jellyfin" else { throw HarborError(code: "music-jellyfin-recording") }
        return try await call(.init(action: "stationTracks", id: station.id), as: [MusicTrack].self)
    }
    func resolve(_ track: MusicTrack) async throws -> MusicPlaybackResolution {
        try validate(); let version = credentialVersion
        let value = try await call(.init(action: "resolve", track: track), as: JellyfinMusicResolution.self)
        let stream = MusicAudioStream(url: value.stream.url, httpHeaders: value.stream.httpHeaders ?? [:], mimeType: value.stream.mimeType, bitrate: value.stream.bitrate)
        return .init(stream: stream, valid: { [weak self] in
            guard let self else { return false }; return self.configured && version == self.credentialVersion
        }, onLoaded: { [weak self] in self?.report(.init(action: "started", session: value.session, direct: value.direct), version: version) },
        onStopped: { [weak self] in self?.report(.init(action: "stopped", session: value.session), version: version) })
    }
    private func report(_ command: JellyfinMusicCommand, version: UUID) {
        guard configured, credentialVersion == version else { return }
        let previous = reports
        reports = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, (try? self.validate(version)) != nil, let account = self.account else { return }
            _ = try? await self.send(.init(action: "connected", config: account, command: command), version: version)
        }
    }
}
