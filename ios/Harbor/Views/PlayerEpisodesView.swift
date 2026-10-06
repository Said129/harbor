import SwiftUI

struct PlayerEpisodesView: View {
    let media: Media
    let current: ResumeTarget
    let library: LibraryModel?
    let play: (Episode) -> Void
    @State private var season = 1
    @State private var revealed = Set<String>()
    private var episodes: [Episode] { EpisodeSequence.ordered(media.videos ?? []) }
    private var seasons: [Int] { Array(Set(episodes.compactMap(\.season))).sorted() }

    var body: some View {
        List {
            if !seasons.isEmpty {
                Section {
                    Picker("Temporada", selection: $season) {
                        ForEach(seasons, id: \.self) { Text($0 == 0 ? "Especiales" : "Temporada \($0)").tag($0) }
                    }.accessibilityIdentifier("player-episode-season")
                }
            }
            Section {
                ForEach(episodes.filter { ($0.season ?? season) == season }) { episode in
                    let playing = isCurrent(episode)
                    let hidden = InterfacePreferences.shared.hideSpoilers && library?.watchedEpisodes(media).contains(episode.watchedKey) != true && !revealed.contains(episode.id)
                    VStack(alignment: .leading, spacing: 8) {
                        Button { play(episode) } label: {
                            HStack(spacing: 12) {
                                Artwork(url: episode.thumbnail, fallback: media.background, maxPixels: 320)
                                    .blur(radius: hidden && InterfacePreferences.shared.blurEpisodes ? 12 : 0)
                                    .frame(width: 92, height: 56).clipped().clipShape(.rect(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(hidden ? "Episodio \(episode.episode ?? 0)" : episode.name ?? episode.title ?? "Episodio \(episode.episode ?? 0)").lineLimit(2)
                                    Text(playing ? "Reproduciendo" : !episode.available ? "Próximamente" : "T\(episode.season ?? 0) · E\(episode.episode ?? 0)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(playing ? "music-check" : "player-next-episode").resizable().scaledToFit().frame(width: 20, height: 20)
                            }.frame(minHeight: 56)
                        }.buttonStyle(.plain).disabled(playing || !episode.available)
                            .accessibilityIdentifier("player-episode-\(episode.id)")
                        if hidden {
                            Button("Mostrar descripción e imagen") { revealed.insert(episode.id) }.font(.caption)
                        } else if InterfacePreferences.shared.showEpisodeDescription, let overview = episode.overview, !overview.isEmpty {
                            Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                        if let date = episode.releaseDate { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("Episodios").navigationBarTitleDisplayMode(.inline)
            .task { season = current.season ?? seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1 }
    }

    private func isCurrent(_ episode: Episode) -> Bool {
        episode.id == current.videoId || (episode.season != nil && episode.episode != nil && episode.season == current.season && episode.episode == current.episode)
    }
}
