import Foundation
import Observation

@MainActor @Observable final class MusicServerConnectionModel {
    let service: SubsonicMusicService
    var address = ""
    var username = ""
    var password = ""
    private(set) var busy = false
    private(set) var failure: String?
    @ObservationIgnored private var generation = UUID()
    init(service: SubsonicMusicService) { self.service = service }
    var incomplete: Bool { [address, username, password].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var statusKey: String {
        switch service.connectionStatus {
        case "connected": "music.connections.statusConnected"
        case "error": "music.connections.statusError"
        default: "music.connections.statusDisconnected"
        }
    }
    func connect() async -> Bool {
        guard !busy, !incomplete else { return false }
        let token = UUID(); generation = token; busy = true; failure = nil
        defer { if token == generation { busy = false } }
        do {
            try await service.connect(address: address, username: username, password: password)
            try Task.checkCancellation(); try service.validateCatalogScope()
            guard token == generation else { return false }
            address = ""; username = ""; password = ""; return true
        } catch is CancellationError { return false }
        catch {
            guard token == generation, !Task.isCancelled, (try? service.validateCatalogScope()) != nil else { return false }
            failure = (error as? SubsonicMusicError)?.localizedDescription ?? DesktopInterfaceText.value("Music is unavailable right now.")
            return false
        }
    }
    func disconnect() -> Bool {
        guard !busy else { return false }; failure = nil
        do { try service.disconnect(); close(); return true }
        catch is CancellationError { close(); return false }
        catch { failure = (error as? SubsonicMusicError)?.localizedDescription ?? DesktopInterfaceText.value("Music is unavailable right now."); return false }
    }
    func dismissFailure() { failure = nil }
    func close() {
        if busy { service.cancelPendingConnection() }
        generation = UUID(); password = ""; username = ""; address = ""; busy = false; failure = nil
    }
}
