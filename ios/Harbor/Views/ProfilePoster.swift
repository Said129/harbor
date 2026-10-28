import SwiftUI

struct ProfilePoster: View {
    let media: Media
    let width: CGFloat?
    let artworkFallbacks: [String]
    let honorsRowStyle: Bool
    var showsTitle = true
    var showsRating = true
    var onExpansionWidthChange: ((CGFloat?) -> Void)? = nil
    @AppStorage("rowCardStyle") private var style = "poster"
    @AppStorage("tvCardLogoPos") private var logoPosition = "bottomStart"
    @AppStorage("posterScale") private var scale = 1.0
    @AppStorage("posterRadius") private var radius = 12.0
    @AppStorage("posterEffect") private var effect = "off"
    @AppStorage("posterQuality") private var quality = "high"
    @AppStorage("posterFocusedCard") private var focusEnabled = false
    @AppStorage("posterBackdropExpansion") private var expansionEnabled = false
    @AppStorage("posterDockMagnification") private var dockEnabled = false
    @AppStorage("posterDockTransitionMs") private var dockMilliseconds = 760.0
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var keyboardFocused
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.posterRowContext) private var row
    @Environment(\.scenePhase) private var scenePhase
    @State private var instanceID = UUID()
    @State private var artSize: CGSize = .zero
    @State private var expansionBase: CGSize?
    @State private var expanded = false
    @State private var wideURL: String?
    @State private var wideResolvedKey = ""
    @State private var wideReady = false
    @State private var wideRevision = 0
    @State private var loaded = false
    @State private var logoLoaded = false
    @State private var resolvedArtwork: ResolvedCardArtwork?
    @State private var resolvedKey = ""
    @State private var localizedPoster: String?
    @State private var posterResolvedKey = ""
    private var overrides: TitleArtworkPreferences { .shared }
    private var participates: Bool { showsTitle || showsRating }
    private var attention: PosterAttentionState { .shared }
    private var selected: Bool { participates && focusEnabled && attention.input == .keyboard && attention.active == instanceID }
    private var dimmed: Bool { participates && focusEnabled && attention.input == .keyboard && attention.active != nil && attention.active != instanceID }
    private var allowsExpansion: Bool { participates && honorsRowStyle && expansionEnabled && configuration.style == .poster && (row?.viewport.width ?? 0) > 0 }
    private var expandedWidth: CGFloat? {
        guard expanded, let base = expansionBase else { return nil }
        return CGFloat(PosterBehaviorPolicy.expandedWidth(posterHeight: Double(base.height)))
    }
    private var dock: PosterDockTransform {
        guard participates, dockEnabled, configuration.style == .poster, !reduceMotion, !expanded else { return .init() }
        return row?.dock(instanceID, rtl: layoutDirection == .rightToLeft) ?? .init()
    }
    private var dockAnchor: UnitPoint { UnitPoint(x: dock.origin == .left ? 0 : dock.origin == .right ? 1 : 0.5, y: 1) }
    private var wideMedia: Media {
        var result = resolutionMedia; result.poster = overrides.value(.poster, id: media.artworkID) ?? media.poster; return result
    }
    private var wideTaskKey: String {
        guard allowsExpansion else { return "off" }
        return "\(AppProfileContext.shared.activationID)|\(wideRevision)|" + ExpandingCardArtwork.key(wideMedia, MetadataPreferences.shared.configuration())
    }
    private var widePixels: Int {
        if quality == "max" { return 0 }
        let target: Double = PosterBehaviorPolicy.expandedWidth(posterHeight: Double(expansionBase?.height ?? artSize.height)) * Double(displayScale) * (quality == "balanced" ? 0.75 : 1)
        return Int(min(2_048, max(240, target.rounded(.up))))
    }
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
    private var layoutCard: some View {
        Group {
            if let width {
                card.containerRelativeFrame(.horizontal, alignment: .leading) { available, _ in
                    expandedWidth ?? min(max(1, available - 32), CGFloat(configuration.rowWidth(base: Double(width))))
                }
            } else { card.frame(width: expandedWidth) }
        }.foregroundStyle(HarborTheme.ink).contentShape(Rectangle())
            .id(instanceID)
            .background {
                if participates, let row, (dockEnabled || allowsExpansion), configuration.style == .poster {
                    GeometryReader { geometry in Color.clear.preference(key: PosterRowFrames.self, value: [instanceID: geometry.frame(in: .named(row.id))]) }
                }
            }
    }
    private var styledCard: some View {
        layoutCard.opacity(dimmed ? 0.34 : 1).colorMultiply(dimmed ? Color(white: 0.68) : .white)
            .saturation(dimmed ? 0.78 : 1).blur(radius: dimmed ? 0.7 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: dimmed)
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.48), value: expanded)
            .zIndex(selected ? 100 : dock.zIndex)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: configuration.scale)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: configuration.radius)
    }
    private var lifecycleCard: some View {
        styledCard.onChange(of: logoURL) { _, _ in logoLoaded = false }
            .onChange(of: keyboardFocused) { _, _ in syncFocus(); syncExpansion() }
            .onKeyPress(phases: .down) { _ in
                if attention.input != .keyboard { attention.input = .keyboard }; return .ignored
            }
            .onChange(of: focusEnabled) { _, _ in syncFocus() }
            .onChange(of: expandedWidth) { _, value in onExpansionWidthChange?(value) }
            .onChange(of: configuration.scale) { _, _ in expanded = false; expansionBase = nil }
            .onChange(of: attention.input) { _, _ in syncFocus(); syncExpansion() }
            .onChange(of: allowsExpansion) { _, enabled in if !enabled { expanded = false; expansionBase = nil }; syncExpansion() }
            .onChange(of: AppProfileContext.shared.activationID) { _, _ in
                attention.focus(instanceID, enabled: false, focused: false); expanded = false; expansionBase = nil
            }
            .onHover { if $0 && participates { attention.pointerMoved() } }
            .onAppear { syncFocus() }
            .onDisappear {
                attention.focus(instanceID, enabled: false, focused: false)
                row?.cancelReveal(instanceID)
                expanded = false; expansionBase = nil; wideReady = false; wideURL = nil; wideResolvedKey = ""
                onExpansionWidthChange?(nil)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { syncFocus(); syncExpansion() }
                else { attention.focus(instanceID, enabled: false, focused: false); row?.cancelReveal(instanceID); expanded = false }
            }
    }
    var body: some View {
        lifecycleCard.task(id: wideTaskKey) {
                let key = wideTaskKey
                wideReady = false; wideURL = nil; expanded = false
                guard allowsExpansion else { return }
                let value = await ExpandingCardArtwork.shared.prepare(wideMedia, configuration: MetadataPreferences.shared.configuration())
                guard !Task.isCancelled, key == wideTaskKey else { return }
                wideResolvedKey = key; wideURL = value
            }
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
                    ZStack {
                        CustomListArtwork(media: media, url: posterURL, fallback: posterFallback, fallbacks: posterFallbacks,
                            maxPixels: pixelLimit, onImageAvailability: { loaded = $0 }, onLoadCompletion: { _ in loaded = true })
                        if let wideURL, wideResolvedKey == wideTaskKey {
                            Artwork(url: wideURL, maxPixels: widePixels, showsPlaceholder: false, onImageAvailability: { ready in
                                wideReady = ready; if ready { loaded = true }; syncExpansion()
                            }, onLoadCompletion: { if !$0 { rejectWideArtwork(wideURL) } })
                                .opacity(expanded ? 1 : 0).scaleEffect(expanded ? 1 : 1.025)
                                .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.48), value: expanded)
                        }
                    }
                }
            }.aspectRatio(expanded ? 16.0 / 9 : configuration.aspectRatio, contentMode: .fit)
                .frame(height: expanded ? expansionBase?.height : nil)
                .background {
                    if allowsExpansion {
                        GeometryReader { geometry in
                            Color.clear.onAppear { if !expanded { artSize = geometry.size; syncExpansion() } }
                                .onChange(of: geometry.size) { _, size in if !expanded { artSize = size; syncExpansion() } }
                        }
                    }
                }
                .background(HarborTheme.surface).clipShape(.rect(cornerRadius: configuration.radius)).accessibilityHidden(true)
                .blur(radius: !reduceMotion && configuration.effect == .blur && !loaded ? 8 : 0)
                .opacity(configuration.effect == .off || reduceMotion || loaded ? 1 : 0)
                .animation(reduceMotion || configuration.effect == .off ? nil : .easeOut(duration: 0.35), value: loaded)
                .overlay(alignment: .bottomTrailing) { if showsRating && configuration.style == .poster { rating } }
                .overlay { if selected { RoundedRectangle(cornerRadius: configuration.radius).stroke(HarborTheme.accent, lineWidth: 2) } }
                .shadow(color: .black.opacity(selected ? 0.65 : 0), radius: selected ? 24 : 0, x: 0, y: selected ? 12 : 0)
                .scaleEffect(dock.scale, anchor: dockAnchor).offset(x: dock.x, y: dock.y)
                .animation(reduceMotion ? nil : .timingCurve(0.22, 0.61, 0.36, 1, duration: PosterBehaviorPolicy.transitionMilliseconds(dockMilliseconds) / 1_000), value: dock)
            if showsTitle && configuration.style == .poster { Text(media.name).font(.caption.weight(.medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func syncFocus() { attention.focus(instanceID, enabled: participates && focusEnabled, focused: keyboardFocused) }
    private func syncExpansion() {
        let next = allowsExpansion && keyboardFocused && attention.input == .keyboard && wideReady && wideResolvedKey == wideTaskKey
        if next, expansionBase == nil, artSize.width > 0, artSize.height > 0 { expansionBase = artSize }
        let ready = next && expansionBase != nil
        if expanded != ready {
            expanded = ready
            if ready { row?.requestReveal(instanceID) } else { row?.cancelReveal(instanceID) }
        }
    }
    private func rejectWideArtwork(_ url: String) {
        let key = wideTaskKey, media = wideMedia, configuration = MetadataPreferences.shared.configuration()
        wideReady = false; expanded = false
        Task {
            await ExpandingCardArtwork.shared.invalidate(key: ExpandingCardArtwork.key(media, configuration), url: url)
            guard key == wideTaskKey, wideURL == url else { return }
            wideURL = nil; if wideRevision < 8 { wideRevision += 1 }
        }
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
            CustomListArtwork(media: media, url: posterURL, fallback: posterFallback, fallbacks: posterFallbacks, maxPixels: pixelLimit,
                onImageAvailability: { if $0 { loaded = true } }, onLoadCompletion: { _ in loaded = true })
                .scaleEffect(1.1).blur(radius: 18).saturation(1.2)
            if let backdrop = backgroundURL {
                Artwork(url: backdrop, maxPixels: pixelLimit, showsPlaceholder: false, onImageAvailability: { if $0 { loaded = true } })
            }
            LinearGradient(stops: configuration.logoPosition == .center
                ? [.init(color: HarborTheme.background.opacity(0.8), location: 0), .init(color: HarborTheme.background.opacity(0.45), location: 0.5), .init(color: HarborTheme.background.opacity(0.7), location: 1)]
                : [.init(color: HarborTheme.background, location: 0.02), .init(color: HarborTheme.background.opacity(0.65), location: 0.34), .init(color: HarborTheme.background.opacity(0.18), location: 0.62), .init(color: .clear, location: 0.84)], startPoint: .bottom, endPoint: .top)
            HStack(alignment: configuration.logoPosition == .center ? .center : .bottom, spacing: 10) {
                CustomListArtwork(media: media, url: posterURL, fallback: posterFallback, fallbacks: posterFallbacks, maxPixels: 180)
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
