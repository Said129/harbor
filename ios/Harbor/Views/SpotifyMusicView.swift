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
            Section("Spotify en iPhone y iPad") {
                Text("Harbor controla la aplicación oficial de Spotify. Puedes conectar una cuenta Free; Spotify decide qué canciones, saltos y controles admite, y conserva sus anuncios.").font(.footnote)
                Label(service.connected ? "Conectado" : "Sin conectar", systemImage: service.connected ? "checkmark.circle.fill" : "link")
                if let snapshot = service.snapshot {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.title).font(.headline); Text(snapshot.artist).foregroundStyle(.secondary)
                        if snapshot.advertisement { Text("Publicidad de Spotify").font(.caption) }
                    }
                    Slider(value: $position, in: 0...max(1, snapshot.duration)) { editing in
                        seeking = editing; if !editing { service.seek(position) }
                    }.disabled(!snapshot.canSeek || !service.connected).accessibilityLabel("Posición")
                    HStack {
                        Button { service.previous() } label: { Image(systemName: "backward.end.fill").frame(width: 44, height: 44) }.disabled(!snapshot.canSkipPrevious)
                        Button { service.togglePause() } label: { Image(systemName: snapshot.paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44) }
                        Button { service.next() } label: { Image(systemName: "forward.end.fill").frame(width: 44, height: 44) }.disabled(!snapshot.canSkipNext)
                    }.buttonStyle(.borderless).disabled(!service.connected)
                }
                if service.authorizing { ProgressView("Esperando autorización de Spotify…") }
                Button(service.connected ? "Volver a autorizar" : "Conectar Spotify") { service.authorize() }.disabled(service.clientID.isEmpty || service.authorizing)
                if service.connected { Button("Desconectar", role: .destructive) { service.disconnect() } }
                if let error = service.error { Text(error).foregroundStyle(.orange).font(.footnote) }
            }
            Section("Tu aplicación de Spotify") {
                Text("Spotify exige Premium al propietario del Client ID en modo de desarrollo, aunque el SDK de iOS admita oyentes Free. Añade cada oyente en Users Management. Harbor no proporciona un Client ID compartido.").font(.footnote).foregroundStyle(.secondary)
                Link("Abrir Spotify for Developers", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                TextField("Client ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Guardar Client ID") { do { try service.saveClientID(clientID) } catch { service.error = "Introduce un Client ID válido de 32 caracteres." } }
                LabeledContent("Bundle ID", value: "site.harbor.iphone")
                Text("Añade exactamente esta URI de redirección:").font(.footnote)
                Text(SpotifyMusicService.redirect).font(.caption.monospaced()).textSelection(.enabled)
                Button("Copiar URI") { UIPasteboard.general.string = SpotifyMusicService.redirect }
            }
            Section("Abrir música") {
                TextField("Enlace o URI de Spotify", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Reproducir en Spotify") { if let uri = SpotifyMusicLink.uri(link) { service.play(uri) } }.disabled(!service.connected || SpotifyMusicLink.uri(link) == nil)
                Link("Abrir Spotify sin Client ID", destination: URL(string: "https://open.spotify.com")!)
                Text("Abrir Spotify sin Client ID funciona con cuentas gratuitas, pero no conecta sus controles a Harbor.").font(.footnote).foregroundStyle(.secondary)
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
