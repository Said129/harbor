import SwiftUI

/// Desktop's hero and detail trailer toggles (`src/views/settings/library-panel/home-tab.tsx`, `quality-panel/trailers-tab.tsx`).
struct HeroTrailerSettingsView: View {
    @Bindable var preferences = HeroTrailerPreferences.shared
    @Bindable var layout = HeroLayoutPreferences.shared
    /// Desktop's Featured source values, in the order of `home-tab.tsx` (lines 46-53). The labels are localized by the picker.
    private var feedChoices: [(String, HeroLayoutPolicy.HeroFeed)] {
        [("Trending", .trending), ("Trakt", .trakt), ("Simkl", .simkl), ("Classic", .classic)]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HarborSettingsSection(DesktopInterfaceText.value("Home hero"), note: DesktopInterfaceText.value("Make the featured banner on Home bigger and sharper.")) {
                    HarborSettingsChoice(DesktopInterfaceText.value("Featured source"), selection: $layout.feed, choices: feedChoices, identifier: "settings-hero-feed")
                    Text(DesktopInterfaceText.value("What fills the hero. Trending is a fresh top list from Harbor, refreshed through the day. Classic uses your own Home rows."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HarborSettingsToggle(DesktopInterfaceText.value("Full hero banner"), note: DesktopInterfaceText.value("Stretch the featured hero edge to edge and taller, across every layout."), isOn: $layout.full)
                        .accessibilityIdentifier("settings-hero-full")
                    HarborSettingsToggle(DesktopInterfaceText.value("Full quality hero image"), note: DesktopInterfaceText.value("Load the highest-resolution artwork for the featured hero. Uses more bandwidth."), isOn: $layout.fullQuality)
                        .accessibilityIdentifier("settings-hero-full-quality")
                }
                HarborSettingsSection(DesktopInterfaceText.value("Home hero shadow"), note: DesktopInterfaceText.value("How dark the gradient behind the featured title on Home is. 100% is the classic look.")) {
                    shadowSlider
                }
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

    /// Desktop's Shadow strength slider (`home-tab.tsx` lines 112-123): 0 to 100 in steps of 5, with a percent readout.
    private var shadowSlider: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(DesktopInterfaceText.value("Shadow strength")).font(HarborTheme.font(14, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(layout.shadowPercent)%").font(HarborTheme.font(14, weight: .semibold)).monospacedDigit()
            }
            Slider(value: $layout.shadowStrength, in: 0...100, step: 5)
                .tint(HarborTheme.ink)
                .accessibilityLabel(DesktopInterfaceText.value("Shadow strength"))
                .accessibilityValue("\(layout.shadowPercent)%")
                .accessibilityIdentifier("settings-hero-shadow")
            Text(DesktopInterfaceText.value("Lower it to let more of the artwork show through."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
