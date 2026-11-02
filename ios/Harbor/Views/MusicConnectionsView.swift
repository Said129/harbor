import SwiftUI

@MainActor struct MusicConnectionsView: View {
    let workspace: MusicWorkspace
    let metadata: MusicArtistClient
    var changed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var server = false
    var body: some View {
        NavigationStack {
            List {
                Section(DesktopInterfaceText.value("music.connections.local")) {
                    LabeledContent(DesktopInterfaceText.value("music.home.yourFiles"), value: String(workspace.library.records.count))
                }
                Section(DesktopInterfaceText.value("music.connections.streaming")) {
                    NavigationLink("Spotify · Free / Premium") { SpotifyMusicView(service: workspace.spotify) }
                    NavigationLink("SoundCloud") {
                        Form {
                            Section("SoundCloud") {
                                Text(DesktopInterfaceText.value("music.mobile.soundcloud.consent")).font(.footnote)
                                Link(DesktopInterfaceText.value("Terms"), destination: URL(string: "https://soundcloud.com/terms-of-use")!)
                                Toggle(DesktopInterfaceText.value("Enabled"), isOn: Binding(get: { workspace.soundcloud.enabled }, set: { workspace.soundcloud.setEnabled($0); changed() }))
                            }
                        }.navigationTitle("SoundCloud")
                    }
                }
                Section(DesktopInterfaceText.value("music.connections.server")) {
                    NavigationLink("Plex") { PlexMusicConnectionView(service: workspace.plex, changed: changed) }
                    NavigationLink("Jellyfin") { JellyfinMusicConnectionView(service: workspace.jellyfin, changed: changed) }
                    Button("Subsonic / Navidrome / Ampache") { server = true }
                }
                Section(DesktopInterfaceText.value("Metadata")) { NavigationLink("Last.fm / MusicBrainz") { MusicMetadataSettingsView(client: metadata) } }
                Section(DesktopInterfaceText.value("music.audio.preferredSource")) {
                    Picker(DesktopInterfaceText.value("music.audio.preferredSource"), selection: Binding(get: { UserDefaults.standard.string(forKey: "harbor.music.preferredSource") ?? "auto" }, set: { UserDefaults.standard.set($0, forKey: "harbor.music.preferredSource") })) {
                        Text(DesktopInterfaceText.value("Auto")).tag("auto")
                        Text(DesktopInterfaceText.value("music.home.yourFiles")).tag("local")
                        Text("Subsonic").tag("subsonic")
                        if workspace.plex.configured { Text("Plex").tag("plex") }
                        if workspace.jellyfin.configured { Text("Jellyfin").tag("jellyfin") }
                        if workspace.soundcloud.enabled { Text("SoundCloud").tag("soundcloud") }
                    }
                }
            }.navigationTitle(DesktopInterfaceText.value("music.connections.title")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close")) { dismiss() } } }
                .sheet(isPresented: $server) { MusicServerConnectionView(service: workspace.server, onChange: changed) }
        }.accessibilityIdentifier("music-connections")
    }
}
