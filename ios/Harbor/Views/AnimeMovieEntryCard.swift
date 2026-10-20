import SwiftUI

struct AnimeMovieEntryCard: View {
    let media: Media
    let watched: Bool
    let play: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: play) {
            ZStack {
                Artwork(url: media.background ?? media.poster, fallback: media.fallbackBackground, maxPixels: 1200)
                LinearGradient(colors: [.clear, HarborTheme.background.opacity(0.35), HarborTheme.background.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                Image("ui-play-filled").resizable().scaledToFit().frame(width: 24, height: 24)
                    .foregroundStyle(HarborTheme.background).frame(width: 64, height: 64)
                    .background(HarborTheme.ink, in: Circle()).shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                    .scaleEffect(hovered && !reduceMotion ? 1.05 : 1).animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovered)
                VStack {
                    HStack {
                        Spacer()
                        if watched {
                            HStack(spacing: 6) {
                                Image("music-check").resizable().scaledToFit().frame(width: 13, height: 13)
                                Text(DesktopInterfaceText.value("Watched"))
                            }
                                .font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(.green)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(.green.opacity(0.2), in: Capsule())
                        }
                    }
                    Spacer()
                    HStack {
                        Text(DesktopInterfaceText.value("Play movie")).font(HarborTheme.font(15, weight: .semibold)).shadow(radius: 4)
                        Spacer()
                    }
                }.padding(20)
            }.frame(height: 260).frame(maxWidth: .infinity).clipped().clipShape(.rect(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityLabel(DesktopInterfaceText.value("Play movie"))
            .accessibilityValue(watched ? DesktopInterfaceText.value("Watched") : "").accessibilityIdentifier("anime-movie-play")
            .onHover { hovered = $0 }
    }
}

struct AnimeFranchiseExtraRow: View {
    let extra: AnimeFranchiseExtra
    let watched: Bool
    let loading: Bool
    var canPlay = true
    let play: () -> Void
    let toggleWatched: (() -> Void)?
    @State private var revealed = false
    private var hidden: Bool { InterfacePreferences.shared.hideSpoilers && !watched && !revealed }
    private var episodeLabel: String { DesktopInterfaceText.value("Episode {n}", variables: ["n": String(extra.slot.number)]) }
    private var available: Bool {
        guard let date = extra.slot.aired else { return !extra.entry.upcoming }
        return (ISO8601DateParser.shared.date(String(date.prefix(10)) + "T00:00:00Z").map { $0 <= Date() } ?? !extra.entry.upcoming)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 0) {
                Button(action: play) {
                    HStack(alignment: .top, spacing: 12) {
                        Artwork(url: extra.image, maxPixels: 400).frame(width: 125, height: 74)
                            .blur(radius: hidden && InterfacePreferences.shared.blurEpisodes ? 14 : 0)
                            .overlay { Image("ui-play-filled").resizable().scaledToFit().frame(width: 24, height: 24).foregroundStyle(.white).shadow(radius: 5) }
                            .clipShape(.rect(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(extra.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                .blur(radius: hidden && InterfacePreferences.shared.spoilerHideTitles ? 5 : 0)
                                .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideTitles ? episodeLabel : extra.name)
                            Text("T\(extra.slot.season) · E\(extra.slot.number)").font(.caption).foregroundStyle(.secondary)
                            if let year = extra.slot.aired?.prefix(4) { Text(String(year)).font(.caption2).foregroundStyle(.secondary) }
                            if loading { ProgressView().controlSize(.small) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(loading || !available || !canPlay).accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideTitles ? episodeLabel : extra.name)
                    .accessibilityIdentifier("franchise-extra-" + extra.entry.id)
                if let toggleWatched { Button(action: toggleWatched) {
                    Image(watched ? "ui-mark-unwatched" : "ui-mark-watched").resizable().scaledToFit().frame(width: 23, height: 23).frame(width: 44, height: 44)
                }.buttonStyle(.plain).disabled(loading || !available)
                    .accessibilityLabel(DesktopInterfaceText.value(watched ? "Marcar como no visto" : "Marcar como visto"))
                }
            }
            if InterfacePreferences.shared.showEpisodeDescription, !extra.slot.overview.isEmpty {
                Text(extra.slot.overview).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .blur(radius: hidden && InterfacePreferences.shared.spoilerHideDescriptions ? 5 : 0)
                    .accessibilityLabel(hidden && InterfacePreferences.shared.spoilerHideDescriptions ? DesktopInterfaceText.value("Spoilers") : extra.slot.overview)
            }
            if hidden && (InterfacePreferences.shared.blurEpisodes || InterfacePreferences.shared.spoilerHideTitles || InterfacePreferences.shared.spoilerHideDescriptions) {
                Button(DesktopInterfaceText.value("Reveal")) { revealed = true }.font(.caption).frame(minHeight: 44)
            }
            if !available { Text(DesktopInterfaceText.value("Próximamente")).font(.caption).foregroundStyle(HarborTheme.accent) }
            Divider()
        }
    }
}
