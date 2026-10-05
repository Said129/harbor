import SwiftUI

enum HarborTheme {
    // sRGB equivalents of the upstream cool-grey default canvas/accent OKLCH
    // tokens in src/lib/theme.ts. Native layouts retain Harbor's identity.
    static let background = Color(.sRGB, red: 0.064818, green: 0.069086, blue: 0.075969)
    static let accent = Color(.sRGB, red: 0.955883, green: 0.636209, blue: 0.359162)
}

struct Poster: View {
    let media: Media
    var width: CGFloat = 116
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: media.poster, fallback: media.background, maxPixels: 480)
                .frame(width: width, height: width * 1.5).clipShape(.rect(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if let rating = media.imdbRating { HStack(spacing: 3) { Text("IMDb").font(.system(size: 7, weight: .black)).foregroundStyle(.black).padding(2).background(.yellow, in: .rect(cornerRadius: 2)); Text(rating).font(.system(size: 9, weight: .semibold)) }.padding(4).background(.black.opacity(0.8), in: .capsule).padding(5) }
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
                        Text(row.plan.title).font(.headline).accessibilityIdentifier("catalog-title")
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
}
