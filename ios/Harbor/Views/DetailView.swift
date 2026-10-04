import SwiftUI

struct DetailView: View {
    let app: AppModel
    @State private var model: DetailModel
    @State private var showStreams = false
    @State private var selectedEpisode: Episode?
    @State private var resolutionTask: Task<Void, Never>?
    init(media: Media, app: AppModel) { self.app = app; _model = State(initialValue: DetailModel(media, service: app.service)) }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AsyncImage(url: (model.media.background ?? model.media.poster).flatMap(URL.init(string:))) { $0.resizable().scaledToFill() } placeholder: { Rectangle().fill(.white.opacity(0.05)) }
                    .frame(height: 220).clipped()
                VStack(alignment: .leading, spacing: 16) {
                    Text(model.media.name).font(.largeTitle.bold())
                    Text([model.media.releaseInfo, model.media.genres?.joined(separator: " · ")].compactMap { $0 }.joined(separator: " · ")).foregroundStyle(.secondary)
                    Text(model.media.description ?? "")
                    if let error = model.error { Text(error).foregroundStyle(.orange) }
                    if model.loading { ProgressView() }
                    if model.media.type != "series" {
                        Button { openStreams() } label: { Label("Ver streams", systemImage: "play.fill").frame(maxWidth: .infinity).padding(8) }.buttonStyle(.borderedProminent)
                    }
                    if let episodes = model.media.videos {
                        ForEach(episodes) { episode in
                            Button { openStreams(episode) } label: {
                                HStack { Image(systemName: "play.circle"); VStack(alignment: .leading) { Text(episode.name ?? episode.title ?? episode.id); Text("T\(episode.season ?? 0) · E\(episode.episode ?? 0)").font(.caption).foregroundStyle(.secondary) }; Spacer() }.frame(minHeight: 48)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding()
            }
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
        .task { await model.load(app.addons) }
        .sheet(isPresented: $showStreams, onDismiss: { resolutionTask?.cancel() }) {
            NavigationStack {
                List {
                    if model.loadingStreams { ProgressView("Consultando addons…") }
                    if let error = model.error { Text(error).foregroundStyle(.orange) }
                    ForEach(Array(model.warnings.enumerated()), id: \.offset) { Text("Solicitud addon: \($0.element)").font(.caption) }
                    ForEach(model.offers) { offer in
                        Button { resolutionTask = Task { await model.play(offer) } } label: { VStack(alignment: .leading, spacing: 8) { Text(offer.title); Text("\(offer.source) · \(offer.quality)").font(.caption).foregroundStyle(.secondary) }.frame(minHeight: 44) }.disabled(model.resolving)
                    }
                }.navigationTitle("Streams").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { showStreams = false } } }
                .fullScreenCover(item: $model.playback) { source in PlayerView(source: source, title: model.media.name) }
                .task(id: selectedEpisode?.id ?? model.media.id) { await model.findStreams(app.addons, episode: selectedEpisode) }
            }.presentationDetents([.medium, .large])
        }
    }
    private func openStreams(_ episode: Episode? = nil) {
        selectedEpisode = episode
        showStreams = true
    }
}
