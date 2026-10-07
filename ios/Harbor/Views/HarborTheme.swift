import SwiftUI

@MainActor enum HarborTheme {
    static var background: Color { ThemePreferences.shared.color("canvas") }
    static var accent: Color { ThemePreferences.shared.color("accent") }
    static var surface: Color { ThemePreferences.shared.color("surface") }
    static var ink: Color { ThemePreferences.shared.color("ink") }
    static func displayFont(_ size: CGFloat) -> Font { .custom("Fraunces-9ptBlack", size: size).weight(.medium) }
    static func font(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        switch ThemePreferences.shared.font {
        case "inter": .custom("Inter-Regular", size: size).weight(weight)
        case "system": .system(size: size, weight: weight)
        default: .custom("SwitzerVariable-Regular", size: size).weight(weight)
        }
    }
}

struct Poster: View {
    let media: Media
    var width: CGFloat? = 116
    var artworkFallbacks: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: media.poster, fallback: media.fallbackPoster, fallbacks: [media.background].compactMap { $0 } + artworkFallbacks, maxPixels: 480)
                .frame(width: width, height: width.map { $0 * 1.5 }).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
                .overlay(alignment: .bottomTrailing) {
                    if (media.ratingSource == "TMDB" ? InterfacePreferences.shared.showTmdbBadge : InterfacePreferences.shared.showImdbBadge), let rating = media.imdbRating { HStack(spacing: 3) { Text(media.ratingSource ?? "IMDb").font(.system(size: 7, weight: .black)).foregroundStyle(.black).padding(2).background(media.ratingSource == "TMDB" ? Color.mint : .yellow, in: .rect(cornerRadius: 2)); Text(rating).font(.system(size: 9, weight: .semibold)) }.padding(4).background(.black.opacity(0.8), in: .capsule).padding(5) }
                }
            Text(media.name).font(.caption.weight(.medium)).lineLimit(2).frame(width: width, alignment: .leading)
        }.foregroundStyle(.primary).contentShape(Rectangle())
    }
}

struct CatalogRails: View {
    let rows: [CatalogRow]
    var app: AppModel? = nil
    var titleOverrides: [String: String] = [:]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(row)).font(HarborTheme.font(17, weight: .medium)).accessibilityIdentifier("catalog-title")
                            Text(["movie": "Películas", "series": "Series", "anime": "Anime", "tv": "TV", "channel": "TV"][row.plan.kind] ?? row.plan.kind).font(HarborTheme.font(12)).foregroundStyle(HarborTheme.ink.opacity(0.45))
                        }
                        Spacer()
                        if let app { NavigationLink { CatalogBrowserView(app: app, initial: row) } label: { HStack(spacing: 4) { Text("Ver todo"); Image("desktop-chevron-right").resizable().scaledToFit().frame(width: 14, height: 14) }.font(.caption).foregroundStyle(.secondary).frame(minHeight: 44) }.accessibilityIdentifier("catalog-browser-link") }
                    }.padding(.horizontal)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(row.metas, id: \.identity) { media in
                                if let app {
                                    NavigationLink { DetailView(media: media, app: app) } label: { Poster(media: media) }
                                        .buttonStyle(.plain).accessibilityLabel(media.name)
                                        .accessibilityIdentifier(media.type == "movie" ? "catalog-movie" : "catalog-media")
                                } else {
                                    NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain).accessibilityLabel(media.name)
                                }
                            }
                        }.padding(.horizontal)
                    }.scrollIndicators(.hidden)
                }
            }
        }
    }
    private func title(_ row: CatalogRow) -> String {
        titleOverrides[row.id] ?? row.plan.title
    }
}
