import SwiftUI

/// Desktop's "Sequels & Prequels" strip (`components/search/anime-relations.tsx`) over `animeRelations`.
/// The requests need no account. Titles open in their own detail page. Side stories are not listed: Desktop's
/// `animeRelations` leaves them out, and the franchise data on the detail page already covers them.
struct AniListRelationsSection: View {
    let media: Media
    let app: AppModel
    @State private var relations: [AniListRelation] = []

    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }

    var body: some View {
        Group {
            if !relations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text(text("Sequels & Prequels"))
                        .font(HarborTheme.font(13, weight: .semibold)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(relations) { relation in
                                NavigationLink { DetailView(media: detailMedia(relation), app: app) } label: { relationCard(relation) }
                                    .buttonStyle(.plain).accessibilityIdentifier("anilist-relation-\(relation.id)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("anilist-relations")
            }
        }
        .task(id: media.identity) { await load() }
    }

    private func relationCard(_ relation: AniListRelation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: relation.poster, maxPixels: 240, showsPlaceholder: false)
                .aspectRatio(2.0 / 3.0, contentMode: .fill).frame(width: 110, height: 165)
                .clipShape(.rect(cornerRadius: 10))
            Text(relation.name).font(.caption.weight(.semibold)).lineLimit(2)
            HStack(spacing: 6) {
                Text(text(relation.kind == .prequel ? "Prequel" : "Sequel")).textCase(.uppercase)
                if let year = relation.year { Text(String(year)) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 110, alignment: .leading)
    }

    /// A relation opens as an AniList title, the same id form the AniList lists use.
    private func detailMedia(_ relation: AniListRelation) -> Media {
        var item = Media(id: "anilist:\(relation.id)", type: "series", name: relation.name)
        item.poster = relation.poster
        return item
    }

    private func load() async {
        let token = AniListAccount.forOwner(app.personalOwner).session?.accessToken ?? ""
        guard let anilistID = await AniListThreadsService.anilistID(for: media.id, token: token) else {
            relations = []
            return
        }
        let service = AniListRelationsService(client: AniListClient(transport: AniListHTTPTransport()))
        let found = await service.relations(anilistID: anilistID)
        guard !Task.isCancelled else { return }
        relations = found
    }
}
