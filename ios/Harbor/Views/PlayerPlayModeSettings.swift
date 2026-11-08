import SwiftUI

struct PlayerPlayModeSettings: View {
    @Binding var automatic: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HarborSettingsSection(DesktopInterfaceText.value("Playback")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(DesktopInterfaceText.value("When you press Play")).font(HarborTheme.font(15, weight: .semibold))
                Text(DesktopInterfaceText.value("Instant starts the best-ranked stream straight away. Pick a source opens the stream list every time, so you choose the release, quality and provider yourself."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HarborSettingsSegmented(selection: $automatic, choices: [(DesktopInterfaceText.value("Instant"), true), (DesktopInterfaceText.value("Pick a source"), false)])
                    .accessibilityIdentifier("settings-play-mode")
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geometry in
                        ZStack {
                            Image("play-mode-preview").resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                                .overlay { LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom) }
                                .overlay { Image("ui-play-filled").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white) }
                                .overlay(alignment: .bottomLeading) {
                                    Capsule().fill(HarborTheme.background.opacity(0.7)).frame(height: 4)
                                        .overlay(alignment: .leading) { Capsule().fill(HarborTheme.accent).frame(width: geometry.size.width * 0.84 * 0.38) }
                                        .padding(.horizontal, geometry.size.width * 0.08).padding(.bottom, geometry.size.height * 0.12)
                                }.opacity(automatic ? 1 : 0)
                            VStack(spacing: 6) {
                                ForEach(["1080p", "720p", "480p"], id: \.self) { quality in
                                    HStack(spacing: 8) {
                                        Text("Steamboat Willie").font(HarborTheme.font(11, weight: .medium))
                                        Spacer(minLength: 0)
                                        Text(quality).font(HarborTheme.font(10)).monospacedDigit().foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                                    }.padding(.horizontal, 8).frame(height: geometry.size.height * 0.23)
                                        .background(ThemePreferences.shared.color(quality == "1080p" ? "accent-soft" : "elevated"), in: .rect(cornerRadius: 4))
                                }
                            }.padding(.horizontal, geometry.size.width * 0.08).opacity(automatic ? 0 : 1)
                        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: automatic)
                    }.aspectRatio(16.0 / 9, contentMode: .fit).frame(maxWidth: 260)
                        .background(HarborTheme.background).clipShape(.rect(cornerRadius: 6))
                        .overlay { RoundedRectangle(cornerRadius: 6).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }.accessibilityHidden(true)
                    Text(DesktopInterfaceText.value(automatic ? "Play starts the best-ranked stream straight away." : "Play opens the stream list so you pick the release yourself."))
                        .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(14).background(HarborTheme.background.opacity(0.4), in: .rect(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
            }
        }
    }
}

struct PlayerNextEpisodeSettings: View {
    @Bindable private var preferences = PlaybackPreferences.shared
    @Bindable private var sources = StreamPreferences.shared
    private var choices: [(String, Double)] {
        [(DesktopInterfaceText.value("Auto"), -1), (DesktopInterfaceText.value("Off"), 0), ("30s", 30), ("45s", 45), (DesktopInterfaceText.value("1 min"), 60), (DesktopInterfaceText.value("1.5 min"), 90), (DesktopInterfaceText.value("2 min"), 120)]
            + (preferences.options.nextEpisodeLeadSeconds == 15 ? [("15s", 15)] : [])
    }
    var body: some View {
        HarborSettingsSection(DesktopInterfaceText.value("Next episode prompt")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Show the Skip button"), note: DesktopInterfaceText.value("Show a Skip Intro / Skip Credits button when Harbor detects one. Turn this off to never show it. You can also tap the X on the button to dismiss a wrong one for the rest of the episode."), isOn: $preferences.options.showSkipIntro)
                .accessibilityIdentifier("settings-skip-intro")
            HarborSettingsToggle(DesktopInterfaceText.value("Auto-skip intros"), note: DesktopInterfaceText.value("Jump past openings automatically the moment one starts. Seeking back into an intro replays it without skipping again. The Skip button follows the setting above."), isOn: $preferences.options.autoSkipIntro)
                .accessibilityIdentifier("settings-auto-skip-intro")
            HarborSettingsToggle(DesktopInterfaceText.value("Auto-skip recaps"), note: DesktopInterfaceText.value("Automatically jump past recap segments."), isOn: $preferences.options.autoSkipRecap)
                .accessibilityIdentifier("settings-auto-skip-recap")
            HarborSettingsToggle(DesktopInterfaceText.value("Auto-skip credit outros"), note: DesktopInterfaceText.value("Automatically skip ending credits and trigger the next episode countdown immediately."), isOn: $preferences.options.autoSkipOutro)
                .accessibilityIdentifier("settings-auto-skip-outro")
            if let owner = MetadataPreferences.shared.settingsOwner {
                TheIntroDBKeyField(owner: owner)
            }
            if preferences.options.showSkipIntro {
                Text(DesktopInterfaceText.value("Auto-hide the Skip button after")).font(HarborTheme.font(14, weight: .semibold))
                Text(DesktopInterfaceText.value("Hides the button on its own after a few seconds so a wrong one doesn't sit there the whole episode."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HarborSettingsSegmented(selection: $preferences.options.skipButtonHideSeconds, choices: [(DesktopInterfaceText.value("Off"), 0), ("5s", 5), ("10s", 10), ("15s", 15), ("30s", 30)])
                    .accessibilityIdentifier("settings-skip-hide")
            }
            Text(DesktopInterfaceText.value("When the Up Next pill appears before an episode ends. Auto scales to the episode length, so short episodes stop prompting so early. Off hides it."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HarborSettingsSegmented(selection: $preferences.options.nextEpisodeLeadSeconds, choices: choices)
                .accessibilityIdentifier("settings-next-prompt")
            HarborSettingsToggle(DesktopInterfaceText.value("Auto-play next episode"), note: DesktopInterfaceText.value("When an episode ends, automatically start the next one. Off lets the episode finish and stop."), isOn: $preferences.options.autoPlayNextEpisode)
                .accessibilityIdentifier("settings-auto-next")
            if preferences.options.autoPlayNextEpisode {
                HarborSettingsToggle(DesktopInterfaceText.value("Ask if you're still watching"), note: DesktopInterfaceText.value("After several episodes auto-play in a row with no input, pause and check you're still there before continuing. Off by default."), isOn: $preferences.options.stillWatching)
                    .accessibilityIdentifier("settings-still-watching")
            }
            if preferences.options.autoPlayNextEpisode && preferences.options.stillWatching {
                Text(DesktopInterfaceText.value("Still watching check-in")).font(HarborTheme.font(14, weight: .semibold))
                Text(DesktopInterfaceText.value("How many episodes auto-play back to back before Harbor pauses to ask."))
                    .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HarborSettingsSegmented(selection: $preferences.options.stillWatchingAfter, choices: [2, 3, 4, 5].map { (DesktopInterfaceText.value("After \($0)"), $0) })
                    .accessibilityIdentifier("settings-still-watching-after")
            }
            HarborSettingsToggle(DesktopInterfaceText.value("Keep same source on next episode"), note: DesktopInterfaceText.value("When auto-playing the next episode, keep the same release/source you were just watching instead of Harbor's top-ranked stream. Falls back to the best stream if that source isn't available."), isOn: $sources.keepSourceNextEpisode)
                .accessibilityIdentifier("settings-next-source")
            HarborSettingsToggle(DesktopInterfaceText.value("Remember last stream"), note: DesktopInterfaceText.value("When you resume something you were watching, replay the exact stream you last used (same addon and source) instead of opening the picker again. Turn off to always choose fresh."), isOn: $sources.rememberLastStream)
                .accessibilityIdentifier("settings-remember-stream")
        }
    }
}

/// Desktop's "Injected ad skip (experimental)" (`views/settings/quality-panel/ad-skip-tab.tsx`). The auto-skip switch
/// only shows while ad skip is on.
struct PlayerAdSkipSettings: View {
    @Bindable private var sources = StreamPreferences.shared

    var body: some View {
        HarborSettingsSection(DesktopInterfaceText.value("Injected ad skip (experimental)"), note: DesktopInterfaceText.value("Some cam and new-release rips have ads spliced into the video itself. When the community has marked one, a Skip button appears. You can also report ads you spot for review. Off by default.")) {
            HarborSettingsToggle(DesktopInterfaceText.value("Enable injected ad skip"), note: DesktopInterfaceText.value("Show a Skip button when a known injected ad plays, and a small report button on new releases so you can mark ads for review."), isOn: $sources.adSkipEnabled)
                .accessibilityIdentifier("settings-ad-skip")
            if sources.adSkipEnabled {
                HarborSettingsToggle(DesktopInterfaceText.value("Skip injected ads automatically"), note: DesktopInterfaceText.value("Jump past a known injected ad on its own instead of showing the Skip button."), isOn: $sources.autoSkipAd)
                    .accessibilityIdentifier("settings-auto-skip-ad")
            }
        }
    }
}
