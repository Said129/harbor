import SwiftUI

struct PosterAppearanceControls: View {
    var samples = SettingsPreviewArtwork.films
    @AppStorage("rowCardStyle") private var style = "poster"
    @AppStorage("tvCardLogoPos") private var logo = "bottomStart"
    @AppStorage("posterScale") private var scale = 1.0
    @AppStorage("posterRadius") private var radius = 12.0
    @AppStorage("posterEffect") private var effect = "off"
    @AppStorage("posterQuality") private var quality = "high"
    private var configuration: PosterCardConfiguration { .init(style: style, logoPosition: logo, scale: scale, radius: radius, effect: effect, quality: quality) }
    private func text(_ key: String) -> String { DesktopInterfaceText.value(key) }
    var body: some View {
        HarborSettingsSection(text("Poster card style")) {
            VStack(alignment: .leading, spacing: 18) {
                if let sample = samples.first {
                    ProfilePoster(media: sample, width: nil, artworkFallbacks: [], honorsRowStyle: true, showsTitle: false, showsRating: false)
                        .frame(maxWidth: (configuration.style == .tv ? 236 : 118) * configuration.scale)
                        .frame(maxWidth: .infinity).accessibilityElement(children: .ignore).accessibilityLabel(sample.name)
                        .accessibilityValue(configuration.style.rawValue).accessibilityIdentifier("poster-card-preview")
                }
                Text(text("Row card style")).font(HarborTheme.font(15, weight: .medium))
                Text(text("TV shows wide art cards with the logo on them. Poster is the classic grid.")).font(.caption).foregroundStyle(.secondary)
                Picker(text("Row card style"), selection: $style) { Text(text("Poster")).tag("poster"); Text(text("TV")).tag("tv") }
                    .pickerStyle(.segmented).accessibilityIdentifier("poster-card-style")
                if configuration.style == .tv {
                    Picker(text("Logo position"), selection: $logo) {
                        Text(text("Start")).tag("bottomStart"); Text(text("Center")).tag("center"); Text(text("End")).tag("bottomEnd")
                    }.pickerStyle(.segmented).accessibilityIdentifier("poster-logo-position")
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(text("Size")); Spacer(); Text(text(PosterCardConfiguration.sizes[configuration.sizeIndex].label)).foregroundStyle(.secondary) }
                    Slider(value: Binding(get: { Double(configuration.sizeIndex) }, set: { scale = PosterCardConfiguration.sizes[Int($0.rounded())].scale }), in: 0...5, step: 1)
                        .accessibilityLabel(text("Size")).accessibilityIdentifier("poster-card-size")
                    Text(text("How large every poster card is drawn across Home and search.")).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(text("Corner radius")); Spacer(); Text(text(configuration.radiusLabel) + " · \(Int(configuration.radius))px").foregroundStyle(.secondary) }
                    Slider(value: $radius, in: 0...40, step: 2).accessibilityLabel(text("Corner radius")).accessibilityIdentifier("poster-card-radius")
                }
                Picker(text("Load effect"), selection: $effect) {
                    Text(text("Blur up")).tag("blur"); Text(text("Fade")).tag("fade"); Text(text("Instant")).tag("off")
                }.pickerStyle(.segmented).accessibilityIdentifier("poster-card-effect")
                Text(text("Blur up looks smoothest. Fade is lighter on older devices. Instant turns it off.")).font(.caption).foregroundStyle(.secondary)
                Picker(text("Quality"), selection: $quality) {
                    Text(text("Balanced")).tag("balanced"); Text(text("High")).tag("high"); Text(text("Maximum")).tag("max")
                }.pickerStyle(.segmented).accessibilityIdentifier("poster-card-quality")
                Text(text("High is sized to your screen and looks identical to full res on far less memory. Balanced saves the most. Maximum keeps original resolution.")).font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(HarborTheme.surface, in: .rect(cornerRadius: 12))
        }
    }
}

/// Each grid observes the same profile-scoped setting as the horizontal rows.
struct PosterGrid<Content: View>: View {
    @AppStorage("rowCardStyle") private var style = "poster"
    @AppStorage("posterScale") private var scale = 1.0
    @State private var availableWidth: CGFloat = 106
    var alignment: HorizontalAlignment = .center
    var spacing: CGFloat = 22
    @ViewBuilder var content: () -> Content
    var body: some View {
        let configuration = PosterCardConfiguration(style: style, scale: scale)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(configuration.gridMinimum(availableWidth: Double(availableWidth)))), spacing: 12, alignment: .top)], alignment: alignment, spacing: spacing, content: content)
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { availableWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in availableWidth = width }
                }
            }
    }
}
