import Foundation
import Observation

struct MetadataConfiguration: Sendable {
    var tmdbKey: String
    var region: String
    var language: String
    var translateTitles: Bool
}

@MainActor @Observable
final class MetadataPreferences {
    static let shared = MetadataPreferences()
    private var scopedSettings: ProfileSettingsStore?
    private(set) var settingsOwner: String?
    private(set) var tmdbKey = ""
    var error: String?
    var region = UserDefaults.standard.string(forKey: "metadata.region") ?? "US" {
        didSet { persist(region, forKey: "metadata.region") }
    }
    var language = UserDefaults.standard.string(forKey: "metadata.language") ?? "es-ES" {
        didSet { persist(language, forKey: "metadata.language") }
    }
    var translateTitles = UserDefaults.standard.object(forKey: "metadata.translateTitles") as? Bool ?? true {
        didSet { persist(translateTitles, forKey: "metadata.translateTitles") }
    }
    func bind(_ settings: ProfileSettingsStore) throws {
        guard let owner = settings.owner else { throw HarborError(code: "profile-settings") }
        let key = try settings.tmdbKey(expectedOwner: owner)
        scopedSettings = settings; settingsOwner = owner; tmdbKey = key; error = nil
    }
    func save(_ value: String, expectedOwner: String) throws {
        guard let scopedSettings, settingsOwner == expectedOwner else { throw HarborError(code: "profile-settings-changed") }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try scopedSettings.setTMDBKey(key, expectedOwner: expectedOwner)
        tmdbKey = key; error = nil
    }
    func configuration() -> MetadataConfiguration { MetadataConfiguration(tmdbKey: tmdbKey, region: region, language: language, translateTitles: translateTitles) }

    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        region = UserDefaults.standard.string(forKey: "metadata.region") ?? "US"
        language = UserDefaults.standard.string(forKey: "metadata.language") ?? "es-ES"
        translateTitles = UserDefaults.standard.object(forKey: "metadata.translateTitles") as? Bool ?? true
    }
}
