import Foundation
import Observation
@preconcurrency import SpotifyiOS
import UIKit

struct SpotifyPlaybackSnapshot: Sendable {
    let title: String
    let artist: String
    let album: String
    let uri: String
    let position: Double
    let duration: Double
    let paused: Bool
    let canSeek: Bool
    let canSkipNext: Bool
    let canSkipPrevious: Bool
    let advertisement: Bool
    init(_ state: any SPTAppRemotePlayerState) {
        title = state.track.name; artist = state.track.artist.name; album = state.track.album.name
        uri = state.track.uri; position = Double(state.playbackPosition) / 1000
        duration = Double(state.track.duration) / 1000; paused = state.isPaused
        canSeek = state.playbackRestrictions.canSeek; canSkipNext = state.playbackRestrictions.canSkipNext
        canSkipPrevious = state.playbackRestrictions.canSkipPrevious; advertisement = state.track.isAdvertisement
    }
}

struct SpotifyContentItem: Decodable, Identifiable, Sendable {
    let id: String
    let uri: String
    let title: String
    let subtitle: String
    let playable: Bool
    let container: Bool
    let offline: Bool
}

@MainActor @Observable final class SpotifyMusicSelection {
    static let shared = SpotifyMusicSelection()
    var active: SpotifyMusicService?
}

/// Spotify owns audio, advertisements, subscription restrictions and its iOS
/// background session. Tokens never become Harbor stream URLs or public state.
@MainActor @Observable final class SpotifyMusicService: NSObject, SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    static var active: SpotifyMusicService? { SpotifyMusicSelection.shared.active }
    static let redirect = "harbor-iphone://spotify-login-callback"
    let scope: PluginExecutionScope
    private(set) var clientID = ""
    private(set) var connected = false
    private(set) var authorizing = false
    private(set) var snapshot: SpotifyPlaybackSnapshot?
    private(set) var snapshotAt = Date()
    var error: String?
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private var remote: SPTAppRemote?
    @ObservationIgnored private var pendingAuthorization = false
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var contentRequests: [UUID: (CheckedContinuation<Data, Error>, Task<Void, Never>)] = [:]
    @ObservationIgnored private let images = NSCache<NSString, UIImage>()
    private var storageKey: String { "music-spotify-client-" + EBookShelf.hash(scope.owner) }
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope; self.currentScope = currentScope
        super.init()
        do { clientID = try KeychainStore().read(storageKey, as: String.self) ?? "" }
        catch { error = "No se pudo recuperar la configuración de Spotify." }
        if !clientID.isEmpty { makeRemote() }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.remote?.disconnect() }
        })
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                guard let self, valid, !pendingAuthorization, remote?.connectionParameters.accessToken != nil else { return }
                remote?.connect()
            }
        })
    }
    private var valid: Bool { !disposed && scope == currentScope() }
    func saveClientID(_ input: String) throws {
        guard valid else { throw CancellationError() }
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 32, value.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw HarborError(code: "spotify-client-id") }
        try KeychainStore().write(value, key: storageKey)
        disconnect(); clientID = value; makeRemote(); error = nil
    }
    private func makeRemote() {
        guard valid, !clientID.isEmpty, let url = URL(string: Self.redirect) else { return }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: url)
        let value = SPTAppRemote(configuration: configuration, logLevel: .none)
        value.delegate = self; remote = value
    }
    func authorize() {
        guard valid, let remote else { error = "Introduce primero el Client ID de tu aplicación de Spotify."; return }
        guard UIApplication.shared.canOpenURL(URL(string: "spotify:")!) else {
            error = "Instala la aplicación oficial de Spotify e inicia sesión allí."; return
        }
        MusicPlayback.shared.stop()
        error = nil; pendingAuthorization = true; authorizing = true
        remote.authorizeAndPlayURI("") { [weak self] success in
            guard !success else { return }
            Task { @MainActor in self?.pendingAuthorization = false; self?.authorizing = false; self?.error = "No se pudo abrir Spotify." }
        }
    }
    @discardableResult func accept(_ url: URL) -> Bool {
        guard url.scheme == "harbor-iphone", url.host == "spotify-login-callback" else { return false }
        guard valid, pendingAuthorization, let remote else { return true }
        pendingAuthorization = false; authorizing = false
        guard let parameters = remote.authorizationParameters(from: url), let token = parameters[SPTAppRemoteAccessTokenKey], !token.isEmpty else {
            error = "Spotify no autorizó la conexión. Revisa el Client ID, la URI y los usuarios permitidos."; return true
        }
        remote.connectionParameters.accessToken = token
        remote.connect(); return true
    }
    func disconnect() {
        pendingAuthorization = false; authorizing = false
        remote?.playerAPI?.delegate = nil
        remote?.disconnect(); remote?.connectionParameters.accessToken = nil
        if Self.active === self { SpotifyMusicSelection.shared.active = nil }
        failContentRequests()
        connected = false; snapshot = nil
    }
    func forget() throws {
        guard valid else { throw CancellationError() }
        try KeychainStore().remove(storageKey); disconnect(); remote = nil; clientID = ""
    }
    func pauseForVideo() { if snapshot?.paused == false { pause() } }
    func togglePause() {
        guard valid, connected else { return }
        if snapshot?.paused == true { MusicPlayback.shared.stop(); remote?.playerAPI?.resume(callback) }
        else { pause() }
    }
    private func pause() { guard valid, connected else { return }; remote?.playerAPI?.pause(callback) }
    func next() { guard valid, connected, snapshot?.canSkipNext == true else { return }; remote?.playerAPI?.skip(toNext: callback) }
    func previous() { guard valid, connected, snapshot?.canSkipPrevious == true else { return }; remote?.playerAPI?.skip(toPrevious: callback) }
    func seek(_ seconds: Double) {
        guard valid, connected, snapshot?.canSeek == true, seconds.isFinite, seconds >= 0 else { return }
        remote?.playerAPI?.seek(toPosition: Int(min(seconds, snapshot?.duration ?? 0) * 1000), callback: callback)
    }
    func play(_ uri: String) {
        guard valid, connected, uri.hasPrefix("spotify:"), !uri.contains(where: { $0.isWhitespace }) else { return }
        MusicPlayback.shared.stop(); remote?.playerAPI?.play(uri, callback: callback)
    }
    private var callback: SPTAppRemoteCallback {
        { [weak self] _, failure in
            let failed = failure != nil
            Task { @MainActor in
                guard let self, valid else { return }
                if failed { error = "Spotify no permite esta acción ahora. Se mantienen las condiciones de tu cuenta." }
            }
        }
    }
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        let identity = ObjectIdentifier(appRemote)
        Task { @MainActor [weak self] in
            guard let self, valid, remote.map(ObjectIdentifier.init) == identity else { return }
            connected = true; authorizing = false; error = nil
            SpotifyMusicSelection.shared.active = self
            remote?.playerAPI?.delegate = self
            remote?.playerAPI?.subscribe(toPlayerState: callback)
        }
    }
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) { disconnected(appRemote, failed: false) }
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) { disconnected(appRemote, failed: true) }
    nonisolated private func disconnected(_ appRemote: SPTAppRemote, failed: Bool) {
        let identity = ObjectIdentifier(appRemote)
        Task { @MainActor [weak self] in
            guard let self, valid, remote.map(ObjectIdentifier.init) == identity else { return }
            connected = false; authorizing = false
            failContentRequests()
            if failed { self.error = "Abre Spotify y vuelve a conectar. Revisa también el acceso de tu aplicación de desarrollador." }
        }
    }
    nonisolated func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        let value = SpotifyPlaybackSnapshot(playerState)
        Task { @MainActor [weak self] in guard let self, valid, connected else { return }; snapshot = value; snapshotAt = Date() }
    }
    private func contentData(_ uri: String?, artwork: Bool) async throws -> Data {
        guard valid, connected, let remote else { throw HarborError(code: "spotify-content") }
        let request = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.finishContent(request, result: .failure(HarborError(code: "spotify-content")))
                }
                contentRequests[request] = (continuation, timeout)
                let completion: HarborSpotifyContentReply = { [weak self] data, error in
                    let failed = error != nil
                    Task { @MainActor in
                        guard let self else { return }
                        if !valid || !connected { finishContent(request, result: .failure(CancellationError())) }
                        else if !failed, let data, data.count <= 8 * 1024 * 1024 { finishContent(request, result: .success(data)) }
                        else { finishContent(request, result: .failure(HarborError(code: "spotify-content"))) }
                    }
                }
                if artwork, let uri { HarborSpotifyArtwork(remote, uri, completion) }
                else { HarborSpotifyContent(remote, uri, completion) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finishContent(request, result: .failure(CancellationError())) } }
    }
    private func finishContent(_ request: UUID, result: Result<Data, Error>) {
        guard let pending = contentRequests.removeValue(forKey: request) else { return }
        pending.1.cancel(); pending.0.resume(with: result)
    }
    private func failContentRequests() {
        for id in Array(contentRequests.keys) { finishContent(id, result: .failure(CancellationError())) }
        images.removeAllObjects()
    }
    func content(_ uri: String? = nil) async throws -> [SpotifyContentItem] {
        let data = try await contentData(uri, artwork: false)
        try Task.checkCancellation()
        return try JSONDecoder().decode([SpotifyContentItem].self, from: data)
    }
    func artwork(_ uri: String) async throws -> UIImage {
        guard valid, connected else { throw CancellationError() }
        if let image = images.object(forKey: uri as NSString) { return image }
        let data = try await contentData(uri, artwork: true)
        try Task.checkCancellation()
        guard let image = UIImage(data: data) else { throw HarborError(code: "spotify-content") }
        images.countLimit = 48; images.totalCostLimit = 16 * 1024 * 1024
        images.setObject(image, forKey: uri as NSString, cost: Int(image.size.width * image.scale * image.size.height * image.scale * 4))
        return image
    }
    func dispose() {
        guard !disposed else { return }; disconnect(); disposed = true; remote?.delegate = nil; remote = nil
        for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens = []
    }
}
