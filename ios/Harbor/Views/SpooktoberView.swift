import SwiftUI
import UIKit

struct SpooktoberInvitation: View {
    let preferences: SpooktoberInvitationPreferences
    let open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Button(action: open) {
                    HStack(spacing: 14) {
                        Image("spook-pumpkin").resizable().scaledToFit().frame(width: 62, height: 68).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Spooktober").font(.custom("Fraunces-9ptBlack", size: 27))
                            Text("Cine, música y descubrimientos de medianoche.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }.padding(18).padding(.trailing, 8).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).background {
                    ZStack {
                        HarborTheme.surface
                        Image("spook-hill").resizable().foregroundStyle(ThemePreferences.shared.color("raised").opacity(0.3))
                        Image("spook-field").resizable().foregroundStyle(ThemePreferences.shared.color("raised").opacity(0.15))
                    }
                }.clipShape(.rect(cornerRadius: 14)).accessibilityIdentifier("spooktober-open")
                Button { preferences.dismiss() } label: {
                    Image(systemName: "xmark").font(.caption).padding(10).background(HarborTheme.background.opacity(0.8), in: .circle)
                }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Ocultar invitación de Spooktober")
            }
            if let error = preferences.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(.horizontal)
    }
}

struct SpooktoberView: View {
    let app: AppModel
    @State private var items: [SpooktoberItem] = []
    @State private var query = ""
    @State private var kind = "Todos"
    @State private var error: String?
    private let sections: [(String, String, String)] = [
        ("classics", "Clásicos de Halloween", "midnight-film"),
        ("new", "Novedades y próximos estrenos", "candle"),
        ("directors", "Maestros del terror", "midnight-film"),
        ("modern", "Terror contemporáneo", "moon"),
        ("international", "Terror de todo el mundo", "ink-eye"),
        ("cozy", "Favoritos de Halloween", "candy"),
        ("series", "Series de terror", "ghost-tv"),
        ("books", "Libros de terror", "haunted-book"),
        ("manga", "Manga de terror", "ink-eye")
    ]
    private var filtered: [SpooktoberItem] {
        items.filter { item in
            (kind == "Todos" || item.type == kind) && (query.isEmpty || item.title.localizedCaseInsensitiveContains(query) || item.creator.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header
                Picker("Contenido", selection: $kind) {
                    Text("Todo").tag("Todos"); Text("Cine").tag("Film"); Text("Series").tag("Series"); Text("Libros").tag("Book"); Text("Manga").tag("Manga")
                }.pickerStyle(.segmented).padding(.horizontal)
                if let error {
                    ContentUnavailableView { Label("No se pudo cargar Spooktober", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Reintentar") { Task { await load(force: true) } } }
                } else if items.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                else if filtered.isEmpty { ContentUnavailableView.search(text: query) }
                else { ForEach(sections, id: \.0) { section in shelf(section) } }
            }.padding(.vertical, 20)
        }.background(HarborTheme.background).navigationTitle("Spooktober").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Buscar títulos o autores")
            .task { await load() }
            .refreshable { await load(force: true) }
            .accessibilityIdentifier("spooktober-scroll")
    }
    private var header: some View {
        HStack(spacing: 14) {
            Image("spook-pumpkin").resizable().scaledToFit().frame(width: 78, height: 78).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Spooktober").font(.custom("Fraunces-9ptBlack", size: 36))
                Text("Tus descubrimientos de Halloween").font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(.horizontal)
    }
    @ViewBuilder private func shelf(_ section: (String, String, String)) -> some View {
        let selected = filtered.filter { $0.section == section.0 }
        if !selected.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image("spook-" + section.2).resizable().scaledToFit().frame(width: 28, height: 28).accessibilityHidden(true)
                    Text(section.1).font(.headline)
                }.padding(.horizontal)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(selected) { item in
                            if let media = item.media {
                                NavigationLink { DetailView(media: media, app: app) } label: { SpooktoberCard(item: item) }.buttonStyle(.plain)
                            } else {
                                NavigationLink { SpooktoberSourceView(item: item) } label: { SpooktoberCard(item: item) }.buttonStyle(.plain)
                            }
                        }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden)
            }
        }
    }
    private func load(force: Bool = false) async {
        do {
            items = try await SpooktoberUpdates.shared.catalog(); error = nil
            let refreshed = try await SpooktoberUpdates.shared.refresh(force: force)
            try Task.checkCancellation(); items = refreshed
        }
        catch is CancellationError { return }
        catch { self.error = "No se pudieron leer las selecciones de Spooktober." }
    }
}

private struct SpooktoberCard: View {
    let item: SpooktoberItem
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpooktoberCover(item: item).frame(width: 116, height: 174).clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
            Text(item.title).font(.caption.weight(.medium)).lineLimit(2)
            Text(item.year).font(.caption2).foregroundStyle(.secondary)
        }.frame(width: 116, alignment: .leading).accessibilityLabel(item.title + ", " + item.year)
    }
}
private struct SpooktoberCover: View {
    let item: SpooktoberItem
    var body: some View {
        if let name = item.localPoster, let image = UIImage(named: name) { BoundedArtworkImage(image: image, fit: .fill) }
        else { Artwork(url: item.poster, fallback: item.media?.fallbackPoster, maxPixels: 600) }
    }
}
private struct SpooktoberSourceView: View {
    let item: SpooktoberItem
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SpooktoberCover(item: item).frame(width: 180, height: 270).clipShape(.rect(cornerRadius: 12)).frame(maxWidth: .infinity)
                Text(item.title).font(.largeTitle.bold())
                Text(item.creator + " · " + item.year).foregroundStyle(.secondary)
                Text(item.description)
                if let url = item.sourceURL { Link(destination: url) { Label("Ver la fuente original", systemImage: "arrow.up.right.square") }.buttonStyle(.bordered) }
            }.padding()
        }.background(HarborTheme.background).navigationBarTitleDisplayMode(.inline)
    }
}
