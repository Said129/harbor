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
    @AppStorage("rowCardStyle") private var style = "poster"
    @AppStorage("posterScale") private var scale = 1.0
    private var configuration: PosterCardConfiguration { .init(style: style, scale: scale) }
    private var wantedWidth: Double { configuration.rowWidth() + 76 * configuration.scale }
    private var wantedHeight: Double { configuration.rowWidth() / configuration.aspectRatio + (configuration.style == .tv ? 0 : 39) }
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(Array(metas.prefix(10).enumerated()), id: \.element.identity) { index, media in
                    NavigationLink(value: media) {
                        GeometryReader { bounds in
                            let factor = bounds.size.width / wantedWidth
                            ZStack(alignment: .topLeading) {
                                RankNumeral(rank: index + 1, size: 195 * configuration.scale * factor)
                                    .frame(width: 135 * configuration.scale * factor, height: 177 * configuration.scale * factor)
                                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.65), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                                Poster(media: media, width: nil).padding(.leading, 76 * configuration.scale * factor)
                            }
                        }.aspectRatio(wantedWidth / wantedHeight, contentMode: .fit)
                            .containerRelativeFrame(.horizontal, alignment: .leading) { available, _ in min(max(1, available - 32), CGFloat(wantedWidth)) }.clipped()
                    }.buttonStyle(.plain).accessibilityLabel("\(index + 1). \(media.name)").accessibilityIdentifier(media.type == "movie" ? "catalog-movie" : "catalog-media")
                }
            }.padding(.horizontal)
        }.scrollIndicators(.hidden)
    }
}
