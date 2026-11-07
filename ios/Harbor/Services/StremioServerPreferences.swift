import Foundation
import Observation

/// Desktop's remote streaming server settings (`lib/settings/defaults.ts`, `lib/settings/types.ts`): the saved
/// address, the strict policy and the two transcode switches. The keys are per profile through
/// `ProfileSettingsStore.keys`, and the values are read with the same names Desktop uses.
@MainActor @Observable
final class StremioServerPreferences {
    static let shared = StremioServerPreferences()

    /// Desktop default "" (`remoteStreamServerUrl`). The settings row stores the normalized address.
    var remoteStreamServerUrl = UserDefaults.standard.string(forKey: "remoteStreamServerUrl") ?? "" {
        didSet { persist(remoteStreamServerUrl, forKey: "remoteStreamServerUrl") }
    }
    /// Desktop default false (`remoteStreamServerStrict`). It only applies while an address is saved.
    var remoteStreamServerStrict = UserDefaults.standard.object(forKey: "remoteStreamServerStrict") as? Bool ?? false {
        didSet { persist(remoteStreamServerStrict, forKey: "remoteStreamServerStrict") }
    }
    /// Desktop default true (`castAlwaysTranscode`). Stored for parity only: Desktop never reads it and iOS has no Cast pipeline yet.
    var castAlwaysTranscode = UserDefaults.standard.object(forKey: "castAlwaysTranscode") as? Bool ?? true {
        didSet { persist(castAlwaysTranscode, forKey: "castAlwaysTranscode") }
    }
    /// Desktop default false (`stremioServerTranscode`): a decode failure retries through the server's HLS transcode.
    var stremioServerTranscode = UserDefaults.standard.object(forKey: "stremioServerTranscode") as? Bool ?? false {
        didSet { persist(stremioServerTranscode, forKey: "stremioServerTranscode") }
    }

    /// The saved address without trailing slashes, or "" when none is saved.
    var address: String { StremioServerPolicy.storedAddress(remoteStreamServerUrl) }
    /// Desktop's `remoteStreamServerStrict()`.
    var strict: Bool { StremioServerPolicy.isStrict(address: remoteStreamServerUrl, flag: remoteStreamServerStrict) }

    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }

    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        remoteStreamServerUrl = UserDefaults.standard.string(forKey: "remoteStreamServerUrl") ?? ""
        remoteStreamServerStrict = UserDefaults.standard.object(forKey: "remoteStreamServerStrict") as? Bool ?? false
        castAlwaysTranscode = UserDefaults.standard.object(forKey: "castAlwaysTranscode") as? Bool ?? true
        stremioServerTranscode = UserDefaults.standard.object(forKey: "stremioServerTranscode") as? Bool ?? false
    }
}
