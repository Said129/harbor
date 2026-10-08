import SwiftUI

struct EpisodeList: View {
    let media: Media
    let library: LibraryModel
    let play: (Episode?) -> Void
    @State private var season = 1
    @State private var revealed = Set<String>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                let hidden = spoilerHidden(episode)
                let episodeLabel = DesktopInterfaceText.value("Episode {n}").replacingOccurrences(of: "{n}", with: String(episode.episode ?? 0))
                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .top, spacing: 12) {
                        Button { play(episode) } label: {
                            Artwork(url: episode.thumbnail, fallback: media.background, maxPixels: 400)
                                .blur(radius: hidden && InterfacePreferences.shared.blurEpisodes ? 14 : 0)
                                .scaleEffect(hidden && InterfacePreferences.shared.blurEpisodes ? 1.04 : 1)
                                .frame(width: 125, height: 74).overlay { Image("ui-play-filled").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white).shadow(radius: 5) }.clipShape(.rect(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(!episode.available).accessibilityLabel("Reproducir episodio \(episode.episode ?? 0)")
                        VStack(alignment: .leading, spacing: 6) {
                            Text(episode.name ?? episode.title ?? episodeLabel).font(.subheadline.weight(.semibold)).lineLimit(2)
                                .blur(radius: hidden && InterfacePreferences.shared.spoilerHideTitles ? 5 : 0)
                                .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideTitles ? episodeLabel : episode.name ?? episode.title ?? episodeLabel)
                            Text("T\(episode.season ?? 0) · E\(episode.episode ?? 0)").font(.caption).foregroundStyle(.secondary)
                            if let date = episode.releaseDate { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { Task { await library.toggleEpisode(media, episode: episode) } } label: {
                            Image(library.watchedEpisodes(media).contains(episode.watchedKey) ? "ui-mark-unwatched" : "ui-mark-watched").resizable().scaledToFit().frame(width: 23, height: 23).frame(minWidth: 32, minHeight: 44)
                        }.buttonStyle(.plain).disabled(library.busy || !episode.available).accessibilityLabel(library.watchedEpisodes(media).contains(episode.watchedKey) ? "Marcar episodio como no visto" : "Marcar episodio como visto")
                    }
                    if InterfacePreferences.shared.showEpisodeDescription, let overview = episode.overview, !overview.isEmpty {
                        Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            .blur(radius: hidden && InterfacePreferences.shared.spoilerHideDescriptions ? 5 : 0)
                            .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideDescriptions ? DesktopInterfaceText.value("Spoilers") : overview)
                    }
                    if hidden && (InterfacePreferences.shared.blurEpisodes || InterfacePreferences.shared.spoilerHideTitles || InterfacePreferences.shared.spoilerHideDescriptions) {
                        Button(DesktopInterfaceText.value("Reveal")) { revealed.insert(episode.id) }.font(.caption).frame(minHeight: 44)
                    }
                    if !episode.available { Text("Próximamente").font(.caption).foregroundStyle(HarborTheme.accent) }
                    Divider()
                }
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
            .task(id: media.identity) { if !seasons.contains(season) { season = seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1 } }
    }
    private func spoilerHidden(_ episode: Episode) -> Bool { InterfacePreferences.shared.hideSpoilers && !library.watchedEpisodes(media).contains(episode.watchedKey) && !revealed.contains(episode.id) }
}
