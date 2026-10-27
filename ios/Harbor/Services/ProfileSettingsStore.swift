import Foundation
import Observation

struct ProfileSettingsDocument: Codable, Equatable, Sendable {
    var values: [String: Data] = [:]
    var tmdbKey: String?
    func validated() throws -> Self {
        guard Set(values.keys).isSubset(of: ProfileSettingsStore.keys),
              tmdbKey.map({ $0.utf8.count <= 8192 && $0.rangeOfCharacter(from: .controlCharacters) == nil }) ?? true,
              try JSONEncoder().encode(self).count <= 3 * 1_024 * 1_024 else { throw HarborError(code: "profile-settings") }
        for data in values.values { _ = try Self.value(data) }
        return self
    }
    static func value(_ data: Data) throws -> Any {
        guard data.count <= 1_024 * 1_024,
              let row = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], row.count == 1,
              let value = row["value"] else { throw HarborError(code: "profile-settings-value") }
        return value
    }
}
struct ProfileSettingsState: Codable, Equatable, Sendable {
    var version = 1
    var documents: [String: ProfileSettingsDocument] = [:]
    var legacyOwner: String?
    func validated() throws -> Self {
        guard version == 1, documents.keys.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 }),
              legacyOwner == nil || documents[legacyOwner!] != nil,
              try JSONEncoder().encode(self).count <= 16 * 1_024 * 1_024 else { throw HarborError(code: "profile-settings") }
        for document in documents.values { _ = try document.validated() }
        return self
    }
}
@MainActor protocol ProfileSettingsPersistence {
    func readProfileSettings() throws -> ProfileSettingsState?
    func writeProfileSettings(_ value: ProfileSettingsState) throws
}
@MainActor private struct KeychainProfileSettings: ProfileSettingsPersistence {
    func readProfileSettings() throws -> ProfileSettingsState? { try KeychainStore().read("native-profile-settings-v1", as: ProfileSettingsState.self) }
    func writeProfileSettings(_ value: ProfileSettingsState) throws { try KeychainStore().write(value, key: "native-profile-settings-v1") }
}

/// Desktop keeps an active settings mirror and one document per independent
/// profile, with a shared document for linked profiles. Save the previous mirror
/// and prepare the next document atomically before changing any visible values.
@MainActor @Observable final class ProfileSettingsStore {
    static let shared = ProfileSettingsStore()
    nonisolated static let keys: Set<String> = [
        "uiLanguage", "navIconAnimations", "interface.autoRotateBanners", "homeMode", "showImdbBadge", "showTmdbBadge",
        "rowCardStyle", "tvCardLogoPos", "posterScale", "posterRadius", "posterEffect", "posterQuality",
        "posterFocusedCard", "posterBackdropExpansion", "posterDockMagnification", "posterDockTransitionMs",
        "simklEnableUserRatings", "simklScrobbleEnabled", "cwSources",
        "tmdbImageLangs", "harbor:title-logos", "harbor:title-posters", "harbor:title-backdrops",
        "showWatchedButton", "showEpisodeDescription", "hideSpoilers", "blurEpisodes", "spoilerHideTitles", "spoilerHideDescriptions",
        "iphone.theme.preset", "iphone.theme.custom", "iphone.theme.font", "iphone.theme.colors", "seekBarColor",
        "iphone.player-options.v1", "mpvHwdec", "resumePlayback", "resumePrompt", "subtitleAutoSync",
        "streamFilterLevel", "streams.addonOrder", "streams.automatic", "keepSourceNextEpisode", "streams.excludeCamera", "streams.maximum", "streams.minimum",
        "pluginsEnabled", "pluginsGroupByRepo", "blockTrackers", "hideContent.adult",
        "metadata.region", "metadata.language", "metadata.translateTitles", "cwPerProfile", "downloadsCellular",
        "profilePromptInterval", "defaultProfileId", "tvdbSeasonType", "tvdbOrderPanel",
        "calendar.monday", "calendar.large", "ebook.fontSize", "ebook.lineHeight", "ebook.margin", "ebook.background", "ebook.font", "ebook.direction",
        "ebook.narrationRate", "ebook.narrationVoice", "ebook.deviceNarrationVoice", "ebook.narrationProvider", "ebook.narrationSpeed", "ebook.shelfSort", "ebook.pdf.horizontal", "ebook.width", "ebook.brightness", "ebook.focusMode", "ebook.customFontID", "ebook.mode", "harbor.ebook.chapterview", "manga.reader.mode", "manga.reader.fit", "manga.reader.background",
        "manga.reader.rtl", "manga.reader.zoom", "manga.reader.autoNextChapter", "manga.reader.navPos", "manga.reader.doubleGap", "manga.reader.focusMode",
        "manga.reader.hideChapterEndHint", "manga.reader.enablePageDownload", "manga.reader.flipSound", "manga.adultSources", "manga.shelfSort",
        "harbor.music.playlistView", "harbor.music.tab", "harbor.music.genres.explore.v1", "music.shuffle", "music.repeat", "music.volume"
    ]
    private let defaults: UserDefaults
    private let persistence: any ProfileSettingsPersistence
    private var state = ProfileSettingsState()
    private var applying = false
    private(set) var owner: String?
    private(set) var ready = false
    private(set) var error: String?
    init(defaults: UserDefaults = .standard, persistence: (any ProfileSettingsPersistence)? = nil) {
        self.defaults = defaults; self.persistence = persistence ?? KeychainProfileSettings()
        reloadIfUnavailable()
    }
    func reloadIfUnavailable() {
        guard !ready, owner == nil else { return }
        do { state = try (self.persistence.readProfileSettings() ?? ProfileSettingsState()).validated(); ready = true }
        catch { self.error = "Could not load profile settings. Saved settings are kept." }
    }
    private func capture(preserving previous: ProfileSettingsDocument? = nil) throws -> ProfileSettingsDocument {
        var document = previous ?? ProfileSettingsDocument(); document.values = [:]
        for key in Self.keys {
            if let value = defaults.object(forKey: key) {
                document.values[key] = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
            }
        }
        return try document.validated()
    }
    private func commit(_ next: ProfileSettingsState) throws {
        let next = try next.validated()
        if state != next { try persistence.writeProfileSettings(next); state = next }
    }
    func activate(owner nextOwner: String, sharedOwner: String, migrateLegacy: Bool, legacyTMDB: (() throws -> String?)? = nil) throws {
        guard ready, !nextOwner.isEmpty, nextOwner.utf8.count <= 512, !sharedOwner.isEmpty, sharedOwner.utf8.count <= 512 else { throw HarborError(code: "profile-settings") }
        do {
            var next = state
            if let owner { next.documents[owner] = try capture(preserving: next.documents[owner]) }
            if migrateLegacy && next.legacyOwner == nil && next.documents[sharedOwner] == nil {
                var document = try capture(); document.tmdbKey = try legacyTMDB?()
                next.documents[sharedOwner] = try document.validated(); next.legacyOwner = sharedOwner
            }
            if next.documents[nextOwner] == nil { next.documents[nextOwner] = next.documents[sharedOwner] ?? ProfileSettingsDocument() }
            let target = try next.documents[nextOwner]!.validated()
            let decoded = try target.values.mapValues(ProfileSettingsDocument.value)
            try commit(next)
            if owner == nextOwner { error = nil; return }
            applying = true
            for key in Self.keys {
                if let value = decoded[key] { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
            owner = nextOwner; applying = false; error = nil
        } catch { self.error = "Could not change profile settings. Saved settings are kept."; throw error }
    }
    @discardableResult func saveCurrent() -> Bool {
        guard ready, !applying, let owner else { return false }
        do { var next = state; next.documents[owner] = try capture(preserving: next.documents[owner]); try commit(next); error = nil; return true }
        catch { self.error = "Could not save profile settings. The previous saved values are kept."; return false }
    }
    func launchPreferences(sharedOwner: String) throws -> ProfileLaunchPreferences {
        guard ready, !sharedOwner.isEmpty, sharedOwner.utf8.count <= 512 else { throw HarborError(code: "profile-settings") }
        let document = owner == sharedOwner ? try capture(preserving: state.documents[sharedOwner]) : state.documents[sharedOwner]
        let values = try document?.values.mapValues(ProfileSettingsDocument.value) ?? [:]
        let interval = (values["profilePromptInterval"] as? String).flatMap(ProfileLaunchPreferences.Interval.init(rawValue:)) ?? .launch
        let result = ProfileLaunchPreferences(interval: interval, defaultID: values["defaultProfileId"] as? String ?? "")
        return result.valid ? result : ProfileLaunchPreferences(interval: interval)
    }
    func setLaunchPreferences(_ preferences: ProfileLaunchPreferences, sharedOwner: String, expectedOwner: String) throws {
        guard ready, owner == expectedOwner, !sharedOwner.isEmpty, sharedOwner.utf8.count <= 512, preferences.valid else { throw HarborError(code: "profile-settings-changed") }
        var next = state
        var document = owner == sharedOwner ? try capture(preserving: next.documents[sharedOwner]) : next.documents[sharedOwner] ?? ProfileSettingsDocument()
        for (key, value) in ["profilePromptInterval": preferences.interval.rawValue, "defaultProfileId": preferences.defaultID] {
            document.values[key] = try PropertyListSerialization.data(fromPropertyList: ["value": value], format: .binary, options: 0)
        }
        next.documents[sharedOwner] = try document.validated()
        try commit(next)
        if owner == sharedOwner {
            applying = true
            defaults.set(preferences.interval.rawValue, forKey: "profilePromptInterval")
            defaults.set(preferences.defaultID, forKey: "defaultProfileId")
            applying = false
        }
        error = nil
    }
    func tmdbKey(expectedOwner: String) throws -> String {
        guard ready, owner == expectedOwner, let document = state.documents[expectedOwner] else { throw HarborError(code: "profile-settings-changed") }
        return document.tmdbKey ?? ""
    }
    func setTMDBKey(_ value: String, expectedOwner: String) throws {
        guard ready, owner == expectedOwner, let previous = state.documents[expectedOwner] else { throw HarborError(code: "profile-settings-changed") }
        var next = state, document = try capture(preserving: previous)
        document.tmdbKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        next.documents[expectedOwner] = try document.validated()
        try commit(next); error = nil
    }
}
