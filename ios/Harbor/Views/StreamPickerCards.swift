import SwiftUI

struct StreamPrimaryCard: View {
    let media: Media
    let episode: Episode?
    let offer: StreamOffer
    let addonLogo: String?
    let busy: Bool
    let downloading: Bool
    let play: () -> Void
    let download: (() -> Void)?

    private var landscape: String? { episode?.thumbnail ?? media.background }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            artwork
            StreamOfferText(media: media, episode: episode, offer: offer, addonLogo: addonLogo, primary: true)
            audioLanguages
            StreamFormatBadges(kinds: offer.pickerBadges, large: false)
            actions
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(HarborTheme.background.opacity(0.7), in: .rect(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(HarborTheme.ink.opacity(0.08), lineWidth: 1) }
            .accessibilityIdentifier("stream-primary-card")
    }
    private var artwork: some View {
        Artwork(url: landscape ?? media.poster, fallback: landscape == nil ? media.fallbackPoster : media.fallbackBackground, maxPixels: 900)
            .frame(height: landscape == nil ? 220 : 165).frame(maxWidth: landscape == nil ? 148 : .infinity)
            .clipped().clipShape(.rect(cornerRadius: 16)).accessibilityHidden(true)
            .overlay(alignment: .bottomLeading) {
                if landscape != nil, let logo = media.logo {
                    Artwork(url: logo, fit: .fit, maxPixels: 360, showsPlaceholder: false)
                        .frame(width: 165, height: 42).padding(12).allowsHitTesting(false)
                }
            }
    }
    private var audioLanguages: some View {
        Group {
            if offer.pickerLanguages.isEmpty {
                Text(DesktopInterfaceText.value("Audio not labeled")).font(HarborTheme.font(12.5, weight: .semibold))
                    .foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
            } else {
                StreamChipLayout(spacing: 10) {
                    ForEach(Array(offer.pickerLanguages.prefix(6)), id: \.self) { code in
                        HStack(spacing: 6) {
                            HarborLanguageFlag(code: code)
                            Text(SubtitleLanguages.preferenceName(code)).font(HarborTheme.font(12.5, weight: .semibold))
                        }.foregroundStyle(ThemePreferences.shared.color("ink-muted"))
                    }
                }
            }
        }
    }
    private var actions: some View {
        HStack(spacing: 14) {
            Button(action: play) {
                HStack(spacing: 10) {
                    Image(offer.pickerExternalURL == nil ? "ui-play-filled" : "stream-external").resizable().scaledToFit().frame(width: 20, height: 20)
                    Text(DesktopInterfaceText.value(offer.pickerExternalURL == nil ? "Play" : "Open in browser"))
                        .font(HarborTheme.font(15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                }.padding(.horizontal, 24).frame(minHeight: 56)
                    .foregroundStyle(HarborTheme.background).background(HarborTheme.ink, in: .capsule)
            }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("stream-offer")
            if let download, offer.pickerExternalURL == nil {
                Button(action: download) {
                    Image("stream-download").resizable().scaledToFit().frame(width: 20, height: 20)
                        .frame(width: 48, height: 48).background(HarborTheme.surface, in: .circle)
                }.buttonStyle(.plain).disabled(downloading || busy)
                    .accessibilityLabel(DesktopInterfaceText.value("Download")).accessibilityIdentifier("stream-download")
            }
            Spacer(minLength: 0)
            if let status = offer.pickerStatus {
                Text(DesktopInterfaceText.value(status)).font(HarborTheme.font(12, weight: .semibold))
                    .foregroundStyle(ThemePreferences.shared.color("ink-muted"))
            }
        }
    }
}

struct StreamSourceRow: View {
    let media: Media
    let episode: Episode?
    let offer: StreamOffer
    let addonLogo: String?
    let busy: Bool
    let downloading: Bool
    let play: () -> Void
    let download: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: play) {
                VStack(alignment: .leading, spacing: 10) {
                    StreamOfferText(media: media, episode: episode, offer: offer, addonLogo: addonLogo, primary: false)
                    HStack(spacing: 10) {
                        StreamFormatBadges(kinds: offer.pickerTierBadges, large: false)
                        Spacer(minLength: 0)
                        ForEach(Array(offer.pickerLanguages.prefix(4)), id: \.self) { HarborLanguageFlag(code: $0) }
                        Image(offer.pickerExternalURL == nil ? "ui-play-filled" : "stream-external").resizable().scaledToFit().frame(width: 15, height: 15)
                    }
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("stream-source-row")
            if let download, offer.pickerExternalURL == nil {
                Button(action: download) { Image("stream-download").resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).disabled(busy || downloading).accessibilityLabel(DesktopInterfaceText.value("Download"))
            }
        }.padding(.horizontal, 16).padding(.vertical, 16)
    }
}

private struct StreamOfferText: View {
    let media: Media
    let episode: Episode?
    let offer: StreamOffer
    let addonLogo: String?
    let primary: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: primary ? 10 : 6) {
            Text(offer.pickerTitle(media: media, episode: episode)).font(.system(size: primary ? 15.5 : 14, design: .monospaced))
                .lineLimit(primary ? 3 : 2).textSelection(.enabled).accessibilityIdentifier(primary ? "stream-primary-title" : "stream-source-title")
            if !offer.pickerFilename.isEmpty, offer.pickerFilename != offer.pickerTitle(media: media, episode: episode) {
                Text(offer.pickerFilename).font(.system(size: primary ? 12.5 : 11, design: .monospaced))
                    .foregroundStyle(ThemePreferences.shared.color("ink-subtle")).lineLimit(2).textSelection(.enabled)
            }
            HStack(alignment: .top, spacing: 8) {
                if let addonLogo { Artwork(url: addonLogo, fit: .fit, maxPixels: 64, showsPlaceholder: false).frame(width: 20, height: 20).clipShape(.rect(cornerRadius: 4)).accessibilityHidden(true) }
                Text(([offer.pickerContributor] + offer.pickerSummary).joined(separator: " · "))
                    .font(HarborTheme.font(12, weight: .semibold)).foregroundStyle(ThemePreferences.shared.color("ink-subtle"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StreamFormatBadges: View {
    let kinds: [String]
    var large = false
    var body: some View {
        StreamChipLayout(spacing: 6) {
            ForEach(kinds, id: \.self) { kind in
                Image("stream-badge-" + kind).resizable().scaledToFit()
                    .frame(width: large ? 60 : 30, height: large ? 56 : 28)
                    .accessibilityLabel(kind)
            }
        }
    }
}

/// Native wrapping for Harbor's flex-wrap badges and provider chips.
struct StreamChipLayout: Layout {
    var spacing: CGFloat = 8
    private func positions(width: CGFloat, subviews: Subviews) -> [(CGPoint, CGSize)] {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        return subviews.map { view in
            let size = view.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            let point = CGPoint(x: x, y: y)
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
            return (point, size)
        }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let layout = positions(width: width, subviews: subviews)
        return CGSize(width: width, height: layout.map { $0.0.y + $0.1.height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, item) in zip(subviews, positions(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + item.0.x, y: bounds.minY + item.0.y), anchor: .topLeading, proposal: ProposedViewSize(item.1))
        }
    }
}
