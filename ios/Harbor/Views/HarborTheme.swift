import SwiftUI

enum HarborTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.07)
    static let accent = Color(red: 0.48, green: 0.65, blue: 0.94)
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
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(row.metas, id: \.identity) { media in
                                NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal)
                    }.scrollIndicators(.hidden)
                }
            }
        }
    }
}
