import SwiftUI
import UIKit

@MainActor struct SpotifyCover: View {
    let service: SpotifyMusicService
    let uri: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { BoundedArtworkImage(image: image, fit: .fill) }
            else { Image("nav-music").resizable().scaledToFit().padding(10).background(HarborTheme.surface) }
        }.clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
            .task(id: uri) { image = nil; image = try? await service.artwork(uri) }
    }
}

@MainActor struct SpotifyCatalogView: View {
    @Bindable var service: SpotifyMusicService
    var uri: String?
    var title = "Spotify"
    @State private var items: [SpotifyContentItem] = []
    @State private var loading = false
    @State private var failed = false
    @State private var retry = 0
    var body: some View {
        List {
            if loading { ProgressView(DesktopInterfaceText.value("Loading music")) }
            if failed {
                Text(DesktopInterfaceText.value("music.error.load")).foregroundStyle(.secondary)
                Button(DesktopInterfaceText.value("Retry")) { retry += 1 }
            }
            ForEach(items) { item in
                HStack(spacing: 12) {
                    if item.container {
                        NavigationLink { SpotifyCatalogView(service: service, uri: item.uri, title: item.title) } label: { row(item) }
                    } else { Button { service.play(item.uri) } label: { row(item) }.buttonStyle(.plain).disabled(!item.playable) }
                    if item.container, item.playable {
                        Button { service.play(item.uri) } label: { Image(systemName: "play.fill").frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel(DesktopInterfaceText.value("music.play"))
                    }
                }
            }
            if !loading, !failed, items.isEmpty { Text(DesktopInterfaceText.value("Nothing to show yet.")).foregroundStyle(.secondary) }
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .task(id: (uri ?? "root") + "|" + String(service.connected) + "|" + String(retry)) {
                items = []; loading = true; failed = false; defer { loading = false }
                do { let result = try await service.content(uri); try Task.checkCancellation(); items = result }
                catch is CancellationError { }
                catch { failed = true }
            }.accessibilityIdentifier("music-spotify-catalog")
    }
    private func row(_ item: SpotifyContentItem) -> some View {
        HStack(spacing: 12) {
            SpotifyCover(service: service, uri: item.uri).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.body).lineLimit(2)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if item.offline { Image(systemName: "arrow.down.circle").font(.caption).foregroundStyle(.secondary) }
        }.frame(minHeight: 56).contentShape(.rect)
    }
}

@MainActor struct SpotifyMiniPlayer: View {
    @Bindable var service: SpotifyMusicService
    @State private var expanded = false
    var body: some View {
        if let snapshot = service.snapshot {
            HStack(spacing: 12) {
                Button { expanded = true } label: {
                    HStack(spacing: 10) {
                        SpotifyCover(service: service, uri: snapshot.uri).frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("Spotify · " + snapshot.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain)
                Button { service.togglePause() } label: { MusicGlyph(snapshot.paused ? "play" : "pause").frame(width: 44, height: 44) }.disabled(!service.connected)
                    .accessibilityLabel(DesktopInterfaceText.value(snapshot.paused ? "music.play" : "music.pause"))
                Button { service.next() } label: { MusicGlyph("next").frame(width: 44, height: 44) }.disabled(!service.connected || !snapshot.canSkipNext)
                    .accessibilityLabel(DesktopInterfaceText.value("music.next"))
            }.padding(.horizontal, 14).padding(.vertical, 7).background(HarborTheme.surface)
                .sheet(isPresented: $expanded) { NavigationStack { SpotifyMusicView(service: service).toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button(DesktopInterfaceText.value("Close")) { expanded = false } }
                } } }.accessibilityIdentifier("music-spotify-mini-player")
        }
    }
}
