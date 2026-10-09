import SwiftUI

struct PlayerEpisodesView: View {
    let media: Media
    let current: ResumeTarget
    let library: LibraryModel?
    let canRestart: Bool
    let restart: () -> Void
    let close: () -> Void
    let play: (Episode) -> Void
    @State private var season = 1
    @State private var seasonOpen = false
    @State private var expanded: String?
    @State private var revealed = Set<String>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var episodes: [Episode] { EpisodeSequence.ordered(media.videos ?? []) }
    private var seasons: [Int] { Array(Set(episodes.compactMap(\.season))).sorted() }
    private var visible: [Episode] { episodes.filter { ($0.season ?? season) == season } }
    private var currentEpisode: Episode? { episodes.first(where: isCurrent) }
    private var nextSeason: Int? { seasons.first { $0 > season } }
    private var subtle: Color { ThemePreferences.shared.color("ink-subtle") }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                playbackContext
                episodeScroll(width: geometry.size.width)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(HarborTheme.ink)
                .background(HarborTheme.background)
        }
    }

    private var playbackContext: some View {
        HStack(spacing: 12) {
            if let episode = currentEpisode {
                Text(DesktopInterfaceText.value("Now playing: {label}").replacingOccurrences(of: "{label}", with: currentLabel(episode)))
                    .font(HarborTheme.font(12.5)).foregroundStyle(subtle).lineLimit(1)
            }
            Spacer(minLength: 0)
            if seasons.count > 1 { seasonPicker }
        }.padding(.horizontal, 24).padding(.bottom, 12)
    }

    private func episodeScroll(width: CGFloat) -> some View {
        let thumbnailWidth: CGFloat = min(156.45, max(80, (width - 56) * 0.36))
        return ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(visible) { episode in episodeCard(episode, thumbnailWidth: thumbnailWidth) }
                    if visible.isEmpty {
                        Text(DesktopInterfaceText.value("No episodes found for this season."))
                            .font(HarborTheme.font(13.5)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                            .multilineTextAlignment(.center).padding(.vertical, 40).padding(.horizontal, 8)
                    }
                    nextSeasonButton
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
            }.accessibilityIdentifier("player-episodes-scroll")
                .onChange(of: season) { _, _ in if let first = visible.first { scroll.scrollTo(first.id, anchor: .top) } }
                .task {
                    season = current.season ?? seasons.first(where: { $0 > 0 }) ?? seasons.first ?? 1
                    if let episode = currentEpisode { scroll.scrollTo(episode.id, anchor: .top) }
                }
        }
    }

    private func episodeCard(_ episode: Episode, thumbnailWidth: CGFloat) -> some View {
        let playing = isCurrent(episode)
        let watched = library?.watchedEpisodes(media).contains(episode.watchedKey) == true
        let hidden = InterfacePreferences.shared.hideSpoilers && !playing && !watched && !revealed.contains(episode.id)
        return PlayerEpisodeCard(episode: episode, playing: playing, watched: watched, hidden: hidden,
            expanded: expanded == episode.id, canRestart: canRestart, thumbnailWidth: thumbnailWidth,
            activate: { if playing { restart(); close() } else { play(episode) } },
            toggle: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { expanded = expanded == episode.id ? nil : episode.id } },
            reveal: { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { _ = revealed.insert(episode.id) } })
            .id(episode.id)
    }

    @ViewBuilder private var nextSeasonButton: some View {
        if let nextSeason {
            Button { changeSeason(nextSeason) } label: {
                HStack(spacing: 6) {
                    Text(seasonLabel(nextSeason))
                    episodeGlyph("episode-next-season", size: 16)
                }.font(HarborTheme.font(13.5, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(ThemePreferences.shared.color("elevated"), in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
            }.buttonStyle(.plain).accessibilityIdentifier("player-next-season")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DesktopInterfaceText.value("Up Next").uppercased()).font(HarborTheme.font(10.5, weight: .semibold))
                    .tracking(3.36).foregroundStyle(subtle)
                Text(media.name).font(HarborTheme.displayFont(22)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                episodeGlyph("episode-close", size: 18).frame(width: 44, height: 44)
                    .foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                    .background(.white.opacity(0.1), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Close"))
                .accessibilityIdentifier("player-episodes-close")
        }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 16)
    }

    private var seasonPicker: some View {
        Button { seasonOpen.toggle() } label: {
            HStack(spacing: 6) {
                Text(seasonLabel(season)).font(HarborTheme.font(13, weight: .semibold))
                episodeGlyph("episode-expand", size: 15).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                    .rotationEffect(.degrees(seasonOpen ? 180 : 0))
            }.padding(.leading, 14).padding(.trailing, 10).frame(height: 36)
                .background(.white.opacity(0.1), in: Capsule()).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityValue(seasonLabel(season)).accessibilityIdentifier("player-episode-season")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: seasonOpen)
            .popover(isPresented: $seasonOpen) {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(seasons, id: \.self) { number in
                            Button { changeSeason(number); seasonOpen = false } label: {
                                Text(seasonLabel(number)).font(HarborTheme.font(13.5, weight: number == season ? .semibold : .regular))
                                    .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .foregroundStyle(number == season ? HarborTheme.background : ThemePreferences.shared.color("ink-muted"))
                                    .background(number == season ? HarborTheme.accent : .clear, in: .rect(cornerRadius: 6))
                            }.buttonStyle(.plain).accessibilityAddTraits(number == season ? [.isSelected] : [])
                        }
                    }.padding(6)
                }.frame(width: 180, height: min(360, CGFloat(seasons.count) * 46 + 12))
                    .background(ThemePreferences.shared.color("elevated"))
                    .presentationCompactAdaptation(.popover)
            }
    }

    private func changeSeason(_ number: Int) { expanded = nil; season = number }
    private func seasonLabel(_ number: Int) -> String {
        number == 0 ? DesktopInterfaceText.value("Specials") : DesktopInterfaceText.value("Season {n}").replacingOccurrences(of: "{n}", with: String(number))
    }
    private func currentLabel(_ episode: Episode) -> String {
        let label = playerEpisodeLabel(episode)
        return (episode.name ?? episode.title).flatMap { $0.isEmpty ? nil : $0 }.map { label + " · " + $0 } ?? label
    }
    private func isCurrent(_ episode: Episode) -> Bool {
        episode.id == current.videoId || (episode.season != nil && episode.episode != nil && episode.season == current.season && episode.episode == current.episode)
    }
}

private struct PlayerEpisodeCard: View {
    let episode: Episode
    let playing: Bool
    let watched: Bool
    let hidden: Bool
    let expanded: Bool
    let canRestart: Bool
    let thumbnailWidth: CGFloat
    let activate: () -> Void
    let toggle: () -> Void
    let reveal: () -> Void
    @State private var hasArtwork = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var preferences: InterfacePreferences { .shared }
    private var fallbackTitle: String { DesktopInterfaceText.value("Episode {n}").replacingOccurrences(of: "{n}", with: String(episode.episode ?? 0)) }
    private var title: String { (episode.name ?? episode.title).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle }
    private var hidesTitle: Bool { hidden && preferences.spoilerHideTitles }
    private var hidesDescription: Bool { hidden && preferences.spoilerHideDescriptions }
    private var canReveal: Bool { hidden && (preferences.blurEpisodes || preferences.spoilerHideTitles || preferences.spoilerHideDescriptions) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Button(action: activate) {
                    HStack(alignment: .top, spacing: 16) {
                        thumbnail
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title).font(HarborTheme.font(14.5, weight: .semibold)).lineLimit(2)
                                .blur(radius: hidesTitle ? 5 : 0).accessibilityLabel(hidesTitle ? fallbackTitle : title)
                            if playing {
                                Text(DesktopInterfaceText.value("Now Playing").uppercased())
                                    .font(HarborTheme.font(10, weight: .bold)).tracking(1.2).foregroundStyle(HarborTheme.accent)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(HarborTheme.accent.opacity(0.15), in: Capsule())
                                    .overlay { Capsule().stroke(HarborTheme.accent.opacity(0.3), lineWidth: 1) }
                            }
                            HStack(spacing: 8) {
                                episodeGlyph(playing ? "episode-restart" : "ui-play-filled", size: playing ? 15 : 16)
                                Text(DesktopInterfaceText.value(playing ? "Restart" : "Play"))
                            }.font(HarborTheme.font(14, weight: .semibold)).padding(.horizontal, 12)
                                .frame(minHeight: 44).foregroundStyle(HarborTheme.background)
                                .background(HarborTheme.accent.opacity(0.82), in: Capsule())
                        }.frame(maxWidth: .infinity, minHeight: thumbnailWidth * 9 / 16, alignment: .topLeading)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(playing ? !canRestart : !episode.available)
                    .accessibilityIdentifier("player-episode-\(episode.id)")
                    .accessibilityLabel(DesktopInterfaceText.value(playing ? "Restart" : "Play") + ": " + (hidesTitle ? fallbackTitle : title))
                detailsButton
            }.padding(12)
            if canReveal {
                Button(DesktopInterfaceText.value("Reveal"), action: reveal).font(HarborTheme.font(13, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("player-episode-reveal-\(episode.id)")
            }
            if expanded {
                Button(action: activate) { details.contentShape(Rectangle()) }
                    .buttonStyle(.plain).disabled(playing ? !canRestart : !episode.available)
                    .accessibilityLabel(DesktopInterfaceText.value(playing ? "Restart" : "Play") + ": " + (hidesTitle ? fallbackTitle : title))
                    .accessibilityIdentifier("player-episode-description-\(episode.id)")
                    .padding(.horizontal, 12).padding(.bottom, 12).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }.background(ThemePreferences.shared.color("elevated").opacity(0.6), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(playing ? HarborTheme.accent : ThemePreferences.shared.color("edge-soft"), lineWidth: playing ? 2 : 1) }
            .clipShape(.rect(cornerRadius: 16))
    }

    private var thumbnail: some View {
        ZStack {
            LinearGradient(colors: [ThemePreferences.shared.color("elevated").opacity(0.5), HarborTheme.background.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if !hasArtwork { episodeGlyph("episode-await", size: 18).foregroundStyle(ThemePreferences.shared.color("ink-subtle").opacity(0.45)) }
            Artwork(url: episode.thumbnail, maxPixels: 480, showsPlaceholder: false, onImageAvailability: { hasArtwork = $0 })
                .blur(radius: hidden && preferences.blurEpisodes ? 14 : 0)
                .scaleEffect(hidden && preferences.blurEpisodes ? 1.04 : 1)
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }.frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16).clipped().clipShape(.rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ThemePreferences.shared.color("edge-soft").opacity(0.6), lineWidth: 1) }
            .overlay(alignment: .bottomLeading) {
                Text(playerEpisodeLabel(episode)).font(HarborTheme.font(10.5, weight: .bold)).tracking(1.89)
                    .foregroundStyle(.white.opacity(0.9)).shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .padding(.leading, 8).padding(.bottom, 6)
            }
            .overlay(alignment: .topTrailing) {
                if watched && !playing {
                    episodeGlyph("theme-selected", size: 12).foregroundStyle(Color(red: 0.2, green: 0.83, blue: 0.6))
                        .frame(width: 24, height: 24).background(.black.opacity(0.55), in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.15), lineWidth: 1) }
                        .padding(6).accessibilityLabel(DesktopInterfaceText.value("Watched"))
                }
            }.accessibilityHidden(true)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hidden)
    }

    private var detailsButton: some View {
        Button(action: toggle) {
            episodeGlyph("episode-expand", size: 18).rotationEffect(.degrees(expanded ? 180 : 0))
                .foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                .frame(width: 44, height: 44).background(ThemePreferences.shared.color("elevated"), in: Circle())
                .overlay { Circle().stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
        }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value(expanded ? "Hide details" : "Show details"))
            .accessibilityValue(expanded ? DesktopInterfaceText.value("Hide details") : DesktopInterfaceText.value("Show details"))
            .accessibilityIdentifier("player-episode-details-\(episode.id)")
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expanded)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let date = episode.releaseDate { Text(date.formatted(date: .abbreviated, time: .omitted)) }
                if let runtime = episode.runtime, runtime.isFinite, runtime > 0 {
                    Text(DesktopInterfaceText.value("{n} min").replacingOccurrences(of: "{n}", with: runtime.formatted(.number.precision(.fractionLength(0...1)))))
                }
            }.font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
            if preferences.showEpisodeDescription, let overview = episode.overview, !overview.isEmpty {
                Text(overview).font(HarborTheme.font(13)).foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                    .fixedSize(horizontal: false, vertical: true).blur(radius: hidesDescription ? 5 : 0)
                    .accessibilityLabel(hidesDescription ? DesktopInterfaceText.value("Spoilers") : overview)
            } else if preferences.showEpisodeDescription {
                Text(DesktopInterfaceText.value("No description available.")).font(HarborTheme.font(12.5)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(HarborTheme.background.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

private func playerEpisodeLabel(_ episode: Episode) -> String {
    "S\(episode.season ?? 0) · E\(String(format: "%02d", episode.episode ?? 0))"
}

private func episodeGlyph(_ name: String, size: CGFloat) -> some View {
    Image(name).resizable().scaledToFit().frame(width: size, height: size).accessibilityHidden(true)
}
