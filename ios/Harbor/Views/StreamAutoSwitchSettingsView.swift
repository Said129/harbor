import SwiftUI

/// Desktop's "Streams" group (`views/settings/player-panel/play-mode-section.tsx`): switching to the next
/// stream when one does not start, and staying on one source for a season.
struct StreamAutoSwitchSettingsView: View {
    @Bindable private var preferences = StreamAutoSwitchPreferences.shared
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    private var waitChoices: [(String, Int)] {
        StreamStallPolicy.waitChoices.map { seconds in
            let label = seconds >= 60 ? text("1 min") : DesktopInterfaceText.value("{n} sec", variables: ["n": String(seconds)])
            return (label, seconds)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HarborSettingsSection(text("Streams")) {
                    HarborSettingsToggle(text("Auto-skip stalled streams"),
                                         note: text("If a stream hasn't started playing in time (a dead source or an addon that's down), automatically try the next available stream. Off by default."),
                                         isOn: $preferences.autoNextOnStall)
                        .accessibilityIdentifier("settings-auto-skip-stalled")
                    if preferences.autoNextOnStall { waitSetting }
                    HarborSettingsToggle(text("Stay on one source for a season"),
                                         note: text("For series and anime, keep playing the rest of the season from the release you first picked. Applies whether Play is instant or manual."),
                                         isOn: $preferences.seasonSourceLock)
                        .accessibilityIdentifier("settings-season-source-lock")
                }
            }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink).buttonStyle(.plain)
            .navigationTitle(text("Streams")).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("stream-auto-switch-settings")
    }

    private var waitSetting: some View {
        VStack(alignment: .leading, spacing: 10) {
            HarborSettingsChoice(text("How long to wait first"), selection: $preferences.stallWaitSeconds, choices: waitChoices,
                                 localizeChoices: false, identifier: "settings-stall-wait")
            Text(text("Slow addons and P2P sources often need more than 10 seconds to start. Raise this if streams are being skipped before they get a fair chance."))
                .font(HarborTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
