import SwiftUI

struct EpisodeList: View {
    let media: Media
    let library: LibraryModel
    let play: (Episode?) -> Void
    @State private var season = 1
    @State private var revealed = Set<String>()
    private var videos: [Episode] { WatchedCodec.ordered(media.videos ?? []) }
    private var seasons: [Int] { Array(Set(videos.compactMap(\.season))).sorted() }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Episodios").font(.title2.bold())
                Spacer()
                Picker("Temporada", selection: $season) {
                    ForEach(seasons, id: \.self) { Text($0 == 0 ? "Especiales" : "Temporada \($0)").tag($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("episode-season")
            }
            ForEach(videos.filter { ($0.season ?? season) == season }) { episode in
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 12) {
                        Button { play(episode) } label: {
                            Artwork(url: episode.thumbnail, fallback: media.background, maxPixels: 400)
                                .blur(radius: spoilerHidden(episode) && InterfacePreferences.shared.blurEpisodes ? 12 : 0)
                                .frame(width: 125, height: 74).overlay { Image(systemName: "play.circle.fill").font(.title).shadow(radius: 5) }.clipShape(.rect(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(!episode.available).accessibilityLabel("Reproducir episodio \(episode.episode ?? 0)")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(episode.name ?? episode.title ?? "Episodio \(episode.episode ?? 0)").font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text("T\(episode.season ?? 0) · E\(episode.episode ?? 0)").font(.caption).foregroundStyle(.secondary)
                            if let date = episode.releaseDate { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { Task { await library.toggleEpisode(media, episode: episode) } } label: {
                            Image(library.watchedEpisodes(media).contains(episode.watchedKey) ? "ui-mark-unwatched" : "ui-mark-watched").resizable().scaledToFit().frame(width: 23, height: 23).frame(minWidth: 32, minHeight: 44)
                        }.buttonStyle(.plain).disabled(library.busy || !episode.available).accessibilityLabel(library.watchedEpisodes(media).contains(episode.watchedKey) ? "Marcar episodio como no visto" : "Marcar episodio como visto")
                    }
                    if InterfacePreferences.shared.showEpisodeDescription, let overview = episode.overview, !overview.isEmpty {
                        if spoilerHidden(episode) { Button("Mostrar descripción e imagen") { revealed.insert(episode.id) }.font(.caption) }
                        else { Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    }
                    if !episode.available { Text("Próximamente").font(.caption).foregroundStyle(HarborTheme.accent) }
                    Divider()
                }
            }
        }.task(id: media.identity) { if !seasons.contains(season) { season = seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1 } }
    }
    private func spoilerHidden(_ episode: Episode) -> Bool { InterfacePreferences.shared.hideSpoilers && !library.watchedEpisodes(media).contains(episode.watchedKey) && !revealed.contains(episode.id) }
}
