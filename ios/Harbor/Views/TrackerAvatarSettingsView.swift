import SwiftUI

/// Desktop's AniList comment and avatar options (`views/settings/anilist-panel.tsx`), opened from the AniList settings.
/// The Trakt, Simkl and MyAnimeList avatar options are not ported: iOS does not read those profile pictures yet.
struct TrackerAvatarSettingsView: View {
    let app: AppModel
    @Bindable private var preferences = AniListPreferences.shared

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text("Tracking what you watch")).font(HarborTheme.font(13, weight: .semibold)).foregroundStyle(.secondary)
                    HarborSettingsToggle("Use my AniList avatar as my Harbor avatar",
                                         note: "Show your AniList profile picture as your Harbor avatar.",
                                         isOn: $preferences.useAnilistAvatar)
                        .accessibilityIdentifier("anilist-avatar-toggle")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(text("Comments")).font(HarborTheme.font(13, weight: .semibold)).foregroundStyle(.secondary)
                    HarborSettingsToggle("Show AniList comments",
                                         note: "Show forum threads and comments from AniList on anime detail pages.",
                                         isOn: $preferences.showAnilistComments)
                        .accessibilityIdentifier("anilist-comments-toggle")
                    HarborSettingsToggle("Blur comments by default",
                                         note: "Comments on anime pages are blurred until you reveal them, even if they are not tagged as spoilers.",
                                         isOn: $preferences.anilistBlurComments)
                        .disabled(!preferences.showAnilistComments)
                        .accessibilityIdentifier("anilist-blur-toggle")
                    if !preferences.showAnilistComments {
                        Text(text("Turn on AniList comments first.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20).frame(maxWidth: 680, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
        .navigationTitle(text("Comments")).navigationBarTitleDisplayMode(.inline)
        .onChange(of: preferences.useAnilistAvatar) { _, on in
            if on { AniListAvatarSync.apply(owner: app.personalOwner) } else { AniListAvatarSync.clear(owner: app.personalOwner) }
        }
    }
}
