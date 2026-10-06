import SwiftUI

struct PlayerTrackPanel: View {
    let page: PlayerSettingsPage
    let state: PlayerState
    @Bindable private var preferences = PlaybackPreferences.shared
    private var tracks: [PlayerState.Track] { state.tracks.filter { $0.type == "audio" } }
    var body: some View {
        Group {
            if page == .subtitles { SubtitleTracksView(state: state, panel: true) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { Text("Pistas de audio · \(tracks.count)").font(.headline); Spacer(); NavigationLink { PlayerSettingsView(page: .audio) } label: { Image("nav-settings").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44) }.accessibilityLabel("Preferencias de audio") }
                        ForEach(tracks) { track in
                            Button { state.controller?.set("aid", String(track.id)) } label: {
                                HStack(spacing: 12) {
                                    Circle().fill(track.selected ? HarborTheme.accent : .white.opacity(0.1)).frame(width: 17, height: 17).overlay { if track.selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.black) } }
                                    VStack(alignment: .leading, spacing: 5) { Text(track.label).font(.subheadline).lineLimit(2); Text([SubtitleLanguages.label(track), track.codec.uppercased()].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
                                    Spacer()
                                }.padding(14).frame(minHeight: 54).background(track.selected ? HarborTheme.surface : HarborTheme.surface.opacity(0.35), in: .rect(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(!state.loaded)
                        }
                        if tracks.isEmpty { Text("No hay pistas de audio disponibles.").font(.subheadline).foregroundStyle(.secondary) }
                        Divider()
                        HStack { Button { state.controller?.set("mute", state.muted ? "no" : "yes") } label: { Image(state.muted ? "player-volume--mute" : "player-volume").resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 44, height: 44) }.accessibilityLabel(state.muted ? "Activar sonido" : "Silenciar"); Slider(value: $preferences.options.volume, in: 0...100).tint(.white).accessibilityLabel("Volumen"); Text("\(Int(state.volume))%").font(.caption).monospacedDigit() }
                    }.padding(18)
                }.background(HarborTheme.background)
            }
        }.navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
    }
}
