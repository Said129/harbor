import SwiftUI
import UIKit

/// Plex artwork is represented without credentials in catalog or playlist data.
@MainActor struct MusicArtwork: View {
    let url: String?
    var maxPixels = 720
    @Environment(\.musicPlaybackSession) private var session
    var body: some View {
        if let url, url.hasPrefix("harbor-music-art://") {
            if let plex = session?.plex { PlexMusicArtwork(reference: url, service: plex, maxPixels: maxPixels) }
            else { Artwork(url: nil, maxPixels: maxPixels, failureIcon: "nav-music") }
        } else { Artwork(url: url, maxPixels: maxPixels, failureIcon: "nav-music") }
    }
}
@MainActor private struct PlexMusicArtwork: View {
    let reference: String
    let service: PlexMusicService
    let maxPixels: Int
    @State private var image: UIImage?
    @State private var revision: UUID?
    @State private var failed = false
    var body: some View {
        ZStack {
            if let image, revision == service.credentialVersion, service.configured { BoundedArtworkImage(image: image, fit: .fill) }
            else {
                Rectangle().fill(.white.opacity(0.045))
                if failed { Image("nav-music").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.secondary) }
                else { ProgressView().controlSize(.small) }
            }
        }.clipped().allowsHitTesting(false).task(id: reference + "|" + service.credentialVersion.uuidString + "|" + String(maxPixels)) {
            image = nil; failed = false; revision = nil
            let version = service.credentialVersion
            do {
                let data = try await service.artwork(reference)
                let decoded = try await ArtworkBitmapDecoder.thumbnail(data, maxPixels: maxPixels)
                try Task.checkCancellation(); try service.validate(version)
                image = decoded.image; revision = version
            } catch is CancellationError { }
            catch { failed = true }
        }
    }
}
