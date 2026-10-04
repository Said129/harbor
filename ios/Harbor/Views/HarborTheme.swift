import SwiftUI

enum HarborTheme {
    // sRGB equivalents of the upstream cool-grey default canvas/accent OKLCH
    // tokens in src/lib/theme.ts. Native layouts retain Harbor's identity.
    static let background = Color(.sRGB, red: 0.064818, green: 0.069086, blue: 0.075969)
    static let accent = Color(.sRGB, red: 0.955883, green: 0.636209, blue: 0.359162)
}

struct Poster: View {
    let media: Media
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: media.poster.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: { Rectangle().fill(.white.opacity(0.06)).overlay(Image(systemName: "film")) }
            .frame(width: 116, height: 172).clipShape(.rect(cornerRadius: 12))
            Text(media.name).font(.caption).lineLimit(2).frame(width: 116, alignment: .leading)
        }.foregroundStyle(.primary)
    }
}

struct CatalogRails: View {
    let rows: [CatalogRow]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 12) {
                    Text(row.plan.title).font(.title3.bold()).padding(.horizontal)
                        .accessibilityIdentifier("catalog-title")
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
