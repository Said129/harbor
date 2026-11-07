import Foundation
import Observation

/// Desktop's connect results (`settings/letterboxd-panel.tsx`): a verified Public username, or a message for the person.
enum StremboxdVerification: Equatable, Sendable {
    case connected(catalogs: Int)
    /// Desktop's English message, shown as it is.
    case failed(String)
    /// Desktop's `Stremboxd error ({status}).`
    case httpFailed(Int)
}

extension StremboxdVerification {
    /// Desktop's `validateStremboxdConfig` failure messages: 400 is an invalid configuration, other statuses show their number.
    static func forError(_ error: StremboxdError) -> StremboxdVerification {
        if error.status == 400 { return .failed("Invalid configuration.") }
        if error.status > 0 { return .httpFailed(error.status) }
        return .failed(error.message)
    }
}

enum StremboxdSignIn: Equatable, Sendable {
    case signedIn
    case needsCode
    case failed(String)
}

/// Desktop's Letterboxd provider (`lib/stremboxd/provider.tsx`): the settings, the Stremboxd session, and the actions that change them.
@MainActor @Observable final class StremboxdAccount {
    static let shared = StremboxdAccount()
    /// The settings live in UserDefaults as JSON, without any secret.
    static let settingsKey = "letterboxdSettings-v1"

    private(set) var settings: StremboxdSettings
    private(set) var session: StremboxdSession?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persistence: any StremboxdSessionPersistence
    @ObservationIgnored let transport: any StremboxdTransport

    init(defaults: UserDefaults = .standard, persistence: any StremboxdSessionPersistence = KeychainStremboxdSession(), transport: any StremboxdTransport = StremboxdHTTPTransport()) {
        self.defaults = defaults
        self.persistence = persistence
        self.transport = transport
        settings = Self.loadSettings(defaults)
        session = try? persistence.readSession()
    }

    static func loadSettings(_ defaults: UserDefaults) -> StremboxdSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let value = try? JSONDecoder().decode(StremboxdSettings.self, from: data) else { return StremboxdSettings() }
        return value
    }

    /// Desktop's `isActive`: enabled, and either a Public username or a signed-in Full account.
    var isActive: Bool {
        guard settings.enabled else { return false }
        switch settings.mode {
        case .full:
            return session != nil
        case .publicMode:
            return !settings.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The catalogs' source: the signed-in account when there is one, otherwise the public configuration.
    var source: StremboxdSource? {
        guard isActive else { return nil }
        if let session = session { return .full(session.userId) }
        guard let segment = configSegment else { return nil }
        return .config(segment)
    }

    var configSegment: String? {
        try? StremboxdConfigCodec.encode(StremboxdConfigCodec.publicConfig(settings))
    }

    func update(_ change: (inout StremboxdSettings) -> Void) {
        var next = settings
        change(&next)
        settings = next
        if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.settingsKey) }
    }

    func setSession(_ value: StremboxdSession?) throws {
        try persistence.writeSession(value)
        session = value
    }

    /// Desktop's `handleVerify`: checks a Public username and turns the integration on only when Stremboxd accepts it.
    func verifyPublic(username: String) async -> StremboxdVerification {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = settings
        candidate.username = name
        guard let segment = try? StremboxdConfigCodec.encode(StremboxdConfigCodec.publicConfig(candidate)) else {
            return .failed("Could not reach Stremboxd. Check your connection.")
        }
        let client = StremboxdClient(transport: transport)
        do {
            let manifest = try await client.manifest(.config(segment))
            switch StremboxdMapping.check(manifest: manifest, expectWatchlist: !name.isEmpty) {
            case .valid(let catalogs, _):
                update { (value: inout StremboxdSettings) in
                    value.enabled = true
                    value.mode = .publicMode
                    value.username = name
                }
                return .connected(catalogs: catalogs)
            case .invalid(let message):
                return .failed(message)
            }
        } catch let error as StremboxdError {
            return StremboxdVerification.forError(error)
        } catch {
            return .failed("Could not reach Stremboxd. Check your connection.")
        }
    }

    /// Desktop's `login`: signs in to Letterboxd through Stremboxd, then makes the account the full-mode source.
    /// The password is used for this request only.
    func signIn(username: String, password: String, code: String?) async -> StremboxdSignIn {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = StremboxdClient(transport: transport)
        do {
            let next = try await client.login(username: name, password: password, totp: code, loginAt: Date().timeIntervalSince1970 * 1_000)
            try setSession(next)
            update { (value: inout StremboxdSettings) in
                value.enabled = true
                value.mode = .full
                value.username = next.username
            }
            await syncPreferences()
            return .signedIn
        } catch let error as StremboxdError {
            if error.code == "2FA_REQUIRED" { return .needsCode }
            return .failed(error.message)
        } catch {
            return .failed("Could not reach Stremboxd. Check your connection.")
        }
    }

    /// Desktop's `disconnect`: forgets the token and returns to Public mode. The username stays.
    func signOut() {
        do { try setSession(nil) } catch { }
        update { (value: inout StremboxdSettings) in value.mode = .publicMode }
    }

    /// Desktop's `buildServerPreferences` sync, for a full-mode account only. Best effort, as on Desktop.
    func syncPreferences() async {
        guard let session = session, settings.mode == .full else { return }
        let client = StremboxdClient(transport: transport)
        let preferences = StremboxdMapping.preferences(selected: settings.selectedCatalogs, listRefs: settings.listRefs)
        do { try await client.updatePreferences(token: session.userToken, preferences: preferences) } catch { }
    }

    /// Desktop's "Add a list": resolves the address, then shows the list as its own row.
    func addList(_ address: String) async throws {
        let client = StremboxdClient(transport: transport)
        let ref = try await client.resolveList(address.trimmingCharacters(in: .whitespacesAndNewlines))
        let catalogID = StremboxdCatalogID.list(ref.id)
        update { (value: inout StremboxdSettings) in
            value.listRefs = value.listRefs.filter { $0.id != ref.id } + [ref]
            if !value.selectedCatalogs.contains(catalogID) { value.selectedCatalogs.append(catalogID) }
        }
    }

    func removeList(_ id: String) {
        let catalogID = StremboxdCatalogID.list(id)
        update { (value: inout StremboxdSettings) in
            value.listRefs.removeAll { $0.id == id }
            value.selectedCatalogs.removeAll { $0 == catalogID }
        }
    }

    func setCatalog(_ id: String, on: Bool) {
        update { (value: inout StremboxdSettings) in
            if on {
                if !value.selectedCatalogs.contains(id) { value.selectedCatalogs.append(id) }
            } else {
                value.selectedCatalogs.removeAll { $0 == id }
            }
        }
    }

    func unhide(_ id: String) {
        update { (value: inout StremboxdSettings) in value.hiddenCatalogs.removeAll { $0 == id } }
    }

    func setShowRatingsOnPosters(_ on: Bool) {
        update { (value: inout StremboxdSettings) in value.showRatingsOnPosters = on }
    }
}
