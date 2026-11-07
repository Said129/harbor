import Foundation
import Observation

/// Desktop's `normalize_player_state` (`cast.rs`): the raw Roku or UPnP state as PLAYING, PAUSED, BUFFERING or IDLE.
enum CastPlayerState {
    static func normalize(_ raw: String) -> String {
        let upper = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch upper {
        case "PLAY", "PLAYING": return "PLAYING"
        case "PAUSE", "PAUSED", "PAUSED_PLAYBACK", "PAUSED_RECORDING": return "PAUSED"
        case "BUFFER", "BUFFERING", "TRANSITIONING", "STARTUP": return "BUFFERING"
        case "STOP", "STOPPED", "IDLE", "NO_MEDIA_PRESENT": return "IDLE"
        default: return upper
        }
    }
}

/// Desktop's cast session (`use-cast-session.ts`) for Roku and DLNA renderers: the chosen target, polled state,
/// and the position to hand back to the local player when the cast stops.
@MainActor @Observable
final class CastController {
    enum Phase: Equatable {
        case idle
        case connecting
        case playing
        case paused
    }

    /// A message for the person. `steps` is Desktop's numbered fix list for the Roku errors.
    struct Failure: Equatable {
        let title: String
        let message: String
        let steps: [String]
    }

    private(set) var targets: [CastTarget] = []
    private(set) var scanning = false
    private(set) var selected: CastTarget?
    private(set) var phase: Phase = .idle
    private(set) var positionSec: Double = 0
    private(set) var durationSec: Double?
    private(set) var failure: Failure?
    /// Where the local player should resume after a stop; read it once with `takeResumePosition()`.
    private(set) var resumePositionSec: Double?
    /// The DLNA master volume shown in the sheet, 0 to 100. Roku has no volume call.
    var volume: Double = 50

    @ObservationIgnored private let transport: CastTransport
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var manualTargets: [CastTarget] = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var startTargetSec: Double = 0
    @ObservationIgnored private var seekConfirmed = true
    @ObservationIgnored private var lastPositionSec: Double = 0
    @ObservationIgnored private var generation = 0

    init(transport: CastTransport = CastURLTransport(), pollInterval: Duration = .seconds(1)) {
        self.transport = transport
        self.pollInterval = pollInterval
    }

    // MARK: Discovery and manual entry

    func scan() async {
        guard !scanning else { return }
        scanning = true
        let found = await CastDiscovery.discoverRokus(transport: transport)
        targets = Self.merged(found, manualTargets)
        scanning = false
    }

    /// A typed Roku address (port 8060), or a DLNA device-description URL. Desktop has no manual entry; iOS needs it because multicast is unavailable.
    func addManual(_ text: String) async {
        failure = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let base = CastRoku.normalizedEcpBase(trimmed) {
            await addRoku(base: base)
        } else if trimmed.contains("://") {
            await addDLNA(descriptionURL: trimmed)
        } else {
            failure = Self.noDeviceFailure
        }
    }

    private func addRoku(base: String) async {
        guard let host = URL(string: base)?.host else {
            failure = Self.noDeviceFailure
            return
        }
        guard let target = await CastDiscovery.probeRoku(host: host, transport: transport) else {
            failure = Self.describe(CastProtocolError.rokuNotFound, deviceName: host)
            return
        }
        remember(target)
    }

    private func addDLNA(descriptionURL: String) async {
        do {
            let body = try await sendChecked(CastNet.request(descriptionURL, method: "GET", timeout: 3)).body
            let description = try CastDLNA.parseDescription(body, location: descriptionURL)
            remember(CastTarget(
                id: "dlna-" + descriptionURL,
                kind: .dlna,
                name: description.name,
                model: description.model,
                host: CastNet.hostPort(of: descriptionURL) ?? descriptionURL,
                endpoint: description.avTransportURL,
                volumeEndpoint: description.renderingControlURL,
                vendor: description.vendor
            ))
        } catch {
            failure = Self.noDeviceFailure
        }
    }

    private func remember(_ target: CastTarget) {
        manualTargets.removeAll { $0.id == target.id }
        manualTargets.append(target)
        targets = Self.merged(targets, manualTargets)
    }

    private static func merged(_ first: [CastTarget], _ second: [CastTarget]) -> [CastTarget] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0.id).inserted }
    }

    // MARK: Session

    /// Desktop's `pickCastDevice`: launch or load the media, then poll the renderer. `startSeconds` is the resume point.
    func cast(to target: CastTarget, mediaURL: String, contentType: String?, title: String?, startSeconds: Double) async {
        stopPolling()
        generation += 1
        let current = generation
        selected = target
        phase = .connecting
        failure = nil
        do {
            switch target.kind {
            case .roku:
                try await launchRoku(target, mediaURL: mediaURL, contentType: contentType, title: title, startSeconds: startSeconds)
            case .dlna:
                try await loadDLNA(target, mediaURL: mediaURL, contentType: contentType, title: title, startSeconds: startSeconds)
            }
        } catch {
            guard current == generation else { return }
            selected = nil
            phase = .idle
            failure = Self.describe(error, deviceName: target.name)
            return
        }
        guard current == generation else { return }
        phase = .playing
        startTargetSec = startSeconds
        seekConfirmed = startSeconds <= 1
        lastPositionSec = startSeconds
        positionSec = startSeconds
        startPolling()
    }

    func play() async {
        guard let target = selected else { return }
        do {
            switch target.kind {
            case .roku:
                _ = try await sendChecked(CastRoku.keypressRequest(base: target.endpoint, key: CastRoku.Key.play))
            case .dlna:
                try await perform(CastDLNA.playCall(controlURL: target.endpoint))
            }
        } catch {
            failure = Self.describe(error, deviceName: target.name)
            return
        }
        phase = .playing
    }

    /// Roku's pause is the same `Play` key as resume, a toggle, as in Desktop. The next poll corrects the phase.
    func pause() async {
        guard let target = selected else { return }
        do {
            switch target.kind {
            case .roku:
                _ = try await sendChecked(CastRoku.keypressRequest(base: target.endpoint, key: CastRoku.Key.play))
            case .dlna:
                try await perform(CastDLNA.pauseCall(controlURL: target.endpoint))
            }
        } catch {
            failure = Self.describe(error, deviceName: target.name)
            return
        }
        phase = .paused
    }

    func togglePlayback() async {
        if phase == .playing {
            await pause()
        } else if phase == .paused {
            await play()
        }
    }

    /// DLNA only. Roku has no absolute seek on Media Assistant, so Desktop's no-op is not ported as a control.
    func seek(to seconds: Double) async {
        guard let target = selected, target.kind == .dlna else { return }
        do {
            try await perform(CastDLNA.seekCall(controlURL: target.endpoint, seconds: seconds))
        } catch {
            failure = Self.describe(error, deviceName: target.name)
            return
        }
        lastPositionSec = seconds
        positionSec = seconds
        startTargetSec = seconds
        seekConfirmed = true
    }

    /// DLNA only, on the speaker. Desktop 0.9.132 has no volume control, so this is an iOS addition.
    func setVolume(_ percent: Double) async {
        guard let target = selected, target.kind == .dlna, let url = target.volumeEndpoint else { return }
        volume = min(max(percent, 0), 100)
        do {
            try await perform(CastDLNA.volumeCall(volumeControlURL: url, percent: Int(volume.rounded())))
        } catch {
            failure = Self.describe(error, deviceName: target.name)
        }
    }

    /// Desktop's `stopCast`: the renderer stops, then the local player resumes from the last position.
    func stop() async {
        guard let target = selected else { return }
        stopPolling()
        do {
            switch target.kind {
            case .roku:
                _ = try await sendChecked(CastRoku.keypressRequest(base: target.endpoint, key: CastRoku.Key.home))
            case .dlna:
                try await perform(CastDLNA.stopCall(controlURL: target.endpoint))
            }
        } catch {
            failure = Self.describe(error, deviceName: target.name)
            startPolling()
            return
        }
        if lastPositionSec > 1 {
            resumePositionSec = lastPositionSec
        }
        selected = nil
        phase = .idle
        positionSec = 0
        durationSec = nil
        seekConfirmed = true
    }

    /// The position to resume at, cleared on read.
    func takeResumePosition() -> Double? {
        let value = resumePositionSec
        resumePositionSec = nil
        return value
    }

    /// One poll of the renderer's state and position (Desktop polls every second).
    func refresh() async {
        guard let target = selected else { return }
        let session = generation
        do {
            let state: String
            let position: Double
            var duration: Double?
            switch target.kind {
            case .roku:
                let body = try await sendChecked(CastRoku.mediaPlayerRequest(base: target.endpoint)).body
                let parsed = CastRoku.parseMediaPlayer(body)
                state = CastPlayerState.normalize(parsed.playerState)
                position = parsed.positionSec
                duration = parsed.durationSec
            case .dlna:
                let positionBody = (try? await perform(CastDLNA.positionInfoCall(controlURL: target.endpoint))) ?? ""
                position = CastDLNA.parsePositionInfo(positionBody)
                let transportBody = try await perform(CastDLNA.transportInfoCall(controlURL: target.endpoint))
                state = CastPlayerState.normalize(CastDLNA.parseTransportState(transportBody))
            }
            guard session == generation, selected?.id == target.id else { return }
            switch state {
            case "PLAYING", "BUFFERING": phase = .playing
            case "PAUSED": phase = .paused
            default: break
            }
            durationSec = duration
            if !seekConfirmed {
                guard position >= startTargetSec - 5 else { return }
                seekConfirmed = true
            }
            if position > 0 {
                lastPositionSec = position
                positionSec = position
            }
        } catch {
            guard session == generation else { return }
            failure = Self.describe(error, deviceName: target.name)
        }
    }

    // MARK: Roku

    /// Desktop's `load` for Roku: find Media Assistant (by name, id, or an icon probe), then launch the media.
    private func launchRoku(_ target: CastTarget, mediaURL: String, contentType: String?, title: String?, startSeconds: Double) async throws {
        let apps = CastRoku.parseApps(try await sendChecked(CastRoku.queryAppsRequest(base: target.endpoint)).body)
        var channel = CastRoku.mediaAssistantChannel(in: apps)
        if channel == nil, let probe = try? await send(CastRoku.iconProbeRequest(base: target.endpoint, channel: CastRoku.channelID)), (200..<300).contains(probe.status) {
            channel = CastRoku.channelID
        }
        guard let channel else { throw CastProtocolError.mediaAssistantMissing }
        let request = CastRoku.launchRequest(base: target.endpoint, channel: channel, url: mediaURL, title: title, contentType: contentType, startSeconds: startSeconds)
        _ = try await sendChecked(request)
    }

    // MARK: DLNA

    private func loadDLNA(_ target: CastTarget, mediaURL: String, contentType: String?, title: String?, startSeconds: Double) async throws {
        let plan = CastDLNA.loadPlan(
            controlURL: target.endpoint,
            mediaURL: mediaURL,
            title: title,
            contentType: contentType,
            startSeconds: startSeconds,
            vendor: target.vendor
        )
        for call in plan {
            try await perform(call)
        }
    }

    /// Sends one SOAP call and applies Desktop's ignore and retry rules. Returns the response body.
    @discardableResult
    private func perform(_ call: CastSOAPCall) async throws -> String {
        guard let request = call.request else { throw CastProtocolError.invalidURL }
        let first = await soapOutcome(request, call: call)
        if case .failure = first, let retry = call.retryAfterMilliseconds {
            await pause(milliseconds: retry)
            // Desktop retries a failed Seek once and ignores the second result.
            let second = await soapOutcome(request, call: call)
            if case .success(let reply) = second { return reply.body }
            return ""
        }
        switch first {
        case .success(let reply):
            await pause(milliseconds: call.pauseAfterMilliseconds)
            return reply.body
        case .failure(let error):
            if call.ignoresFailure {
                await pause(milliseconds: call.pauseAfterMilliseconds)
                return ""
            }
            throw error
        }
    }

    private func soapOutcome(_ request: URLRequest, call: CastSOAPCall) async -> Result<CastReply, CastProtocolError> {
        do {
            let reply = try await transport.send(request)
            guard (200..<300).contains(reply.status) else {
                return .failure(.soap(action: call.action, status: reply.status, upnpCode: CastDLNA.upnpErrorCode(reply.body)))
            }
            return .success(reply)
        } catch {
            return .failure(.transport)
        }
    }

    private func pause(milliseconds: Int) async {
        guard milliseconds > 0 else { return }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    // MARK: HTTP helpers

    private func send(_ request: URLRequest?) async throws -> CastReply {
        guard let request else { throw CastProtocolError.invalidURL }
        do {
            return try await transport.send(request)
        } catch {
            throw CastProtocolError.transport
        }
    }

    /// A request whose HTTP status must be 2xx, mapped to Desktop's Roku error codes.
    private func sendChecked(_ request: URLRequest?) async throws -> CastReply {
        let reply = try await send(request)
        guard (200..<300).contains(reply.status) else { throw CastRoku.error(forStatus: reply.status) }
        return reply
    }

    private func startPolling() {
        stopPolling()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Copy

    private static var noDeviceFailure: Failure {
        Failure(
            title: "",
            message: DesktopInterfaceText.value("No Chromecast, DLNA, or Roku devices found. Make sure your TV is on, woken up, and on the same Wi-Fi."),
            steps: []
        )
    }

    /// Desktop's cast error copy (`use-cast-session.ts`, `buildActionableCastError`), with the generic fallback.
    static func describe(_ error: Error, deviceName: String) -> Failure {
        switch error as? CastProtocolError {
        case .rokuBlocked?:
            return Failure(
                title: DesktopInterfaceText.value("Enable Roku Network Access"),
                message: DesktopInterfaceText.value("Your Roku is set to block control requests from apps on your network, so Harbor can't reach it. This is a one-time setting on the Roku."),
                steps: [
                    DesktopInterfaceText.value("On your Roku remote, press Home."),
                    DesktopInterfaceText.value("Open Settings, then System, then Advanced system settings."),
                    DesktopInterfaceText.value("Select \"Control by mobile apps\" and set Network access to \"Default\"."),
                    DesktopInterfaceText.value("Come back to Harbor and try casting again."),
                ]
            )
        case .rokuNotFound?:
            return Failure(
                title: DesktopInterfaceText.value("Couldn't reach this Roku"),
                message: DesktopInterfaceText.value("Harbor found something at this address that looked like a Roku, but it didn't respond like one. The device may be offline or another product picked up the same broadcast."),
                steps: [
                    DesktopInterfaceText.value("Make sure the Roku is powered on and on the same Wi-Fi as your computer."),
                    DesktopInterfaceText.value("Close the cast menu and reopen it to rescan the network."),
                    DesktopInterfaceText.value("If multiple Rokus appear, pick the one matching your TV's name."),
                ]
            )
        case .mediaAssistantMissing?:
            return Failure(
                title: DesktopInterfaceText.value("Install Media Assistant"),
                message: DesktopInterfaceText.value("Roku changed its OS to block the built-in Media Player from accepting video from other apps. Media Assistant is a free channel built to take over that job. One-time install on your Roku and casting works."),
                steps: [
                    DesktopInterfaceText.value("On your Roku, open Streaming Channels from the home screen."),
                    DesktopInterfaceText.value("Search for \"Media Assistant\" (channel ID 782875, free)."),
                    DesktopInterfaceText.value("Install it."),
                    DesktopInterfaceText.value("Come back to Harbor and try casting again."),
                ]
            )
        default:
            return Failure(
                title: "",
                message: DesktopInterfaceText.value("Could not cast to {deviceName}.", variables: ["deviceName": deviceName]),
                steps: []
            )
        }
    }
}
