import SwiftUI

/// Desktop's Live TV "Top networks" rows (`src/views/live/top-networks-rows.tsx`): for the region set in
/// Settings, each network the channel list carries gets a card, grouped by category. A card plays its channel.
/// Shown only on the plain channel list (no search text, no category, no favourites filter), like Desktop.
struct LiveTVTopNetworksRow: View {
    let region: String
    let channels: [LiveChannel]
    let active: Bool
    let onPlay: (LiveChannel) -> Void
    @State private var sections: [LiveTVNetworkSection] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                sectionView(section)
            }
        }
        .padding(.vertical, sections.isEmpty ? 0 : 8)
        .task(id: taskKey) {
            sections = active ? LiveTVRegionNetworks.sections(region: region, channels: channels) : []
        }
    }

    private var taskKey: String {
        "\(active)|\(region)|\(channels.count)|\(channels.first?.id ?? "")|\(channels.last?.id ?? "")"
    }

    private func sectionView(_ section: LiveTVNetworkSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DesktopInterfaceText.value(section.title))
                .font(HarborTheme.font(11, weight: .semibold)).tracking(2).textCase(.uppercase)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(section.networks) { item in
                        networkCard(item)
                    }
                }
            }
        }
    }

    private func networkCard(_ item: LiveTVResolvedNetwork) -> some View {
        Button { onPlay(item.channel) } label: {
            VStack(spacing: 8) {
                if let logo = item.channel.logo {
                    Artwork(url: logo, fit: .fit, maxPixels: 240).frame(width: 120, height: 60)
                } else {
                    Image("nav-livetv").resizable().scaledToFit().frame(width: 30, height: 30).frame(width: 120, height: 60)
                        .foregroundStyle(.secondary)
                }
                Text(DesktopInterfaceText.value(item.def.displayName))
                    .font(HarborTheme.font(14, weight: .semibold)).lineLimit(1)
            }
            .frame(width: 140)
            .padding(10)
            .background(HarborTheme.ink.opacity(0.06), in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(HarborTheme.ink)
        .accessibilityIdentifier("live-tv-top-network")
    }
}
