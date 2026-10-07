import SwiftUI

struct MangaEditorialView: View {
    let universes: Bool
    let shelf: MangaShelf
    let client: SuwayomiClient?
    let sources: [MangaSource]
    let local: [MangaBook]
    let connection: MangaConnection
    @State private var search: MangaEditorialSearch?
    @State private var selected: MangaEditorial.Universe?
    @State private var resolved: MangaBook?
    @State private var error: String?
    @State private var connecting = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                Text(universes ? "Universos" : "Colecciones").font(.custom("QRAmesBeta-Regular", size: 34))
                if universes {
                    Text("Elige un mundo y sumérgete en todo lo que contiene.").font(HarborTheme.font(15)).foregroundStyle(.secondary)
                    universeGrid
                } else if let search {
                    ForEach(MangaEditorial.original?.collections ?? []) { definition in
                        MangaEditorialRail(definition: definition, shelf: shelf, client: client, search: search)
                    }
                }
                if let error { Text(error).font(HarborTheme.font(13)).foregroundStyle(.orange) }
                if client == nil {
                    Button("Fuentes de manga") { connecting = true }.font(HarborTheme.font(14, weight: .medium)).frame(minHeight: 44)
                }
            }.padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .toolbar(.visible, for: .navigationBar).navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(universes ? "manga-universes" : "manga-collections")
            .task { if search == nil { search = MangaEditorialSearch(client: client, sources: sources, local: local) } }
            .task(id: selected?.id) {
                guard let selected, let search else { return }
                error = nil
                do {
                    let item = try await search.resolve(selected.query)
                    try Task.checkCancellation()
                    if let item { resolved = item } else { error = "No se encontró ningún manga" }
                } catch is CancellationError { return }
                catch { self.error = safeMessage(error) }
                self.selected = nil
            }
            .navigationDestination(item: $resolved) { book in MangaDetailView(book: book, shelf: shelf, client: book.server == client?.server.id ? client : nil) }
            .sheet(isPresented: $connecting, onDismiss: {
                if client?.server != connection.server { dismiss() }
            }) { MangaConnectionView(connection: connection) }
    }
    private var universeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(MangaEditorial.original?.universes ?? []) { universe in
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { selected = universe } } label: {
                    ZStack(alignment: .bottomLeading) {
                        Artwork(url: universe.backdrop, maxPixels: 600).accessibilityHidden(true)
                        LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 8) {
                            if selected?.id == universe.id { ProgressView().tint(.white) }
                            if let logo = universe.logo { Artwork(url: logo, fit: .fit, maxPixels: 500, showsPlaceholder: false).frame(height: 52) }
                            Text(universe.name).font(HarborTheme.font(15, weight: .semibold)).lineLimit(2)
                        }.padding(14)
                    }.frame(height: 150).clipShape(.rect(cornerRadius: 14)).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(selected != nil).accessibilityLabel(universe.name).accessibilityIdentifier("manga-universe-" + universe.id)
            }
        }
    }
}

private struct MangaEditorialRail: View {
    let definition: MangaEditorial.Collection
    let shelf: MangaShelf
    let client: SuwayomiClient?
    let search: MangaEditorialSearch
    @State private var books: [MangaBook] = []
    @State private var loading = false
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MangaEditorial.title(definition.name)).font(HarborTheme.font(18, weight: .semibold))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(books) { book in
                        NavigationLink { MangaDetailView(book: book, shelf: shelf, client: book.server == client?.server.id ? client : nil) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                MangaImage(book: book, owner: shelf.owner, path: book.cover, client: book.server == client?.server.id ? client : nil, maxPixels: 500).frame(width: 116, height: 174).clipShape(.rect(cornerRadius: 10))
                                Text(book.title).font(HarborTheme.font(12, weight: .medium)).lineLimit(2).frame(width: 116, alignment: .leading)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
            if loading { ProgressView() }
            if let error { Text(error).font(HarborTheme.font(12)).foregroundStyle(.orange); Button("Reintentar") { Task { await load() } } }
            else if loaded && books.isEmpty { Text("No se encontró ningún manga").font(HarborTheme.font(13)).foregroundStyle(.secondary) }
        }.task { if !loaded { await load() } }
    }
    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        var seen = Set(books.map(\.id))
        for start in stride(from: 0, to: definition.titles.count, by: 4) {
            do { try Task.checkCancellation() } catch { return }
            let titles = Array(definition.titles[start..<min(start + 4, definition.titles.count)])
            let result = await withTaskGroup(of: (Int, MangaBook?, String?).self) { group in
                for (index, title) in titles.enumerated() {
                    group.addTask {
                        do { return (index, try await search.resolve(title), nil) }
                        catch is CancellationError { return (index, nil, nil) }
                        catch { return (index, nil, safeMessage(error)) }
                    }
                }
                var values: [(Int, MangaBook?, String?)] = []
                for await value in group { values.append(value) }
                return values.sorted { $0.0 < $1.0 }
            }
            guard !Task.isCancelled else { return }
            for (_, book, failure) in result {
                if let book, seen.insert(book.id).inserted { books.append(book) }
                if let failure { error = failure }
            }
        }
        loaded = true
    }
}
