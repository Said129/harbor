import SwiftUI
import UIKit

@MainActor struct SpotifyMusicView: View {
    @Bindable var service: SpotifyMusicService
    @State private var clientID = ""
    @State private var link = ""
    @State private var position = 0.0
    @State private var seeking = false
    var body: some View {
        Form {
            Section("Spotify Web") {
                NavigationLink("Spotify Web Player") { SpotifyWebView(owner: service.scope.owner) }.accessibilityIdentifier("music-spotify-web-link")
                Text(DesktopInterfaceText.value("music.mobile.spotify.web")).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Spotify · iPhone / iPad") {
                Text(DesktopInterfaceText.value("music.mobile.spotify.remote")).font(.footnote)
                Label(DesktopInterfaceText.value(service.connected ? "music.connections.statusConnected" : "music.connections.statusDisconnected"), systemImage: service.connected ? "checkmark.circle.fill" : "link")
                if let snapshot = service.snapshot {
                    SpotifyCover(service: service, uri: snapshot.uri).frame(width: 160, height: 160).frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.title).font(.headline); Text(snapshot.artist).foregroundStyle(.secondary)
                        if snapshot.advertisement { Text(DesktopInterfaceText.value("music.mobile.spotify.advertisement")).font(.caption) }
                    }
                    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                        Slider(value: Binding(get: { seeking ? position : service.position(at: timeline.date) }, set: { position = $0 }), in: 0...max(1, snapshot.duration)) { editing in
                            if editing { position = service.position(at: Date()) }
                            seeking = editing; if !editing { service.seek(position) }
                        }.disabled(!snapshot.canSeek || !service.connected).accessibilityLabel(DesktopInterfaceText.value("music.position"))
                    }
                    HStack {
                        Button { service.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.disabled(!snapshot.canSkipPrevious).accessibilityLabel(DesktopInterfaceText.value("music.previous"))
                        Button { service.togglePause() } label: { Image(systemName: snapshot.paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44) }.accessibilityLabel(DesktopInterfaceText.value(snapshot.paused ? "music.play" : "music.pause"))
                        Button { service.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.disabled(!snapshot.canSkipNext).accessibilityLabel(DesktopInterfaceText.value("music.next"))
                    }.buttonStyle(.borderless).disabled(!service.connected)
                }
                if service.connected {
                    NavigationLink(DesktopInterfaceText.value("music.discover")) { SpotifyCatalogView(service: service) }
                }
                if service.authorizing { ProgressView(DesktopInterfaceText.value("music.source.loading")) }
                Button(DesktopInterfaceText.value("music.spotifySetup.authorize")) { service.authorize() }.disabled(service.clientID.isEmpty || service.authorizing)
                if service.connected { Button(DesktopInterfaceText.value("music.connect.disconnect"), role: .destructive) { service.disconnect() } }
                if let error = service.error { Text(error).foregroundStyle(.orange).font(.footnote) }
                if let error = service.scrobbleError { Text(error).foregroundStyle(.orange).font(.footnote) }
            }
            Section(DesktopInterfaceText.value("music.spotifySetup.createTitle")) {
                Text(DesktopInterfaceText.value("music.spotifySetup.createBody")).font(.footnote).foregroundStyle(.secondary)
                Text(DesktopInterfaceText.value("music.spotifySetup.accountHint")).font(.footnote).foregroundStyle(.secondary)
                Link(DesktopInterfaceText.value("music.spotifySetup.dashboard"), destination: URL(string: "https://developer.spotify.com/dashboard")!)
                TextField("Client ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(DesktopInterfaceText.value("Save")) { do { try service.saveClientID(clientID) } catch { service.error = DesktopInterfaceText.value("music.spotifySetup.rejected") } }
                LabeledContent("Bundle ID", value: "site.harbor.iphone")
                Text(DesktopInterfaceText.value("music.spotifySetup.redirectBody")).font(.footnote)
                Text(SpotifyMusicService.redirect).font(.caption.monospaced()).textSelection(.enabled)
                Button(DesktopInterfaceText.value("music.spotifySetup.copyUri")) { UIPasteboard.general.string = SpotifyMusicService.redirect }
            }
            Section(DesktopInterfaceText.value("music.spotifyLibrary.open")) {
                TextField("Spotify URL / URI", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(DesktopInterfaceText.value("music.play") + " · Spotify") { if let uri = SpotifyMusicLink.uri(link) { service.play(uri) } }.disabled(!service.connected || SpotifyMusicLink.uri(link) == nil)
                Link(DesktopInterfaceText.value("music.spotifyLibrary.open"), destination: URL(string: "https://open.spotify.com")!)
                Text(DesktopInterfaceText.value("music.mobile.spotify.external")).font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("Spotify").navigationBarTitleDisplayMode(.inline)
            .onAppear { clientID = service.clientID; position = service.snapshot?.position ?? 0 }
            .onChange(of: service.snapshot?.position) { _, value in if !seeking { position = value ?? 0 } }
            .accessibilityIdentifier("music-spotify-connection")
    }
}

enum SpotifyMusicLink {
    static func uri(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let kinds = ["track", "album", "playlist", "artist", "show", "episode"]
        let parts: [String]
        if value.hasPrefix("spotify:") { parts = value.split(separator: ":").dropFirst().map(String.init) }
        else if let url = URL(string: value), url.scheme == "https", url.host == "open.spotify.com" {
            parts = url.pathComponents.filter { $0 != "/" && !$0.hasPrefix("intl-") }
        } else { return nil }
        guard parts.count == 2, kinds.contains(parts[0]), parts[1].count == 22, parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return "spotify:" + parts.joined(separator: ":")
    }
}
