import SwiftUI

@MainActor struct MusicCatalogRail: View {
    let row: MusicCatalogRow
    let client: any MusicCatalogCalling
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayTitle).font(.title3.weight(.semibold))
                if let subtitle = row.subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }.padding(.horizontal, 18)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    if row.layout == .trackGrid {
                        ForEach(Array(stride(from: 0, to: row.items.count, by: 3)), id: \.self) { offset in
                            VStack(spacing: 12) {
                                ForEach(Array(row.items[offset..<min(offset + 3, row.items.count)])) { item in
                                    NavigationLink { MusicCatalogDetailView(item: item, client: client) } label: { MusicCatalogCompactItem(item: item) }
                                        .buttonStyle(.plain).accessibilityIdentifier("music-catalog-item-" + item.id)
                                }
                            }.frame(width: 280)
                        }
                    } else {
                        ForEach(row.items) { item in
                            NavigationLink { MusicCatalogDetailView(item: item, client: client) } label: {
                                MusicCatalogCoverCard(item: item, wide: row.layout == .wide)
                            }.buttonStyle(.plain).accessibilityIdentifier("music-catalog-item-" + item.id)
                        }
                    }
                }.padding(.horizontal, 18)
            }.scrollIndicators(.hidden)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("music-catalog-row-" + row.id)
    }
}

@MainActor struct MusicCatalogCoverCard: View {
    let item: MusicCatalogItem
    var wide = false
    private var width: CGFloat { wide ? 220 : 140 }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Artwork(url: item.artwork, maxPixels: 480, failureIcon: "nav-music")
                .frame(width: width, height: wide ? 132 : width)
                .clipShape(.rect(cornerRadius: item.isArtist ? width / 2 : 12)).accessibilityHidden(true)
            Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
            if let subtitle = item.subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }.frame(width: width, alignment: .leading).foregroundStyle(HarborTheme.ink).contentShape(Rectangle())
    }
}

@MainActor struct MusicCatalogCompactItem: View {
    let item: MusicCatalogItem
    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: item.artwork, maxPixels: 240, failureIcon: "nav-music")
                .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: item.isArtist ? 24 : 8)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.medium)).lineLimit(2)
                if let subtitle = item.subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if case .track(let track) = item { Text(track.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }.frame(minHeight: 48).foregroundStyle(HarborTheme.ink).contentShape(Rectangle())
    }
}

@MainActor struct MusicCatalogSearchSections: View {
    let result: MusicCatalogSearch
    let client: any MusicCatalogCalling
    private var rows: [MusicCatalogRow] {
        [MusicCatalogRow(id: "search:artists", title: "Artists", titleLiteral: false, subtitle: nil, layout: .circles, source: "catalog", items: result.artists.map(MusicCatalogItem.artist)),
         MusicCatalogRow(id: "search:tracks", title: "Tracks", titleLiteral: false, subtitle: nil, layout: .trackGrid, source: "catalog", items: result.tracks.map(MusicCatalogItem.track)),
         MusicCatalogRow(id: "search:albums", title: "Albums", titleLiteral: false, subtitle: nil, layout: .covers, source: "catalog", items: result.albums.map(MusicCatalogItem.album)),
         MusicCatalogRow(id: "search:playlists", title: "Playlists", titleLiteral: false, subtitle: nil, layout: .covers, source: "catalog", items: result.playlists.map(MusicCatalogItem.playlist))]
    }
    var body: some View {
        if let top = result.top {
            VStack(alignment: .leading, spacing: 12) {
                Text(DesktopInterfaceText.value("Top result")).font(.title3.weight(.semibold))
                NavigationLink { MusicCatalogDetailView(item: top, client: client) } label: { MusicCatalogCompactItem(item: top) }.buttonStyle(.plain)
            }.padding(.horizontal, 18)
        }
        ForEach(rows.filter { !$0.items.isEmpty }) { MusicCatalogRail(row: $0, client: client) }
        if result.top == nil, rows.allSatisfy({ $0.items.isEmpty }) {
            ContentUnavailableView(DesktopInterfaceText.value("No results"), systemImage: "magnifyingglass")
        }
    }
}
