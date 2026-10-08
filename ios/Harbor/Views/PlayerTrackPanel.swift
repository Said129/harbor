import SwiftUI

struct PlayerTrackPanel: View {
    let page: PlayerSettingsPage
    let state: PlayerState
    @Environment(\.dismiss) private var dismiss
    @Bindable private var preferences = PlaybackPreferences.shared
    private var tracks: [PlayerState.Track] { state.tracks.filter { $0.type == "audio" } }
    var body: some View {
        Group {
            if page == .subtitles { SubtitleTracksView(state: state) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            Text(text("Audio")).font(HarborTheme.font(14, weight: .semibold))
                            Text(String(tracks.count)).font(HarborTheme.font(12)).monospacedDigit().foregroundStyle(.secondary)
                            Spacer()
                            NavigationLink { PlayerSettingsView(page: .audio) } label: {
                                Image("nav-settings").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44)
                            }.accessibilityLabel(text("Audio"))
                        }
                        ForEach(tracks) { track in
                            Button { state.controller?.set("aid", String(track.id)); dismiss() } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Circle().fill(track.selected ? HarborTheme.accent : HarborTheme.ink.opacity(0.1)).frame(width: 16, height: 16)
                                        .overlay { if track.selected { Image("subtitle-check").resizable().scaledToFit().frame(width: 9, height: 9).foregroundStyle(HarborTheme.background) } }
                                        .padding(.top, 2).accessibilityHidden(true)
                                    if !track.language.isEmpty { HarborLanguageFlag(code: SubtitleLanguages.key(track)).padding(.top, 2) }
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(title(track)).font(HarborTheme.font(13, weight: .medium)).lineLimit(2)
                                        Text(details(track)).font(HarborTheme.font(10.5)).tracking(0.7).foregroundStyle(.secondary).lineLimit(3)
                                    }
                                    Spacer()
                                }.padding(12).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                    .background(track.selected ? HarborTheme.surface : .clear, in: .rect(cornerRadius: 8))
                                    .overlay { if track.selected { RoundedRectangle(cornerRadius: 8).stroke(HarborTheme.ink.opacity(0.1), lineWidth: 1) } }
                            }.buttonStyle(.plain).disabled(!state.loaded).accessibilityAddTraits(track.selected ? .isSelected : [])
                                .accessibilityIdentifier("audio-track-\(track.id)")
                        }
                        Divider()
                        HStack {
                            Text(text("Sync Offset")).font(HarborTheme.font(12, weight: .semibold))
                            Spacer()
                            Text((state.audioDelay > 0 ? "+" : "") + String(format: "%.2fs", state.audioDelay)).accessibilityIdentifier("audio-sync-offset")
                                .font(HarborTheme.font(13, weight: .bold)).monospacedDigit()
                                .foregroundStyle(state.audioDelay == 0 ? HarborTheme.ink.opacity(0.55) : HarborTheme.accent)
                            if state.audioDelay != 0 {
                                Button { changeDelay(0) } label: {
                                    Image("audio-reset-sync").resizable().scaledToFit().frame(width: 12, height: 12).frame(width: 44, height: 44)
                                        .background(HarborTheme.surface, in: .rect(cornerRadius: 6))
                                }.buttonStyle(.plain).disabled(!state.loaded).accessibilityLabel(text("Reset sync"))
                            }
                        }
                        HStack(spacing: 0) {
                            Button { changeDelay(state.audioDelay - 0.1) } label: { Text("−0.1s").frame(maxWidth: .infinity, minHeight: 44) }
                            Divider().frame(height: 22)
                            Button { changeDelay(state.audioDelay + 0.1) } label: { Text("+0.1s").frame(maxWidth: .infinity, minHeight: 44) }
                        }.font(HarborTheme.font(12, weight: .semibold)).monospacedDigit().buttonStyle(.plain).disabled(!state.loaded)
                            .background(HarborTheme.surface, in: .rect(cornerRadius: 8))
                        Divider()
                        HStack {
                            Button { state.controller?.set("mute", state.muted ? "no" : "yes") } label: {
                                Image(state.muted ? "player-volume--mute" : "player-volume").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44)
                            }.accessibilityLabel(text(state.muted ? "Unmute" : "Mute"))
                            Slider(value: Binding(get: { state.volume }, set: { preferences.options.volume = $0 }), in: 0...100)
                                .tint(HarborTheme.ink).accessibilityLabel(text("Volume"))
                            Text("\(Int(state.volume))%").font(HarborTheme.font(12)).monospacedDigit()
                        }.disabled(!state.loaded)
                    }.padding(18)
                }.background(HarborTheme.background)
            }
        }.navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
    }

    private func text(_ original: String) -> String { DesktopInterfaceText.value(original) }
    private func title(_ track: PlayerState.Track) -> String {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && title != track.language { return title }
        if !track.language.isEmpty { return SubtitleLanguages.preferenceName(track.language) }
        return track.label.isEmpty ? text("Track") : track.label
    }
    private func details(_ track: PlayerState.Track) -> String {
        [track.language.isEmpty ? "" : SubtitleLanguages.label(track), track.codec, track.channels, track.defaultTrack ? text("Default") : ""]
            .filter { !$0.isEmpty }.joined(separator: " · ").uppercased()
    }
    private func changeDelay(_ value: Double) {
        preferences.options.audioDelay = min(10, max(-10, (value * 100).rounded() / 100))
    }
}
