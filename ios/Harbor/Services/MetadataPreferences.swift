import Foundation
import Observation

struct MetadataConfiguration: Sendable {
    var tmdbKey: String
    var region: String
    var language: String
    var translateTitles: Bool
    var imageLanguages: [String] = ["English", "Original"]
    /// Desktop's `rpdbKey`: rated posters. Read from the Keychain store of the profile, empty when none is saved.
    var rpdbKey: String = ""
    /// Desktop's `fanartKey`: logos and backdrops. Read from the same Keychain store, empty when none is saved.
    var fanartKey: String = ""
    /// Desktop's `translateDescriptions`: plot text and tagline in the metadata language (on) or in English (off).
    var translateDescriptions = true
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
    var translateDescriptions = UserDefaults.standard.object(forKey: "metadata.translateDescriptions") as? Bool ?? true {
        didSet { persist(translateDescriptions, forKey: "metadata.translateDescriptions") }
    }
    var imageLanguages = UserDefaults.standard.stringArray(forKey: "tmdbImageLangs") ?? ["English", "Original"] {
        didSet { persist(imageLanguages, forKey: "tmdbImageLangs") }
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
    func configuration() -> MetadataConfiguration {
        var result = MetadataConfiguration(tmdbKey: tmdbKey, region: region, language: language, translateTitles: translateTitles, imageLanguages: imageLanguages)
        result.rpdbKey = savedArtworkKey(.rpdb)
        result.fanartKey = savedArtworkKey(.fanart)
        result.translateDescriptions = translateDescriptions
        return result
    }
    private func savedArtworkKey(_ provider: ArtworkKeyStore.Provider) -> String {
        guard let owner = settingsOwner else { return "" }
        let store = ArtworkKeyStore.forOwner(owner)
        if !store.ready { try? store.load() }
        return store.key(provider)
    }

    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        region = UserDefaults.standard.string(forKey: "metadata.region") ?? "US"
        language = UserDefaults.standard.string(forKey: "metadata.language") ?? "es-ES"
        translateTitles = UserDefaults.standard.object(forKey: "metadata.translateTitles") as? Bool ?? true
        translateDescriptions = UserDefaults.standard.object(forKey: "metadata.translateDescriptions") as? Bool ?? true
        imageLanguages = UserDefaults.standard.stringArray(forKey: "tmdbImageLangs") ?? ["English", "Original"]
    }
}
