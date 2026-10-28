import SwiftUI

struct DiscoveryRails: View {
    let rows: [DiscoveryRail]
    let app: AppModel
    var titleOverrides: [String: String] = [:]
    var disableDefaultRanking = false
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(rows.filter { $0.personal?.available() != false }) { row in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text(titleOverrides[row.id] ?? row.title).font(HarborTheme.font(18, weight: .semibold)).accessibilityIdentifier("rail-" + row.id); Spacer(); NavigationLink(DesktopInterfaceText.value("View all")) { DiscoveryGrid(rail: row, app: app, titleOverride: titleOverrides[row.id]) }.font(HarborTheme.font(12)).foregroundStyle(.secondary).accessibilityIdentifier("discovery-browse-" + row.id) }.padding(.horizontal)
                    if row.id.hasSuffix("-top10") && !disableDefaultRanking { TopTenRail(metas: row.metas) }
                    else { ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(row.metas, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media) }.buttonStyle(.plain).accessibilityLabel(media.name).accessibilityIdentifier(row.kind == "anime" ? "anime-media" : row.kind == "movie" ? "catalog-movie" : "catalog-media") }
                        }.padding(.horizontal)
                    }.scrollIndicators(.hidden).posterRowBehavior() }
                }
            }
        }
    }
}

struct DiscoveryGrid: View {
    let rail: DiscoveryRail
    let app: AppModel
    var titleOverride: String? = nil
    @State private var items: [Media] = []
    @State private var page = 1
    @State private var loading = false
    @State private var finished = false
    @State private var error: String?
    var body: some View {
        if let personal = rail.personal, !personal.available() {
            ContentUnavailableView(DesktopInterfaceText.value("Trakt"), systemImage: "person.crop.circle.badge.exclamationmark")
        } else if let service = StreamingServiceDefinition.all.first(where: { rail.path == "streaming:" + $0.key }) {
            StreamingCatalogView(service: service, app: app)
        } else { grid }
    }
    private var grid: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                PosterGrid(spacing: 22) {
                    ForEach(items, id: \.identity) { media in NavigationLink(value: media) { Poster(media: media, width: nil) }.buttonStyle(.plain) }
                }
                if let error { Text(error).font(.caption).foregroundStyle(.orange); Button("Reintentar") { Task { await load() } } }
                if loading { ProgressView() }
                if !items.isEmpty && !finished && !loading && error == nil { ProgressView().task { await load() } }
            }.padding()
        }.background(HarborTheme.background).navigationTitle(titleOverride ?? rail.title).navigationBarTitleDisplayMode(.inline)
            .task { if items.isEmpty { await load() } }
            .onChange(of: rail.personal?.available()) { _, available in
                if available == false { items = []; finished = true; error = nil }
            }
    }
    private func load() async {
        guard !loading && !finished else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let next: [Media]
            if let personal = rail.personal {
                guard personal.available() else { throw CancellationError() }
                next = try await personal.page(page)
            } else if ["anime:picks", "home:fixed"].contains(rail.path) { next = page == 1 ? rail.metas : [] }
            else if rail.kind == "anime" { next = try await AnimeService.shared.page(rail, page: page) }
            else { next = try await TMDBService().page(rail, page: page, configuration: MetadataPreferences.shared.configuration()) }
            try Task.checkCancellation()
            guard rail.personal?.available() != false else { items = []; finished = true; return }
            var known = Set(items.map(\.identity)); let additions = next.filter { known.insert($0.identity).inserted }
            items.append(contentsOf: additions); page += 1; finished = next.isEmpty || additions.isEmpty || rail.path == "home:fixed"
        } catch is CancellationError { return }
        catch { self.error = safeMessage(error) }
    }
}
