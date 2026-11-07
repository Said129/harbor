import Foundation
import Observation

/// Watch Together settings. The three Desktop keys (`togetherRelayUrl`, `togetherShareCursors`, `togetherGuestsPick`)
/// live in UserDefaults under Desktop's names, so the profile settings mirror saves and restores them. The client
/// identity is per install, as Desktop keeps it in localStorage. Call `reloadPreferences()` after a profile switch.
@MainActor @Observable final class TogetherPreferences {
    static let shared = TogetherPreferences()

    enum Key {
        static let relayURL = "togetherRelayUrl"
        static let shareCursors = "togetherShareCursors"
        static let guestsPick = "togetherGuestsPick"
        static let clientID = "harbor.together.clientId"
        static let displayName = "harbor.together.name"
    }

    /// Desktop `defaults.ts`: Watch Together is off until a relay is chosen.
    static let defaultRelayURL = ""
    static let defaultShareCursors = true
    static let defaultGuestsPick = false

    private let defaults: UserDefaults
    private(set) var relayURL = TogetherPreferences.defaultRelayURL
    /// Stored only. Cursors are not shown on iPhone or iPad.
    private(set) var shareCursors = TogetherPreferences.defaultShareCursors
    private(set) var guestsPick = TogetherPreferences.defaultGuestsPick
    private(set) var clientID = ""
    private(set) var displayName = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reloadPreferences()
    }

    func reloadPreferences() {
        relayURL = defaults.string(forKey: Key.relayURL) ?? TogetherPreferences.defaultRelayURL
        shareCursors = defaults.object(forKey: Key.shareCursors) as? Bool ?? TogetherPreferences.defaultShareCursors
        guestsPick = defaults.object(forKey: Key.guestsPick) as? Bool ?? TogetherPreferences.defaultGuestsPick
        let storedID = defaults.string(forKey: Key.clientID) ?? ""
        if storedID.isEmpty {
            let fresh = UUID().uuidString
            defaults.set(fresh, forKey: Key.clientID)
            clientID = fresh
        } else {
            clientID = storedID
        }
        let storedName = defaults.string(forKey: Key.displayName) ?? ""
        if storedName.isEmpty {
            let generated = TogetherPreferences.generatedName()
            defaults.set(generated, forKey: Key.displayName)
            displayName = generated
        } else {
            displayName = storedName
        }
    }

    func setRelayURL(_ value: String) {
        let trimmed = value.togetherTrimmed
        relayURL = trimmed
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Key.relayURL)
        } else {
            defaults.set(trimmed, forKey: Key.relayURL)
        }
    }

    func setShareCursors(_ value: Bool) {
        shareCursors = value
        defaults.set(value, forKey: Key.shareCursors)
    }

    func setGuestsPick(_ value: Bool) {
        guestsPick = value
        defaults.set(value, forKey: Key.guestsPick)
    }

    /// Desktop `setDisplayName`: at most 32 characters, and an empty name becomes a generated guest name.
    func setDisplayName(_ value: String) {
        let trimmed = String(value.togetherTrimmed.prefix(32))
        let next = trimmed.isEmpty ? TogetherPreferences.generatedName() : trimmed
        displayName = next
        defaults.set(next, forKey: Key.displayName)
    }

    static func generatedName() -> String {
        "Guest \(Int.random(in: 1000...9999))"
    }
}
