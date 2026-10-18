import SwiftUI

struct CollectionsView: View {
    let app: AppModel
    @State private var model = CollectionsModel()
    @State private var query = ""
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                if MetadataPreferences.shared.tmdbKey.isEmpty {
                    ContentUnavailableView { Label("Colecciones", image: "nav-collections") } description: { Text("Conecta TMDB para explorar las sagas y sus películas.") } actions: { NavigationLink("Configurar TMDB") { MetadataSettingsView() } }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 14)], spacing: 22) {
                        ForEach(model.items) { collection in
                            NavigationLink { CollectionDetailView(collection: collection, app: app) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Artwork(url: collection.poster, fallback: collection.background, maxPixels: 600).frame(height: 220).clipShape(.rect(cornerRadius: 12))
                                    Text(collection.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    if model.loading { ProgressView() }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await model.load(query: query, reset: false) } } }
                    if !model.items.isEmpty && !model.finished && !model.loading && model.error == nil { ProgressView().task { await model.load(query: query, reset: false) } }
                    if model.items.isEmpty && !model.loading && model.error == nil { ContentUnavailableView.search(text: query) }
                }
            }.padding()
        }.background(HarborTheme.background).navigationTitle("Colecciones").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Buscar sagas…")
            .task(id: query + MetadataPreferences.shared.tmdbKey + MetadataPreferences.shared.language) { if !MetadataPreferences.shared.tmdbKey.isEmpty { await model.load(query: query, reset: true) } }
    }
}

struct CollectionDetailView: View {
    let collection: MovieCollection
    let app: AppModel
    @State private var details: CollectionDetails?
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Artwork(url: details?.background ?? collection.background, fallback: collection.poster, maxPixels: 1400).frame(height: 230).clipped()
                VStack(alignment: .leading, spacing: 18) {
                    Text(details?.name ?? collection.name).font(.title.bold())
                    if let description = details?.description ?? collection.description { Text(description).font(.subheadline).foregroundStyle(.secondary) }
                    if let details {
                        Text("\(details.parts.count) películas").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 106), spacing: 12, alignment: .top)], spacing: 22) {
                            ForEach(details.parts, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media, width: nil) }.buttonStyle(.plain) }
                        }
                    } else if let error { Text(error).foregroundStyle(.orange); Button("Reintentar") { Task { await load() } } }
                    else { ProgressView() }
                }.padding()
            }
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline).task { await load() }
    }
    private func load() async {
        error = nil
        do { details = try await TMDBService().collection(collection.id, configuration: MetadataPreferences.shared.configuration()) }
        catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}
