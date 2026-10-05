import SwiftUI

@MainActor enum HarborTheme {
    static var background: Color { ThemePreferences.shared.color("canvas") }
    static var accent: Color { ThemePreferences.shared.color("accent") }
    static var surface: Color { ThemePreferences.shared.color("surface") }
    static var ink: Color { ThemePreferences.shared.color("ink") }
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: media.poster, fallback: media.fallbackPoster, fallbacks: [media.background].compactMap { $0 }, maxPixels: 480)
                .frame(width: width, height: width.map { $0 * 1.5 }).aspectRatio(2.0 / 3.0, contentMode: .fit).clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
                .overlay(alignment: .bottomTrailing) {
                    if (media.ratingSource == "TMDB" ? InterfacePreferences.shared.showTmdbBadge : InterfacePreferences.shared.showImdbBadge), let rating = media.imdbRating { HStack(spacing: 3) { Text(media.ratingSource ?? "IMDb").font(.system(size: 7, weight: .black)).foregroundStyle(.black).padding(2).background(media.ratingSource == "TMDB" ? Color.mint : .yellow, in: .rect(cornerRadius: 2)); Text(rating).font(.system(size: 9, weight: .semibold)) }.padding(4).background(.black.opacity(0.8), in: .capsule).padding(5) }
                }
            Text(media.name).font(.caption.weight(.medium)).lineLimit(2).frame(width: width, alignment: .leading)
        }.foregroundStyle(.primary)
    }
}

struct CatalogRails: View {
    let rows: [CatalogRow]
    var app: AppModel? = nil
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(title(row)).font(.headline).accessibilityIdentifier("catalog-title")
                        Spacer()
                        if let app { NavigationLink { CatalogBrowserView(app: app, initial: row) } label: { HStack(spacing: 4) { Text("Ver todo"); Image(systemName: "chevron.right") }.font(.caption).foregroundStyle(.secondary) }.accessibilityIdentifier("catalog-browser-link") }
                    }.padding(.horizontal)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(row.metas, id: \.identity) { media in
                                NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain)
                                    .accessibilityLabel(media.name)
                                    .accessibilityIdentifier(media.type == "movie" ? "catalog-movie" : "catalog-media")
                            }
                        }.padding(.horizontal)
                    }.scrollIndicators(.hidden)
                }
            }
        }
    }
    private func title(_ row: CatalogRow) -> String {
        guard rows.filter({ $0.plan.title == row.plan.title }).count > 1 else { return row.plan.title }
        let type: String
        switch row.plan.kind {
        case "movie": type = "Películas"
        case "series": type = "Series"
        case "anime": type = "Anime"
        case "tv", "channel": type = "TV"
        default: type = row.plan.kind
        }
        return "\(row.plan.title) · \(type)"
    }
}
