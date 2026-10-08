import SwiftUI
import CoreText

private struct RankNumeral: UIViewRepresentable {
    let rank: Int
    func makeUIView(context: Context) -> UILabel { let label = UILabel(); label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal); return label }
    func updateUIView(_ label: UILabel, context: Context) {
        let attributes: [UIFontDescriptor.AttributeName: Any] = [.name: "Oswald-Regular", UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [NSNumber(value: 0x77676874): NSNumber(value: 600)]]
        let font = UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: 195)
        label.attributedText = NSAttributedString(string: String(rank), attributes: [.font: font, .strokeColor: UIColor.white.withAlphaComponent(0.55), .foregroundColor: UIColor.clear, .strokeWidth: 1.4, .kern: -2])
    }
}

struct TopTenRail: View {
    let metas: [Media]
    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(Array(metas.prefix(10).enumerated()), id: \.element.identity) { index, media in
                    NavigationLink(value: media) {
                        ZStack(alignment: .topLeading) {
                            RankNumeral(rank: index + 1).frame(width: 135, height: 177)
                                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.65), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                            Poster(media: media).padding(.leading, 76)
                        }.frame(width: 192, height: 213, alignment: .topLeading).clipped()
                    }.buttonStyle(.plain).accessibilityLabel("\(index + 1). \(media.name)").accessibilityIdentifier(media.type == "movie" ? "catalog-movie" : "catalog-media")
                }
            }.padding(.horizontal)
        }.scrollIndicators(.hidden)
    }
}
