import SwiftUI

struct StreamPickerView: View {
    let model: DetailModel
    let addons: [Addon]
    let episode: Episode?
    let downloading: Bool
    let downloadMessage: String?
    let play: (StreamOffer) -> Void
    let download: ((StreamOffer) -> Void)?
    let refresh: () -> Void
    let back: () -> Void
    @State private var selectedID: Int?
    @State private var sourcesExpanded = false
    @State private var provider: String?
    @State private var overviewExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var busy: Bool { model.resolving || model.pendingPlayback != nil }
    private var selected: StreamOffer? {
        model.offers.first { $0.id == selectedID } ?? StreamPreferences.shared.preferred(model.offers) ?? model.offers.first
    }
    private var tiers: [StreamOffer] {
        var seen = Set<String>()
        let representatives = model.offers.filter { seen.insert($0.quality).inserted }
        let order = ["4K_DV", "4K_HDR", "4K", "1080p_HDR", "1080p", "720p", "SD", "ROUGH"]
        return representatives.sorted { (order.firstIndex(of: $0.quality) ?? 8) < (order.firstIndex(of: $1.quality) ?? 8) }
    }
    private var providers: [StreamOffer] {
        var seen = Set<String>()
        return model.offers.filter { seen.insert($0.pickerInstance).inserted }
    }
    private var sources: [StreamOffer] { model.offers.filter { provider == nil || $0.pickerInstance == provider } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                navigation
                header
                content
            }.padding(20).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .toolbar(.hidden, for: .navigationBar).accessibilityIdentifier("stream-picker-scroll")
            .onChange(of: model.offers.map(\.id)) { _, _ in
                if !model.offers.contains(where: { $0.id == selectedID }) { selectedID = nil }
                if !providers.contains(where: { $0.pickerInstance == provider }) { provider = nil }
            }
            .onChange(of: episode?.id) { _, _ in selectedID = nil; overviewExpanded = false; provider = nil }
    }
    private var navigation: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                HStack(spacing: 10) {
                    navIcon("stream-back", size: 26)
                    Text(DesktopInterfaceText.value("Back")).font(HarborTheme.font(17, weight: .semibold))
                }
            }.buttonStyle(.plain).accessibilityIdentifier("stream-picker-close")
            Spacer(minLength: 12)
            Button(action: refresh) {
                HStack(spacing: 10) {
                    navIcon("stream-refresh", size: 20)
                    Text(DesktopInterfaceText.value("Refresh")).font(HarborTheme.font(17, weight: .semibold))
                }
            }.buttonStyle(.plain).disabled(model.loadingStreams || busy)
                .accessibilityLabel(DesktopInterfaceText.value("Refresh sources")).accessibilityIdentifier("stream-picker-refresh")
        }.foregroundStyle(ThemePreferences.shared.color("ink-muted"))
    }
    private func navIcon(_ name: String, size: CGFloat) -> some View {
        Image(name).resizable().scaledToFit().frame(width: size, height: size)
            .frame(width: 48, height: 48).background(ThemePreferences.shared.color("elevated").opacity(0.7), in: .circle)
            .overlay { Circle().stroke(ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }.accessibilityHidden(true)
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let episode {
                Text(episodeEyebrow(episode)).font(HarborTheme.font(11, weight: .semibold)).tracking(2.5)
                    .textCase(.uppercase).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                Text(episode.name ?? episode.title ?? "\(DesktopInterfaceText.value("Episode")) \(episode.episode ?? 0)")
                    .font(HarborTheme.displayFont(34)).accessibilityIdentifier("stream-picker-title")
                if let overview = episode.overview, !overview.isEmpty { overviewView(overview) }
            } else {
                if let release = model.media.releaseInfo {
                    Text(([release] + Array((model.media.genres ?? []).prefix(2))).joined(separator: " · "))
                        .font(HarborTheme.font(11, weight: .semibold)).tracking(2.5).textCase(.uppercase)
                        .foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                }
                Text(model.media.name).font(HarborTheme.displayFont(36)).accessibilityIdentifier("stream-picker-title")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func episodeEyebrow(_ episode: Episode) -> String {
        let season = "\(DesktopInterfaceText.value("Season")) \(episode.season ?? 1)"
        let number = "\(DesktopInterfaceText.value("Episode")) \(String(format: "%02d", episode.episode ?? 0))"
        return [model.media.name, season, number].joined(separator: " · ")
    }
    private func overviewView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(HarborTheme.font(14.5)).lineSpacing(4).lineLimit(overviewExpanded ? nil : 2)
                .foregroundStyle(ThemePreferences.shared.color("ink-muted"))
            Button { overviewExpanded.toggle() } label: {
                HStack(spacing: 4) {
                    Text(DesktopInterfaceText.value(overviewExpanded ? "Show less" : "View more"))
                    Image("settings-chevron-down").resizable().scaledToFit().frame(width: 14, height: 14).rotationEffect(.degrees(overviewExpanded ? 180 : 0))
                }.font(HarborTheme.font(13, weight: .semibold)).frame(minHeight: 44)
            }.buttonStyle(.plain)
        }
    }
    @ViewBuilder private var content: some View {
        if model.loadingStreams {
            HarborLoader(size: 72).frame(maxWidth: .infinity).padding(.vertical, 48)
        } else if let offer = selected {
            if let error = model.error { Text(error).font(HarborTheme.font(14)).foregroundStyle(.orange) }
            if let downloadMessage { Text(downloadMessage).font(HarborTheme.font(13)).foregroundStyle(ThemePreferences.shared.color("ink-muted")) }
            StreamPrimaryCard(media: model.media, episode: episode, offer: offer, addonLogo: logo(offer), busy: busy, downloading: downloading,
                              play: { play(offer) }, download: download.map { action in { action(offer) } })
            if tiers.count > 1 { qualityStrip }
            sourceDrawer
        } else {
            emptySources
        }
    }
    private var qualityStrip: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(DesktopInterfaceText.value("Switch quality")).font(HarborTheme.font(12, weight: .bold)).tracking(2.5).textCase(.uppercase)
                .foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
            StreamChipLayout(spacing: 10) {
                ForEach(tiers) { offer in qualityButton(offer) }
            }
        }.accessibilityIdentifier("stream-quality-strip")
    }
    private func qualityButton(_ offer: StreamOffer) -> some View {
        let active = offer.quality == selected?.quality
        return Button { selectedID = offer.id } label: {
            HStack(spacing: 10) {
                StreamFormatBadges(kinds: [offer.pickerLeadBadge], large: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(DesktopInterfaceText.value(offer.pickerLeadLabel)).font(HarborTheme.font(12.5, weight: .bold))
                    Text([offer.pickerStatus.map { DesktopInterfaceText.value($0) }, offer.pickerSize].compactMap { $0 }.joined(separator: " · "))
                        .font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                }
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 56)
                .background(active ? HarborTheme.ink.opacity(0.05) : HarborTheme.background.opacity(0.6), in: .rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(active ? HarborTheme.ink.opacity(0.35) : ThemePreferences.shared.color("edge-soft"), lineWidth: 1) }
        }.buttonStyle(.plain).disabled(busy).accessibilityAddTraits(active ? [.isSelected] : [])
            .accessibilityIdentifier("stream-quality-" + offer.quality)
    }
    private var sourceDrawer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { sourcesExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(DesktopInterfaceText.value(sourcesExpanded ? "Hide all sources" : "All sources")).font(HarborTheme.font(13, weight: .semibold))
                    Text(String(model.offers.count)).font(HarborTheme.font(12)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                    Image("settings-chevron-down").resizable().scaledToFit().frame(width: 14, height: 14).rotationEffect(.degrees(sourcesExpanded ? 180 : 0))
                }.frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("stream-all-sources")
            if sourcesExpanded {
                if providers.count > 1 { providerFilters }
                LazyVStack(spacing: 0) {
                    ForEach(Array(sources.enumerated()), id: \.element.id) { index, offer in
                        if index > 0 { Divider().overlay(ThemePreferences.shared.color("edge-soft").opacity(0.3)) }
                        StreamSourceRow(media: model.media, episode: episode, offer: offer, addonLogo: logo(offer), busy: busy, downloading: downloading,
                                        play: { play(offer) }, download: download.map { action in { action(offer) } })
                    }
                }.background(HarborTheme.background.opacity(0.8), in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThemePreferences.shared.color("edge-soft").opacity(0.6), lineWidth: 1) }
                    .transition(.opacity).accessibilityIdentifier("stream-source-list")
            }
        }
    }
    private var providerFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                providerPill(nil, name: DesktopInterfaceText.value("All"), count: model.offers.count)
                ForEach(providers) { offer in
                    providerPill(offer.pickerInstance, name: offer.source, count: model.offers.filter { $0.pickerInstance == offer.pickerInstance }.count)
                }
            }
        }.scrollIndicators(.hidden)
    }
    private func providerPill(_ id: String?, name: String, count: Int) -> some View {
        let active = provider == id
        return Button { provider = id } label: {
            HStack(spacing: 6) { Text(name).lineLimit(1); Text(String(count)).opacity(0.7) }
                .font(HarborTheme.font(12, weight: .semibold)).padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(active ? HarborTheme.background : ThemePreferences.shared.color("ink-muted"))
                .background(active ? HarborTheme.ink : ThemePreferences.shared.color("elevated").opacity(0.5), in: .capsule)
        }.buttonStyle(.plain).accessibilityAddTraits(active ? [.isSelected] : [])
    }
    private var emptySources: some View {
        VStack(spacing: 16) {
            Text(DesktopInterfaceText.value(model.filteredSources ? "Strict filters dropped everything" : "No source returned a stream")).font(HarborTheme.displayFont(26)).multilineTextAlignment(.center)
            if let error = model.error, !model.filteredSources { Text(error).font(HarborTheme.font(14)).foregroundStyle(ThemePreferences.shared.color("ink-muted")).multilineTextAlignment(.center) }
            Button(action: refresh) { Text(DesktopInterfaceText.value("Retry")).font(HarborTheme.font(14, weight: .semibold)).padding(.horizontal, 24).frame(minHeight: 48).foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule) }
                .buttonStyle(.plain).accessibilityIdentifier("stream-picker-retry")
        }.padding(24).frame(maxWidth: .infinity).background(HarborTheme.background.opacity(0.7), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(ThemePreferences.shared.color("edge-soft"), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
    }
    private func logo(_ offer: StreamOffer) -> String? {
        if let priority = offer.raw["addonPriority"].integer, addons.indices.contains(priority),
           addons[priority].manifest["id"].string == offer.addonID { return addons[priority].manifest["logo"].string }
        let matches = addons.filter { $0.transportUrl == offer.pickerInstance || $0.manifest["id"].string == offer.addonID }
        return matches.count == 1 ? matches.first?.manifest["logo"].string : nil
    }
}
