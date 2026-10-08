import SwiftUI

struct PlayerEpisodesView: View {
    let media: Media
    let current: ResumeTarget
    let library: LibraryModel?
    let play: (Episode) -> Void
    @State private var season = 1
    @State private var revealed = Set<String>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    let episodeLabel = DesktopInterfaceText.value("Episode {n}").replacingOccurrences(of: "{n}", with: String(episode.episode ?? 0))
                    VStack(alignment: .leading, spacing: 8) {
                        Button { play(episode) } label: {
                            HStack(spacing: 12) {
                                Artwork(url: episode.thumbnail, fallback: media.background, maxPixels: 320)
                                    .blur(radius: hidden && InterfacePreferences.shared.blurEpisodes ? 14 : 0)
                                    .scaleEffect(hidden && InterfacePreferences.shared.blurEpisodes ? 1.04 : 1)
                                    .frame(width: 92, height: 56).clipped().clipShape(.rect(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(episode.name ?? episode.title ?? episodeLabel).lineLimit(2)
                                        .blur(radius: hidden && InterfacePreferences.shared.spoilerHideTitles ? 5 : 0)
                                        .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideTitles ? episodeLabel : episode.name ?? episode.title ?? episodeLabel)
                                    Text(playing ? "Reproduciendo" : !episode.available ? "Próximamente" : "T\(episode.season ?? 0) · E\(episode.episode ?? 0)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(playing ? "music-check" : "player-next-episode").resizable().scaledToFit().frame(width: 20, height: 20)
                            }.frame(minHeight: 56)
                        }.buttonStyle(.plain).disabled(playing || !episode.available)
                            .accessibilityIdentifier("player-episode-\(episode.id)")
                        if hidden && (InterfacePreferences.shared.blurEpisodes || InterfacePreferences.shared.spoilerHideTitles || InterfacePreferences.shared.spoilerHideDescriptions) {
                            Button(DesktopInterfaceText.value("Reveal")) { revealed.insert(episode.id) }.font(.caption).frame(minHeight: 44)
                        }
                        if InterfacePreferences.shared.showEpisodeDescription, let overview = episode.overview, !overview.isEmpty {
                            Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                .blur(radius: hidden && InterfacePreferences.shared.spoilerHideDescriptions ? 5 : 0)
                                .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideDescriptions ? DesktopInterfaceText.value("Spoilers") : overview)
                        }
                        if let date = episode.releaseDate { Text(date, style: .date).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
            .navigationTitle("Episodios").navigationBarTitleDisplayMode(.inline)
            .task { season = current.season ?? seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1 }
    }

    private func isCurrent(_ episode: Episode) -> Bool {
        episode.id == current.videoId || (episode.season != nil && episode.episode != nil && episode.season == current.season && episode.episode == current.episode)
    }
}
