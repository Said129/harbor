import Foundation
import Observation

/// Desktop's AniList comment and avatar settings (`lib/settings/defaults.ts`: all default to off). The keys are
/// Desktop's, and ProfileSettingsStore keeps them per profile. Call `reloadPreferences()` after a profile switch.
@MainActor @Observable
final class AniListPreferences {
    static let shared = AniListPreferences()
    /// Desktop's `showAnilistComments`: the AniList Comments section on anime pages.
    var showAnilistComments = UserDefaults.standard.object(forKey: "showAnilistComments") as? Bool ?? false { didSet { persist(showAnilistComments, forKey: "showAnilistComments") } }
    /// Desktop's `anilistBlurComments`: comments stay blurred until revealed, spoiler or not.
    var anilistBlurComments = UserDefaults.standard.object(forKey: "anilistBlurComments") as? Bool ?? false { didSet { persist(anilistBlurComments, forKey: "anilistBlurComments") } }
    /// Desktop's `useAnilistAvatar`: the AniList profile picture is the Harbor avatar.
    var useAnilistAvatar = UserDefaults.standard.object(forKey: "useAnilistAvatar") as? Bool ?? false { didSet { persist(useAnilistAvatar, forKey: "useAnilistAvatar") } }

    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        showAnilistComments = UserDefaults.standard.object(forKey: "showAnilistComments") as? Bool ?? false
        anilistBlurComments = UserDefaults.standard.object(forKey: "anilistBlurComments") as? Bool ?? false
        useAnilistAvatar = UserDefaults.standard.object(forKey: "useAnilistAvatar") as? Bool ?? false
    }
}

/// Which picture the profile should show for a tracker. Pure, so the rules are testable without a profile.
@MainActor enum TrackerAvatarResolver {
    /// Desktop's `AnilistAvatarSync`: the AniList picture while the setting is on, if the URL is one a profile can show.
    static func profileAvatar(enabled: Bool, anilistAvatar: String?) -> String? {
        guard enabled, let url = anilistAvatar?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
              HouseholdAppearanceBinding.remoteAvatar(url) else { return nil }
        return url
    }

    /// Desktop's toggle-off (`toggleAnilistAvatar`): the picture is cleared only while it is still this tracker's.
    static func shouldClear(profileAvatar: String?, anilistAvatar: String?) -> Bool {
        guard let profileAvatar, let anilistAvatar else { return false }
        return profileAvatar == anilistAvatar
    }
}

/// Writes the AniList picture into the profile, as Desktop's `AnilistAvatarSync` and the avatar toggle do.
/// Remote pictures are kept on this device only (HarborProfileSync sends bundled avatars to the cloud).
@MainActor enum AniListAvatarSync {
    /// Run when the setting is on, after a profile switch or launch, so the picture follows a refreshed AniList avatar.
    static func apply(owner: String, preferences: AniListPreferences = .shared) {
        let account = AniListAccount.forOwner(owner)
        if !account.ready { try? account.load() }
        guard let url = TrackerAvatarResolver.profileAvatar(enabled: preferences.useAnilistAvatar, anilistAvatar: account.session?.avatar) else { return }
        let profile = ProfilePreferences.forOwner(owner)
        guard profile.value.remoteAvatar != url else { return }
        profile.update { $0.remoteAvatar = url; $0.photo = nil; $0.initialsAvatar = false }
    }

    /// Run when the setting is switched off: removes the picture only if it is still the AniList one.
    static func clear(owner: String) {
        let account = AniListAccount.forOwner(owner)
        let profile = ProfilePreferences.forOwner(owner)
        guard TrackerAvatarResolver.shouldClear(profileAvatar: profile.value.remoteAvatar, anilistAvatar: account.session?.avatar) else { return }
        profile.update { $0.remoteAvatar = nil }
    }
}
