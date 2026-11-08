import SwiftUI

/// The player's top-bar title, as Desktop's `title-info` control shows it: the first line, the second line for an
/// episode, and the quality line. By default the episode line leads and the show name follows; `playerTitleSeriesFirst`
/// moves the show name to the top (`UISettingsPolicy.titleLines`).
struct PlayerTitleLines: View {
    let state: PlayerState
    let title: String
    let media: Media?
    let target: ResumeTarget

    var body: some View {
        let lines = Self.lines(title: title, media: media, target: target, seriesFirst: InterfacePreferences.shared.playerTitleSeriesFirst)
        VStack(alignment: .leading, spacing: 2) {
            Text(lines.primary).lineLimit(1)
            if let secondary = lines.secondary, !secondary.isEmpty {
                Text(secondary).font(.caption).opacity(0.7).lineLimit(1)
            }
            PlayerQualityInfoLine(state: state)
        }
    }

    /// Desktop's episode line, `S{season} E{episode} · {name}`. Without season and episode numbers only the name remains.
    nonisolated static func episodeLine(season: Int?, episode: Int?, name: String?) -> String? {
        var code: String?
        if let season, let episode { code = "S\(season) E\(episode)" }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let code { return trimmed.isEmpty ? code : code + " · " + trimmed }
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The first and second line for `target`. An episode of `media` carries its episode line and the show name;
    /// a movie, or an episode that `media` does not list, keeps `title` alone with no second line, as before.
    /// `UISettingsPolicy.titleLines` takes the episode line as its `title` and the show name as its `subtitle`,
    /// so the swap puts the show name first.
    nonisolated static func lines(title: String, media: Media?, target: ResumeTarget, seriesFirst: Bool) -> (primary: String, secondary: String?) {
        guard let episode = media?.videos?.first(where: { $0.belongs(to: target) }),
              let line = episodeLine(season: episode.season, episode: episode.episode, name: episode.name),
              let show = media?.name else { return (title, nil) }
        return UISettingsPolicy.titleLines(title: line, subtitle: show, seriesFirst: seriesFirst)
    }
}
