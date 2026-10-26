import SwiftUI

struct ProfilePoster: View {
    let media: Media
    let width: CGFloat?
    let artworkFallbacks: [String]
    let honorsRowStyle: Bool
    var showsTitle = true
    var showsRating = true
    @AppStorage("rowCardStyle") private var style = "poster"
    @AppStorage("tvCardLogoPos") private var logoPosition = "bottomStart"
    @AppStorage("posterScale") private var scale = 1.0
    @AppStorage("posterRadius") private var radius = 12.0
    @AppStorage("posterEffect") private var effect = "off"
    @AppStorage("posterQuality") private var quality = "high"
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loaded = false
    @State private var logoLoaded = false
    @State private var resolvedArtwork: ResolvedCardArtwork?
    @State private var resolvedKey = ""
    @State private var localizedPoster: String?
    @State private var posterResolvedKey = ""
    private var overrides: TitleArtworkPreferences { .shared }
    private var localizesPoster: Bool {
        overrides.value(.poster, id: media.artworkID) == nil && CardArtworkResolver.canLocalizePoster(media, configuration: MetadataPreferences.shared.configuration())
    }
    private var posterPending: Bool { localizesPoster && posterResolvedKey != artworkKey }
    private var posterURL: String? {
        overrides.value(.poster, id: media.artworkID) ?? (posterPending ? nil : (posterResolvedKey == artworkKey ? localizedPoster : nil) ?? media.poster)
    }
    private var posterFallback: String? { posterPending ? nil : media.fallbackPoster }
    private var posterFallbacks: [String] { posterPending ? [] : [media.poster, media.background].compactMap { $0 } + artworkFallbacks }
    private var logoURL: String? { overrides.value(.logo, id: media.artworkID) ?? (resolvedKey == artworkKey ? resolvedArtwork?.logo : nil) ?? media.logo }
    private var backgroundURL: String? {
        overrides.value(.backdrop, id: media.artworkID) ?? (media.background != media.poster ? media.background : nil)
            ?? (resolvedKey == artworkKey ? resolvedArtwork?.backdrop : nil)
    }
    private var resolutionMedia: Media {
        var result = media; result.background = overrides.value(.backdrop, id: media.artworkID) ?? media.background; return result
    }
    private var artworkKey: String {
        if configuration.style != .tv && !localizesPoster { return "poster|" + media.identity }
        return "\(style)|\(AppProfileContext.shared.activationID)|" + CardArtworkResolver.cacheKey(resolutionMedia, MetadataPreferences.shared.configuration(), pinnedLogo: overrides.value(.logo, id: media.artworkID))
    }
    private var configuration: PosterCardConfiguration { .init(style: honorsRowStyle ? style : "poster", logoPosition: logoPosition, scale: scale, radius: radius, effect: effect, quality: quality) }
    private var pixelLimit: Int { configuration.pixels(width: width.map { configuration.rowWidth(base: Double($0)) } ?? (configuration.style == .tv ? 318 : 150) * configuration.scale, displayScale: Double(displayScale)) }
    var body: some View {
        Group {
            if let width {
                card.containerRelativeFrame(.horizontal, alignment: .leading) { available, _ in
                    min(max(1, available - 32), CGFloat(configuration.rowWidth(base: Double(width))))
                }
            } else { card }
        }.foregroundStyle(HarborTheme.ink).contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: configuration.scale)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: configuration.radius)
            .onChange(of: logoURL) { _, _ in logoLoaded = false }
            .task(id: artworkKey) {
                let key = artworkKey
                let value = localizesPoster ? await CardArtworkResolver.shared.poster(media, configuration: MetadataPreferences.shared.configuration()) : nil
                guard !Task.isCancelled, key == artworkKey else { return }
                localizedPoster = value; posterResolvedKey = key
            }
            .task(id: artworkKey) {
                guard configuration.style == .tv else { return }
                let key = artworkKey
                let value = await CardArtworkResolver.shared.resolve(resolutionMedia, configuration: MetadataPreferences.shared.configuration(), pinnedLogo: overrides.value(.logo, id: media.artworkID))
                guard !Task.isCancelled, key == artworkKey else { return }
                resolvedArtwork = value; resolvedKey = key
            }
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: configuration.style == .tv ? 0 : 6) {
            Group {
                if configuration.style == .tv { televisionArtwork }
                else {
                    Artwork(url: posterURL, fallback: posterFallback, fallbacks: posterFallbacks,
                        maxPixels: pixelLimit, onImageAvailability: { loaded = $0 }, onLoadCompletion: { _ in loaded = true })
                }
            }.aspectRatio(configuration.aspectRatio, contentMode: .fit)
                .background(HarborTheme.surface).clipShape(.rect(cornerRadius: configuration.radius)).accessibilityHidden(true)
                .blur(radius: !reduceMotion && configuration.effect == .blur && !loaded ? 8 : 0)
                .opacity(configuration.effect == .off || reduceMotion || loaded ? 1 : 0)
                .animation(reduceMotion || configuration.effect == .off ? nil : .easeOut(duration: 0.35), value: loaded)
                .overlay(alignment: .bottomTrailing) { if showsRating && configuration.style == .poster { rating } }
            if showsTitle && configuration.style == .poster { Text(media.name).font(.caption.weight(.medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var rating: some View {
        if (media.ratingSource == "TMDB" ? InterfacePreferences.shared.showTmdbBadge : InterfacePreferences.shared.showImdbBadge), let value = media.imdbRating {
            HStack(spacing: 3) {
                Text(media.ratingSource ?? "IMDb").font(.system(size: 7, weight: .black)).foregroundStyle(.black).padding(2)
                    .background(media.ratingSource == "TMDB" ? Color.mint : .yellow, in: .rect(cornerRadius: 2))
                Text(value).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
            }.padding(4).background(.black.opacity(0.8), in: .capsule).padding(5)
        }
    }
    private var televisionArtwork: some View {
        ZStack {
            Artwork(url: posterURL, fallback: posterFallback, fallbacks: posterFallbacks, maxPixels: pixelLimit,
                onImageAvailability: { if $0 { loaded = true } }, onLoadCompletion: { _ in loaded = true })
                .scaleEffect(1.1).blur(radius: 18).saturation(1.2)
            if let backdrop = backgroundURL {
                Artwork(url: backdrop, maxPixels: pixelLimit, showsPlaceholder: false, onImageAvailability: { if $0 { loaded = true } })
            }
            LinearGradient(stops: configuration.logoPosition == .center
                ? [.init(color: HarborTheme.background.opacity(0.8), location: 0), .init(color: HarborTheme.background.opacity(0.45), location: 0.5), .init(color: HarborTheme.background.opacity(0.7), location: 1)]
                : [.init(color: HarborTheme.background, location: 0.02), .init(color: HarborTheme.background.opacity(0.65), location: 0.34), .init(color: HarborTheme.background.opacity(0.18), location: 0.62), .init(color: .clear, location: 0.84)], startPoint: .bottom, endPoint: .top)
            HStack(alignment: configuration.logoPosition == .center ? .center : .bottom, spacing: 10) {
                Artwork(url: posterURL, fallback: posterFallback, fallbacks: posterFallbacks, maxPixels: 180)
                    .frame(width: 36, height: 54).clipShape(.rect(cornerRadius: 2))
                    .overlay { RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.12), lineWidth: 1) }
                VStack(alignment: captionAlignment, spacing: 4) {
                    ZStack(alignment: captionFrameAlignment) {
                        Text(media.name).font(HarborTheme.font(14.5, weight: .semibold)).lineLimit(2).foregroundStyle(logoLoaded ? .clear : HarborTheme.ink)
                        if let logo = logoURL {
                            Artwork(url: logo, fit: .fit, fitAlignment: .leading, maxPixels: 600, showsPlaceholder: false, onImageAvailability: { logoLoaded = $0 }).frame(height: 34)
                        }
                    }
                    if let year = media.releaseInfo { Text(year).font(HarborTheme.font(11)).foregroundStyle(ThemePreferences.shared.color("ink-muted")).lineLimit(1) }
                }.multilineTextAlignment(captionTextAlignment).frame(maxWidth: .infinity, alignment: captionFrameAlignment)
            }.padding(configuration.logoPosition == .center ? 0 : 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: logoAlignment)
        }.clipped()
    }
    private var logoAlignment: Alignment {
        switch configuration.logoPosition { case .center: .center; case .bottomStart: .bottomLeading; case .bottomEnd: .bottomTrailing }
    }
    private var captionAlignment: HorizontalAlignment {
        switch configuration.logoPosition { case .center: .center; case .bottomStart: .leading; case .bottomEnd: .trailing }
    }
    private var captionFrameAlignment: Alignment {
        switch configuration.logoPosition { case .center: .center; case .bottomStart: .leading; case .bottomEnd: .trailing }
    }
    private var captionTextAlignment: TextAlignment {
        switch configuration.logoPosition { case .center: .center; case .bottomStart: .leading; case .bottomEnd: .trailing }
    }
}
