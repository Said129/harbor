import SwiftUI

/// Desktop's hero and detail trailer toggles (`src/views/settings/library-panel/home-tab.tsx`, `quality-panel/trailers-tab.tsx`).
struct HeroTrailerSettingsView: View {
    @Bindable var preferences = HeroTrailerPreferences.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HarborSettingsSection(DesktopInterfaceText.value("Hero trailers")) {
                    HarborSettingsToggle(DesktopInterfaceText.value("Play trailers in the hero"), note: DesktopInterfaceText.value("After a moment on a slide, the featured title's trailer plays muted in the background. Uses more bandwidth."), isOn: $preferences.heroTrailers)
                        .accessibilityIdentifier("settings-hero-trailers")
                    if preferences.heroTrailers {
                        HarborSettingsToggle(DesktopInterfaceText.value("Home hero audio"), isOn: $preferences.heroTrailerAudio)
                            .accessibilityIdentifier("settings-hero-trailer-audio")
                    }
                    HarborSettingsToggle(DesktopInterfaceText.value("Auto-play trailer on detail pages"), isOn: $preferences.detailTrailerAutoplay)
                        .accessibilityIdentifier("settings-detail-trailer-autoplay")
                    if preferences.detailTrailerAutoplay {
                        HarborSettingsToggle(DesktopInterfaceText.value("Start trailers with audio"), isOn: $preferences.detailTrailerAudio)
                            .accessibilityIdentifier("settings-detail-trailer-audio")
                    }
                }
            }.padding(20)
        }.background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("Hero trailers"))
            .navigationBarTitleDisplayMode(.inline).tint(HarborTheme.accent)
            .accessibilityIdentifier("hero-trailer-settings-scroll")
    }
}
