import SwiftUI

struct PlayerUpNextView: View {
    let episode: Episode
    let remaining: Double
    let automatic: Bool
    let hideSpoiler: Bool
    let play: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(automatic ? "Siguiente en \(Int(remaining.isFinite ? min(300, max(0, remaining.rounded(.up))) : 0)) s" : "Siguiente episodio").font(.caption.weight(.semibold)).monospacedDigit()
            Text(hideSpoiler ? "T\(episode.season ?? 0) · E\(episode.episode ?? 0)" : episode.name ?? episode.title ?? "Episodio \(episode.episode ?? 0)").font(.subheadline.weight(.semibold)).lineLimit(2)
            HStack(spacing: 12) {
                Button(action: play) {
                    Label { Text("Reproducir ahora") } icon: { Image("player-next-episode").resizable().scaledToFit().frame(width: 16, height: 16) }
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("player-up-next-play")
                Spacer(minLength: 0)
                Button(action: cancel) { Image("music-close").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44) }
                    .accessibilityLabel("Cancelar siguiente episodio").accessibilityIdentifier("player-up-next-cancel")
            }.font(.caption)
        }.padding(.horizontal, 14).padding(.top, 12).frame(maxWidth: 300, alignment: .leading)
            .foregroundStyle(.white).background(.black.opacity(0.8), in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15)) }
            .accessibilityIdentifier("player-up-next")
    }
}
