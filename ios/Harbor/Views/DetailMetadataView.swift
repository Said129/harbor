import SwiftUI

struct DetailMetadataView: View {
    let media: Media
    let app: AppModel
    @Environment(\.openURL) private var openURL
    @State private var gallery = "videos"
    @State private var imageURL: String?
    private var details: MediaDetails? { media.details }
    private var information: [(String, String)] {
        var fields: [(String, String)] = []
        if let directors = media.director, !directors.isEmpty { fields.append(("Dirección", directors.joined(separator: ", "))) }
        for (job, label) in [("Writer", "Guion"), ("Screenplay", "Guion adaptado"), ("Producer", "Producción"), ("Director of Photography", "Fotografía"), ("Original Music Composer", "Música"), ("Editor", "Montaje")] {
            let names = details?.crew.filter { $0.role == job }.map(\.name) ?? []
            if !names.isEmpty { fields.append((label, names.joined(separator: ", "))) }
        }
        if let status = details?.status, !status.isEmpty { fields.append(("Estado", status)) }
        if let studios = details?.studios, !studios.isEmpty { fields.append(("Estudios", studios.joined(separator: " · "))) }
        let countries = details?.countries.joined(separator: " · ") ?? ""
        if !countries.isEmpty { fields.append(("País", countries)) } else if let country = media.country, !country.isEmpty { fields.append(("País", country)) }
        if let language = details?.language { fields.append(("Idioma original", Locale.current.localizedString(forLanguageCode: language) ?? language)) }
        if let genres = media.genres, !genres.isEmpty { fields.append(("Géneros", genres.joined(separator: " · "))) }
        if let budget = details?.budget { fields.append(("Presupuesto", budget.formatted(.currency(code: "USD").precision(.fractionLength(0))))) }
        if let revenue = details?.revenue { fields.append(("Recaudación", revenue.formatted(.currency(code: "USD").precision(.fractionLength(0))))) }
        if let votes = details?.votes, votes > 0 { fields.append(("Valoraciones en TMDB", votes.formatted())) }
        return fields
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if let credits = details?.cast, !credits.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Reparto · \(credits.count)").font(.headline)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(credits) { credit in
                                VStack(alignment: .leading, spacing: 6) {
                                    Artwork(url: credit.photo, maxPixels: 350).frame(width: 102, height: 140).clipShape(.rect(cornerRadius: 10))
                                    Text(credit.name).font(.caption.bold()).lineLimit(2)
                                    if !credit.role.isEmpty { Text(credit.role).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                                }.frame(width: 102, alignment: .leading)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            } else if let cast = media.cast, !cast.isEmpty { VStack(alignment: .leading, spacing: 12) { Text("Reparto · \(cast.count)").font(.headline); Text(cast.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) } }
            if let collection = details?.collection, !collection.isEmpty { rail(details?.collectionName ?? "Colección", items: collection) }
            if let similar = details?.similar, !similar.isEmpty { rail("Más como esto", items: similar) }
            if let recommendations = details?.recommendations, !recommendations.isEmpty { rail("También te puede gustar", items: recommendations) }
            if let details, !details.trailers.isEmpty || !details.backdrops.isEmpty || !details.posters.isEmpty || !details.logos.isEmpty { mediaGallery(details) }
            if !information.isEmpty {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Información").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 24) {
                        ForEach(Array(information.enumerated()), id: \.offset) { _, field in
                            VStack(alignment: .leading, spacing: 9) { Text(field.0.uppercased()).font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.secondary); Text(field.1).font(.subheadline) }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }.padding(.horizontal, 20).padding(.bottom, 32)
            .sheet(isPresented: Binding(get: { imageURL != nil }, set: { if !$0 { imageURL = nil } })) {
                NavigationStack {
                    if let imageURL {
                        Artwork(url: imageURL, fit: .fit, maxPixels: 1800)
                            .background(.black).navigationTitle("Imagen")
                            .toolbar { Button("Cerrar") { self.imageURL = nil } }
                    }
                }
            }
    }
    private func rail(_ title: String, items: [Media]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            ScrollView(.horizontal) { LazyHStack(alignment: .top, spacing: 12) { ForEach(items, id: \.identity) { item in NavigationLink { DetailView(media: item, app: app) } label: { Poster(media: item) }.buttonStyle(.plain) } } }.scrollIndicators(.hidden)
        }
    }
    private func mediaGallery(_ details: MediaDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Media").font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach([("videos", "Vídeos", details.trailers.count), ("backdrops", "Fondos", details.backdrops.count), ("posters", "Carteles", details.posters.count), ("logos", "Logos", details.logos.count)], id: \.0) { key, name, count in
                        if count > 0 { HarborPill(title: "\(name)  \(count)", selected: gallery == key) { gallery = key } }
                    }
                }
            }.scrollIndicators(.hidden)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    if gallery == "videos" {
                        ForEach(details.trailers) { trailer in
                            Button { if let url = URL(string: trailer.url) { openURL(url) } } label: { VStack(alignment: .leading, spacing: 6) { Artwork(url: trailer.thumbnail, maxPixels: 500).frame(width: 220, height: 124).clipShape(.rect(cornerRadius: 10)).overlay { Image("ui-play-filled").resizable().scaledToFit().frame(width: 28, height: 28).shadow(radius: 4) }; Text(trailer.title).font(.caption).lineLimit(2) }.frame(width: 220) }.buttonStyle(.plain)
                        }
                    } else {
                        let urls = gallery == "backdrops" ? details.backdrops : gallery == "posters" ? details.posters : details.logos
                        ForEach(urls, id: \.self) { url in Button { imageURL = url } label: { Artwork(url: url, fit: gallery == "logos" ? .fit : .fill, maxPixels: 500).frame(width: gallery == "posters" ? 110 : 220, height: gallery == "posters" ? 165 : 124).clipShape(.rect(cornerRadius: 10)) }.buttonStyle(.plain).accessibilityLabel("Abrir imagen") }
                    }
                }
            }.scrollIndicators(.hidden)
        }.onAppear { if details.trailers.isEmpty { gallery = !details.backdrops.isEmpty ? "backdrops" : !details.posters.isEmpty ? "posters" : "logos" } }
    }
}
