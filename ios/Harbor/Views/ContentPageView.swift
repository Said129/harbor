import SwiftUI

struct ContentPageView: View {
    let app: AppModel
    let kind: String
    let title: String
    @State private var model: ContentPageModel
    @MainActor init(app: AppModel, kind: String, title: String) { self.app = app; self.kind = kind; self.title = title; _model = State(initialValue: app.pageModel(kind)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !model.heroes.isEmpty { CinemaHero(metas: model.heroes, app: app) }
                if model.loading && model.rows.isEmpty && model.curated.isEmpty { ProgressView("Cargando \(title.lowercased())…").frame(maxWidth: .infinity).padding(40) }
                if let error = model.error, model.rows.isEmpty && model.curated.isEmpty {
                    ContentUnavailableView { Label(title, image: kind == "movie" ? "nav-movies" : "nav-shows") } description: { Text(error) } actions: {
                        Button("Reintentar") { Task { await model.load(kind: kind, app: app, refresh: true) } }
                    }
                }
                DiscoveryRails(rows: model.curated, app: app)
                CatalogRails(rows: model.rows, app: app)
            }.padding(.bottom, 24)
        }.background(HarborTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("content-\(kind)")
            .task(id: "\(app.storageReady)|\(app.addons.filter(\.enabled).map(\.id).joined())|\(MetadataPreferences.shared.tmdbKey)|\(MetadataPreferences.shared.region)|\(MetadataPreferences.shared.language)|\(MetadataPreferences.shared.translateTitles)") { if app.storageReady { await model.load(kind: kind, app: app) } }
            .onChange(of: app.rows.count) { _, _ in if !["movie", "series", "kids"].contains(kind) { Task { await model.load(kind: kind, app: app, refresh: true) } } }
            .refreshable { await model.load(kind: kind, app: app, refresh: true) }
    }
}

struct CinemaHero: View {
    let metas: [Media]
    let app: AppModel
    @State private var selected = 0
    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $selected) {
                ForEach(Array(metas.prefix(5).enumerated()), id: \.element.identity) { index, media in
                    GeometryReader { geometry in
                        ZStack(alignment: .bottomLeading) {
                            Artwork(url: media.background, fallback: media.fallbackBackground, fallbacks: [media.poster].compactMap { $0 }, maxPixels: 1400)
                                .frame(width: geometry.size.width, height: geometry.size.height).accessibilityHidden(true)
                            LinearGradient(colors: [.black.opacity(0.12), HarborTheme.background.opacity(0.55), HarborTheme.background], startPoint: .top, endPoint: .bottom).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 14) {
                                Text("DESTACADO HOY").font(.system(size: 9, weight: .semibold)).tracking(4).foregroundStyle(.white.opacity(0.5))
                                if let logo = media.logo {
                                    Artwork(url: logo, fit: .fit, maxPixels: 650).frame(maxWidth: 260).frame(height: 66).accessibilityHidden(true)
                                } else { Text(media.name).font(.system(size: 30, weight: .bold)).lineLimit(2) }
                                HStack(spacing: 14) {
                                    if let year = media.releaseInfo { Text(year).foregroundStyle(.secondary) }
                                    if let rating = media.imdbRating { HStack(spacing: 5) { Text(media.ratingSource ?? "IMDb").font(.system(size: 9, weight: .black)).foregroundStyle(.black).padding(3).background(.yellow, in: .rect(cornerRadius: 2)); Text(rating).fontWeight(.semibold) } }
                                    if let runtime = media.runtime { Text(runtime).foregroundStyle(.secondary) }
                                }.font(.caption)
                                if let description = media.description { Text(description).font(.subheadline).foregroundStyle(.white.opacity(0.72)).lineLimit(3) }
                                HStack(spacing: 10) {
                                    NavigationLink { DetailView(media: media, app: app, playImmediately: true) } label: { Label("Reproducir", systemImage: "play.fill").font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 13).foregroundStyle(.black).background(.white, in: .rect(cornerRadius: 8)) }
                                        .buttonStyle(.plain).accessibilityIdentifier("hero-play")
                                    NavigationLink(value: media) { Label("Más información", systemImage: "info.circle").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 13).background(.black.opacity(0.3), in: .rect(cornerRadius: 8)) }.buttonStyle(.plain)
                                }
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }.tag(index).accessibilityElement(children: .contain).accessibilityIdentifier(index == 0 ? "home-hero" : "hero-page-\(index)")
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 410)
            if metas.count > 1 {
                HStack(spacing: 7) {
                    ForEach(0..<min(5, metas.count), id: \.self) { index in
                        Button { withAnimation { selected = index } } label: { Capsule().fill(selected == index ? .white : .white.opacity(0.3)).frame(width: selected == index ? 24 : 7, height: 4).frame(minHeight: 24) }.accessibilityLabel("Destacado \(index + 1)")
                    }
                }
            }
        }
    }
}
