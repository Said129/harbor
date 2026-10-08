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
            Text(DesktopInterfaceText.value("When the Up Next pill appears before an episode ends. Auto scales to the episode length, so short episodes stop prompting so early. Off hides it."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HarborSettingsSegmented(selection: $preferences.options.nextEpisodeLeadSeconds, choices: choices)
                .accessibilityIdentifier("settings-next-prompt")
            HarborSettingsToggle(DesktopInterfaceText.value("Auto-play next episode"), note: DesktopInterfaceText.value("When an episode ends, automatically start the next one. Off lets the episode finish and stop."), isOn: $preferences.options.autoPlayNextEpisode)
                .accessibilityIdentifier("settings-auto-next")
            HarborSettingsToggle(DesktopInterfaceText.value("Keep same source on next episode"), note: DesktopInterfaceText.value("When auto-playing the next episode, keep the same release/source you were just watching instead of Harbor's top-ranked stream. Falls back to the best stream if that source isn't available."), isOn: $sources.keepSourceNextEpisode)
                .accessibilityIdentifier("settings-next-source")
        }
    }
}
