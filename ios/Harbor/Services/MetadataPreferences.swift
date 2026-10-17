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
    private let keychain = KeychainStore()
    private(set) var tmdbKey = ""
    var error: String?
    var region = UserDefaults.standard.string(forKey: "metadata.region") ?? "US" {
        didSet { UserDefaults.standard.set(region, forKey: "metadata.region") }
    }
    var language = UserDefaults.standard.string(forKey: "metadata.language") ?? "es-ES" {
        didSet { UserDefaults.standard.set(language, forKey: "metadata.language") }
    }
    var translateTitles = UserDefaults.standard.object(forKey: "metadata.translateTitles") as? Bool ?? true {
        didSet { UserDefaults.standard.set(translateTitles, forKey: "metadata.translateTitles") }
    }
    func load() {
        do { tmdbKey = try keychain.read("metadata.tmdb.v1", as: String.self) ?? ""; error = nil }
        catch { self.error = safeMessage(error) }
    }
    func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { try keychain.remove("metadata.tmdb.v1") }
        else { try keychain.write(key, key: "metadata.tmdb.v1") }
        tmdbKey = key; error = nil
    }
    func configuration() -> MetadataConfiguration { MetadataConfiguration(tmdbKey: tmdbKey, region: region, language: language, translateTitles: translateTitles) }
}
