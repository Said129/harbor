import SwiftUI

struct DiscoveryRails: View {
    let rows: [DiscoveryRail]
    let app: AppModel
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(row.title).font(.headline); Spacer(); NavigationLink("Ver todo") { DiscoveryGrid(rail: row, app: app) }.font(.caption).foregroundStyle(.secondary) }.padding(.horizontal)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(row.metas, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain).accessibilityLabel(media.name) }
                        }.padding(.horizontal)
                    }.scrollIndicators(.hidden)
                }
            }
        }
    }
}

struct DiscoveryGrid: View {
    let rail: DiscoveryRail
    let app: AppModel
    @State private var items: [Media] = []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 22) {
                    ForEach(items, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain) }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load() } } }
                if loading { ProgressView() }
                if !items.isEmpty && !finished && !loading && error == nil { ProgressView().task { await load() } }
            }.padding()
        }.background(HarborTheme.background).navigationTitle(rail.title).navigationBarTitleDisplayMode(.inline)
            .task { if items.isEmpty { await load() } }
    }
    private func load() async {
        guard !loading && !finished else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let next = try await TMDBService().page(rail, page: page, configuration: MetadataPreferences.shared.configuration())
            try Task.checkCancellation()
            var known = Set(items.map(\.identity)); let additions = next.filter { known.insert($0.identity).inserted }
            items.append(contentsOf: additions); page += 1; finished = next.isEmpty || additions.isEmpty
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}
