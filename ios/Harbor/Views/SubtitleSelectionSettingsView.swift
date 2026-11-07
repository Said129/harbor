import SwiftUI

/// Desktop's "Choosing a track", "Skip these tracks", "Normalize embedded subtitle size" and "Second line size" settings (`views/settings/language-panel/subtitles-tab.tsx`, `audio-tab.tsx`, `player-panel/subtitle-section.tsx`, `dual-subtitle-section.tsx`).
struct SubtitleSelectionSettingsView: View {
    @Bindable private var preferences = SubtitleSelectionPreferences.shared

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    /// Desktop shows the normalise toggle only when the ASS override is "no" or "scale" (`subtitle-section.tsx:388`).
    private var normalizeAvailable: Bool {
        let assOverride = PlaybackPreferences.shared.options.subtitleASS
        return assOverride == "no" || assOverride == "scale"
    }

    /// Desktop shows the second line size only when a second subtitle language is set (`dual-subtitle-section.tsx:72`).
    private var secondaryOn: Bool {
        !SubtitleLanguages.preferredCodes(PlaybackPreferences.shared.options.secondarySubtitleLanguage).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                chooseSection
                skipSection
                if normalizeAvailable { normalizeSection }
                if secondaryOn { secondarySection }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(HarborTheme.background)
        .foregroundStyle(HarborTheme.ink)
        .buttonStyle(.plain)
        .navigationTitle(text("Choosing a track"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("subtitle-selection-settings")
    }

    private var chooseSection: some View {
        HarborSettingsSection(text("Choosing a track"), note: text("Which subtitle Harbor lands on when more than one is available.")) {
            HarborSettingsToggle(text("Prefer embedded subtitles"),
                                 note: text("Keep the subtitle track included in the video file instead of switching to a downloaded one."),
                                 isOn: $preferences.preferEmbeddedSubs)
                .accessibilityIdentifier("settings-prefer-embedded-subs")
            HarborSettingsToggle(text("Upgrade subtitles when better ones load"),
                                 note: text("Switch to a better language match if it arrives after playback starts. Leave off to keep the current track."),
                                 isOn: $preferences.subtitleAutoUpgrade)
                .accessibilityIdentifier("settings-subtitle-auto-upgrade")
            HarborSettingsToggle(text("Choose subtitles before playback"),
                                 note: text("Choose the exact track and language after picking a source, before the video starts."),
                                 isOn: $preferences.subtitlePreselect)
                .accessibilityIdentifier("settings-subtitle-preselect")
        }
    }

    private var skipSection: some View {
        HarborSettingsSection(text("Skip these tracks"), note: text("Applies to both audio and subtitle tracks. You can still pick a skipped track by hand in the player.")) {
            BlockWordsField(words: $preferences.trackBlockWords)
        }
    }

    private var normalizeSection: some View {
        HarborSettingsSection(text("Styled (ASS) subtitles")) {
            HarborSettingsToggle(text("Normalize embedded subtitle size"),
                                 note: text("Auto-adjusts styled (ASS) subtitles so dialogue stays the same size across files, while keeping their colors, fonts, and sign placement."),
                                 isOn: $preferences.subAssNormalizeSize)
                .accessibilityIdentifier("settings-ass-normalize-size")
        }
    }

    private var secondarySection: some View {
        HarborSettingsSection(text("Dual subtitles")) {
            SecondLineSizeControl(scale: $preferences.subSecondaryScale)
        }
    }
}

/// Desktop's "Never auto-select tracks containing" field: comma-separated words, saved as the person types.
private struct BlockWordsField: View {
    @Binding var words: [String]
    @State private var draft: String

    init(words: Binding<[String]>) {
        _words = words
        _draft = State(initialValue: words.wrappedValue.joined(separator: ", "))
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { draft },
            set: { value in
                draft = value
                words = SubtitleSelectionPolicy.blockWords(fromText: value)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(DesktopInterfaceText.value("Never auto-select tracks containing"))
                .font(HarborTheme.font(14, weight: .semibold))
            TextField(DesktopInterfaceText.value("commentary, descriptive"), text: draftBinding)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(DesktopInterfaceText.value("Never auto-select tracks containing"))
                .accessibilityIdentifier("settings-track-block-words")
            Text(DesktopInterfaceText.value("Tracks whose name contains one of these words are skipped."))
                .font(HarborTheme.font(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Desktop's "Second line size" slider, 40% to 140% in 5% steps.
private struct SecondLineSizeControl: View {
    @Binding var scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(DesktopInterfaceText.value("Second line size"))
                    .font(HarborTheme.font(14, weight: .semibold))
                Spacer()
                Text("\(Int((scale * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $scale, in: 0.4...1.4, step: 0.05)
                .accessibilityLabel(DesktopInterfaceText.value("Second line size"))
                .accessibilityIdentifier("settings-second-line-size")
            Text(DesktopInterfaceText.value("Relative to your main subtitle size."))
                .font(HarborTheme.font(12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
