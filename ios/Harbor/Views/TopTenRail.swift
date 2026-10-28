import SwiftUI
import CoreText

private struct RankNumeral: UIViewRepresentable {
    let rank: Int
    var size: CGFloat = 195
    func makeUIView(context: Context) -> UILabel { let label = UILabel(); label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal); return label }
    func updateUIView(_ label: UILabel, context: Context) {
        let attributes: [UIFontDescriptor.AttributeName: Any] = [.name: "Oswald-Regular", UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [NSNumber(value: 0x77676874): NSNumber(value: 600)]]
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
        label.attributedText = NSAttributedString(string: String(rank), attributes: [.font: font, .strokeColor: UIColor.white.withAlphaComponent(0.55), .foregroundColor: UIColor.clear, .strokeWidth: 1.4, .kern: -2])
    }
}

struct TopTenRail: View {
    let metas: [Media]
    var app: AppModel? = nil
    var customList: CustomList? = nil
    @AppStorage("rowCardStyle") private var style = "poster"
    @AppStorage("posterScale") private var scale = 1.0
    private var configuration: PosterCardConfiguration { .init(style: style, scale: scale) }
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(Array(metas.prefix(10).enumerated()), id: \.element.identity) { index, media in
                    card(media, index: index)
                        .buttonStyle(.plain).accessibilityLabel("\(index + 1). \(media.name)").accessibilityIdentifier(media.type == "movie" ? "catalog-movie" : "catalog-media")
                }
            }.padding(.horizontal)
        }.scrollIndicators(.hidden).posterRowBehavior()
    }
    @ViewBuilder private func card(_ media: Media, index: Int) -> some View {
        if let app, let customList, let item = customList.items.first(where: { $0.id == media.id }) {
            NavigationLink { CustomListItemDestination(app: app, item: item, listID: customList.id) } label: {
                RankedPosterArtwork(rank: index + 1, media: media, configuration: configuration)
            }
        } else {
            NavigationLink(value: media) { RankedPosterArtwork(rank: index + 1, media: media, configuration: configuration) }
        }
    }
}

private struct RankedPosterArtwork: View {
    let rank: Int
    let media: Media
    let configuration: PosterCardConfiguration
    @AppStorage("posterDockMagnification") private var dock = false
    @AppStorage("posterBackdropExpansion") private var expansion = false
    @Environment(\.posterRowContext) private var row
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wideWidth: CGFloat?
    private var baseWidth: Double { configuration.rowWidth() + 76 * configuration.scale }
    private var baseHeight: Double { configuration.rowWidth() / configuration.aspectRatio + (configuration.style == .tv ? 0 : 39) }
    private var effects: Bool { configuration.style == .poster && (dock || expansion) }
    private var baseFactor: Double {
        guard let viewport = row?.viewport.width, viewport > 0 else { return 1 }
        return min(1, max(1, viewport - 32) / baseWidth)
    }
    private var aspectRatio: Double {
        guard let wideWidth else { return baseWidth / baseHeight }
        return (wideWidth + 76 * configuration.scale * baseFactor) / (baseHeight * baseFactor)
    }
    var body: some View {
        GeometryReader { bounds in
            let factor = effects && (row?.viewport.width ?? 0) > 0 ? baseFactor : bounds.size.width / baseWidth
            ZStack(alignment: .topLeading) {
                RankNumeral(rank: rank, size: 195 * configuration.scale * factor)
                    .frame(width: 135 * configuration.scale * factor, height: 177 * configuration.scale * factor)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.65), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                Poster(media: media, width: nil, onExpansionWidthChange: { wideWidth = $0 })
                    .padding(.leading, 76 * configuration.scale * factor)
            }
        }.aspectRatio(aspectRatio, contentMode: .fit)
            .containerRelativeFrame(.horizontal, alignment: .leading) { available, _ in
                wideWidth.map { $0 + 76 * configuration.scale * baseFactor } ?? min(max(1, available - 32), baseWidth)
            }
            .modifier(RankedPosterClipping(enabled: !effects))
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.48), value: wideWidth)
    }
}
private struct RankedPosterClipping: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.clipped() } else { content }
    }
}
