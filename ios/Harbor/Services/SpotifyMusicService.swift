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
    let speed: Double
    let paused: Bool
    let canSeek: Bool
    let canSkipNext: Bool
    let canSkipPrevious: Bool
    let advertisement: Bool
    let episode: Bool
    init(_ state: any SPTAppRemotePlayerState) {
        title = state.track.name; artist = state.track.artist.name; album = state.track.album.name
        uri = state.track.uri; position = Double(state.playbackPosition) / 1000
        duration = Double(state.track.duration) / 1000; paused = state.isPaused
        let speed = Double(state.playbackSpeed); self.speed = speed.isFinite && speed > 0 ? speed : 1
        canSeek = state.playbackRestrictions.canSeek; canSkipNext = state.playbackRestrictions.canSkipNext
        canSkipPrevious = state.playbackRestrictions.canSkipPrevious; advertisement = state.track.isAdvertisement
        episode = state.track.isEpisode || state.track.isPodcast
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
    var scrobbleError: String? { listening?.error }
    @ObservationIgnored private let currentScope: @MainActor () -> PluginExecutionScope
    @ObservationIgnored private var remote: SPTAppRemote?
    @ObservationIgnored private var pendingAuthorization = false
    @ObservationIgnored private var authorizationAttempt = UUID()
    @ObservationIgnored private var authorizationTimeout: Task<Void, Never>?
    @ObservationIgnored private var disposed = false
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []
    @ObservationIgnored private var contentRequests: [UUID: (CheckedContinuation<Data, Error>, Task<Void, Never>)] = [:]
    @ObservationIgnored private let images = NSCache<NSString, UIImage>()
    @ObservationIgnored private var listening: SpotifyListeningRecorder?
    @ObservationIgnored private var listeningConnection: UUID?
    @ObservationIgnored private var listeningPoller: Task<Void, Never>?
    @ObservationIgnored private var stateRequest: (id: UUID, continuation: CheckedContinuation<SpotifyPlaybackSnapshot, Error>, deadline: Task<Void, Never>)?
    private var storageKey: String { "music-spotify-client-" + EBookShelf.hash(scope.owner) }
    init(scope: PluginExecutionScope, currentScope: @escaping @MainActor () -> PluginExecutionScope) {
        self.scope = scope; self.currentScope = currentScope
        super.init()
        do { clientID = try KeychainStore().read(storageKey, as: String.self) ?? "" }
        catch { self.error = DesktopInterfaceText.value("music.spotifySetup.rejected") }
        if !clientID.isEmpty { makeRemote() }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in self?.stopListening(); self?.remote?.disconnect() }
        })
        tokens.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.valid else { return }
                if self.pendingAuthorization {
                    let attempt = self.authorizationAttempt
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    if self.valid, self.pendingAuthorization, self.authorizationAttempt == attempt { self.endAuthorization(DesktopInterfaceText.value("music.spotifySetup.rejected")) }
                } else if self.remote?.connectionParameters.accessToken != nil { self.remote?.connect() }
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
        guard !authorizing else { return }
        guard valid, let remote else { error = DesktopInterfaceText.value("music.spotifySetup.missingSaved"); return }
        guard UIApplication.shared.canOpenURL(URL(string: "spotify:")!) else {
            error = DesktopInterfaceText.value("music.mobile.spotify.install"); return
        }
        MusicPlayback.shared.stop()
        error = nil; pendingAuthorization = true; authorizing = true
        authorizationTimeout?.cancel(); authorizationAttempt = UUID(); let attempt = authorizationAttempt
        authorizationTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard let self, self.valid, self.authorizationAttempt == attempt, self.pendingAuthorization else { return }
            self.endAuthorization(DesktopInterfaceText.value("music.spotifySetup.rejected"))
        }
        remote.authorizeAndPlayURI("") { [weak self] success in
            guard !success else { return }
            Task { @MainActor in
                guard let self, self.valid, self.authorizationAttempt == attempt else { return }
                self.endAuthorization(DesktopInterfaceText.value("music.spotifySetup.rejected"))
            }
        }
    }
    private func endAuthorization(_ message: String? = nil) {
        pendingAuthorization = false; authorizing = false; authorizationAttempt = UUID()
        authorizationTimeout?.cancel(); authorizationTimeout = nil
        if let message { error = message }
    }
    @discardableResult func accept(_ url: URL) -> Bool {
        guard url.scheme == "harbor-iphone", url.host == "spotify-login-callback" else { return false }
        guard valid, pendingAuthorization, let remote else { return true }
        endAuthorization()
        guard let parameters = remote.authorizationParameters(from: url), let token = parameters[SPTAppRemoteAccessTokenKey], !token.isEmpty else {
            error = DesktopInterfaceText.value("music.spotifySetup.rejected"); return true
        }
        remote.connectionParameters.accessToken = token
        remote.connect(); return true
    }
    func disconnect() {
        endAuthorization()
        stopListening(); listening?.playRequested()
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
    func next() { guard valid, connected, snapshot?.canSkipNext == true else { return }; invalidateListeningPosition(newPlay: true); remote?.playerAPI?.skip(toNext: callback) }
    func previous() { guard valid, connected, snapshot?.canSkipPrevious == true else { return }; invalidateListeningPosition(newPlay: true); remote?.playerAPI?.skip(toPrevious: callback) }
    func seek(_ seconds: Double) {
        guard valid, connected, snapshot?.canSeek == true, seconds.isFinite, seconds >= 0 else { return }
        invalidateListeningPosition(newPlay: false)
        remote?.playerAPI?.seek(toPosition: Int(min(seconds, snapshot?.duration ?? 0) * 1000), callback: callback)
    }
    func play(_ uri: String) {
        guard valid, connected, uri.hasPrefix("spotify:"), !uri.contains(where: { $0.isWhitespace }) else { return }
        MusicPlayback.shared.stop(); invalidateListeningPosition(newPlay: true); remote?.playerAPI?.play(uri, callback: callback)
    }
    private var callback: SPTAppRemoteCallback {
        { [weak self] _, failure in
            let failed = failure != nil
            Task { @MainActor in
                guard let self, self.valid else { return }
                if failed { self.error = DesktopInterfaceText.value("music.mobile.spotify.restricted") }
            }
        }
    }
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        let identity = ObjectIdentifier(appRemote)
        Task { @MainActor [weak self] in
            guard let self, self.valid, self.remote.map(ObjectIdentifier.init) == identity else { return }
            connected = true; authorizing = false; error = nil
            SpotifyMusicSelection.shared.active = self
            remote?.playerAPI?.delegate = self
            remote?.playerAPI?.subscribe(toPlayerState: callback)
            startListening()
        }
    }
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) { disconnected(appRemote, failed: false) }
    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) { disconnected(appRemote, failed: true) }
    nonisolated private func disconnected(_ appRemote: SPTAppRemote, failed: Bool) {
        let identity = ObjectIdentifier(appRemote)
        Task { @MainActor [weak self] in
            guard let self, self.valid, self.remote.map(ObjectIdentifier.init) == identity else { return }
            connected = false
            stopListening()
            if !pendingAuthorization { authorizing = false }
            failContentRequests()
            if failed { self.error = DesktopInterfaceText.value("music.spotifySetup.rejected") }
        }
    }
    nonisolated func playerStateDidChange(_ playerState: any SPTAppRemotePlayerState) {
        let value = SpotifyPlaybackSnapshot(playerState)
        Task { @MainActor [weak self] in guard let self, self.valid, self.connected else { return }; snapshot = value; snapshotAt = Date() }
    }
    func position(at date: Date) -> Double {
        guard let snapshot else { return 0 }
        let elapsed = connected && !snapshot.paused ? max(0, date.timeIntervalSince(snapshotAt)) * snapshot.speed : 0
        return min(snapshot.duration, max(0, snapshot.position + elapsed))
    }
    func configureScrobbling(_ account: LastFmMusicService) {
        stopListening(); listening?.dispose(); listening = nil
        guard valid, account.scope == scope else { return }
        listening = SpotifyListeningRecorder(lastfm: account, currentScope: currentScope)
        if connected { startListening() }
    }
    private func startListening() {
        stopListening()
        guard valid, connected, listening != nil else { return }
        let connection = UUID(); listeningConnection = connection; listening?.connect(connection)
        listeningPoller = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.valid, self.connected, self.listeningConnection == connection else { return }
                if UIApplication.shared.applicationState == .active, self.listening?.enabled == true {
                    do {
                        let value = try await self.confirmedPlayerState(connection)
                        if value.advertisement { self.listening?.suspend() }
                        else if value.episode || !value.duration.isFinite || value.duration <= 0 || value.duration > Double(UInt32.max) {
                            self.listening?.playRequested()
                        } else {
                            let seconds = UInt64(value.duration)
                            let track = MusicTrack(id: value.uri, connectorId: "spotify", sourceId: value.uri, playbackUrl: nil,
                                title: value.title, artist: value.artist, album: value.album.isEmpty ? nil : value.album, artwork: "",
                                durationSeconds: seconds, durationLabel: "\(seconds / 60):" + String(format: "%02llu", seconds % 60))
                            self.listening?.observe(track, position: value.position, paused: value.paused, advertisement: false, connection: connection)
                        }
                    } catch is CancellationError { return }
                    catch { self.listening?.suspend() }
                } else { self.listening?.suspend() }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    private func invalidateListeningPosition(newPlay: Bool) {
        if newPlay { listening?.playRequested() } else { listening?.seekRequested() }
        if let pending = stateRequest {
            finishPlayerState(pending.id, result: .failure(HarborError(code: "spotify-state-reset")))
        }
    }
    private func stopListening() {
        let old = listeningConnection; listeningConnection = nil
        listeningPoller?.cancel(); listeningPoller = nil
        if let old { listening?.disconnect(old) }
        if let pending = stateRequest { finishPlayerState(pending.id, result: .failure(CancellationError())) }
    }
    private func confirmedPlayerState(_ connection: UUID) async throws -> SpotifyPlaybackSnapshot {
        guard valid, connected, listeningConnection == connection, let api = remote?.playerAPI,
              stateRequest == nil else { throw CancellationError() }
        let request = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    self?.finishPlayerState(request, result: .failure(HarborError(code: "spotify-state")))
                }
                stateRequest = (request, continuation, deadline)
                api.getPlayerState { [weak self] result, error in
                    let value: SpotifyPlaybackSnapshot?
                    if error == nil, let state = result as? any SPTAppRemotePlayerState { value = SpotifyPlaybackSnapshot(state) }
                    else { value = nil }
                    Task { @MainActor in
                        guard let self else { return }
                        guard self.valid, self.connected, self.listeningConnection == connection, UIApplication.shared.applicationState == .active else {
                            self.finishPlayerState(request, result: .failure(CancellationError())); return
                        }
                        if let value { self.finishPlayerState(request, result: .success(value)) }
                        else { self.finishPlayerState(request, result: .failure(HarborError(code: "spotify-state"))) }
                    }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finishPlayerState(request, result: .failure(CancellationError())) } }
    }
    private func finishPlayerState(_ request: UUID, result: Result<SpotifyPlaybackSnapshot, Error>) {
        guard let pending = stateRequest, pending.id == request else { return }
        stateRequest = nil; pending.deadline.cancel(); pending.continuation.resume(with: result)
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
                        if !self.valid || !self.connected { self.finishContent(request, result: .failure(CancellationError())) }
                        else if !failed, let data, data.count <= 8 * 1024 * 1024 { self.finishContent(request, result: .success(data)) }
                        else { self.finishContent(request, result: .failure(HarborError(code: "spotify-content"))) }
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
        listening?.dispose(); listening = nil
        for token in tokens { NotificationCenter.default.removeObserver(token) }; tokens = []
    }
}
