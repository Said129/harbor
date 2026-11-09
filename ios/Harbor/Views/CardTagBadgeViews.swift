import SwiftUI

/// Desktop's non-score poster badges (`components/pick-card.tsx`): the watchlist bookmark, the DUB tag on anime, and the New tag.
/// Which badges show, and where, come from `CardTagPolicy`; this view draws them and loads the dub feed once.
struct CardTagBadges: View {
    let media: Media
    var showsTopTenRibbon = true
    @Environment(\.customListApp) private var app

    init(media: Media, showsTopTenRibbon: Bool = true) {
        self.media = media
        self.showsTopTenRibbon = showsTopTenRibbon
    }

    private var preferences: InterfacePreferences { InterfacePreferences.shared }
    private var dubIndex: AnimeDubIndex? { AnimeDubIndexStore.shared.index }
    private var bookmarked: Bool { app?.library.bookmarked(media) ?? false }
    private var position: CardWatchlistPosition { CardWatchlistPosition.restored(preferences.watchlistBadge) }
    private var ribbonSide: String? {
        guard showsTopTenRibbon, preferences.top10Ribbon,
              TopTenRibbonIndexStore.shared.contains(media, profileActivationID: AppProfileContext.shared.activationID) else { return nil }
        return preferences.top10RibbonSide
    }
    private var ribbonAtStart: Bool { ribbonSide == "left" }
    private var ribbonAtEnd: Bool { ribbonSide == "right" }
    private var needsDubFeed: Bool { preferences.showDubBadge && CardTagPolicy.isAnimeCardID(media.id) }
    private var tags: [CardTag] {
        CardTagPolicy.tags(id: media.id, releaseInfo: media.releaseInfo, year: Calendar.current.component(.year, from: Date()),
                           showsCardTags: preferences.showCardBadges, showsDub: preferences.showDubBadge,
                           hasDub: dubIndex?.hasDub(media.id) ?? false)
    }

    /// Nothing is drawn for a card with no badge, and the overlay never takes touches from the poster.
    var body: some View {
        ZStack {
            Color.clear
            tagColumn
            bookmarkMark
        }
        .allowsHitTesting(false)
        .task(id: needsDubFeed) { if needsDubFeed { await AnimeDubIndexStore.shared.ensureLoaded() } }
    }

    @ViewBuilder private var tagColumn: some View {
        if !tags.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(tags, id: \.self) { CardTagLabel(tag: $0) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 8).padding(.top, ribbonAtStart ? 34 : 8)
        }
    }

    @ViewBuilder private var bookmarkMark: some View {
        if CardTagPolicy.showsBookmark(position, bookmarked: bookmarked),
           let placement = CardTagPolicy.bookmarkPlacement(position, tagCount: tags.count,
                                                           ribbonAtStart: ribbonAtStart, ribbonAtEnd: ribbonAtEnd) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(HarborTheme.ink)
                .frame(width: 24, height: 24)
                .background(HarborTheme.background.opacity(0.95), in: .circle)
                .accessibilityLabel(DesktopInterfaceText.value("In watchlist"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bookmarkAlignment(placement))
                .padding(.top, CGFloat(placement.topInset)).padding(.horizontal, 6)
                .padding(.bottom, placement.isTop ? 0 : 6)
        }
    }

    private func bookmarkAlignment(_ placement: CardBookmarkPlacement) -> Alignment {
        if placement.isTop { return placement.isStart ? .topLeading : .topTrailing }
        return placement.isStart ? .bottomLeading : .bottomTrailing
    }
}

/// The ribbon is a shared poster mark. Top-ten ranked cards hide it because their large numeral already shows the rank.
struct CardTopTenRibbon: View {
    let media: Media
    @Bindable private var preferences = InterfacePreferences.shared

    private var shouldShow: Bool {
        preferences.top10Ribbon
            && TopTenRibbonIndexStore.shared.contains(media, profileActivationID: AppProfileContext.shared.activationID)
    }

    var body: some View {
        Group {
            if shouldShow { TopTenCornerRibbon(side: preferences.top10RibbonSide) }
        }
    }
}

/// One tag: a small capsule with Desktop's label. DUB is the accent colour; New is white, as Desktop's neutral badge.
private struct CardTagLabel: View {
    let tag: CardTag

    var body: some View {
        Text(DesktopInterfaceText.value(tag.title))
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(HarborTheme.background)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(fill, in: .rect(cornerRadius: 6))
    }

    private var fill: Color { tag == .dub ? HarborTheme.accent : Color.white }
}

/// The DUB feed for the anime cards on screen, read once: the first card that needs it starts the request and later
/// cards reuse the index. A failed reply leaves the index empty so the next card asks again, as Desktop does.
@MainActor @Observable
final class AnimeDubIndexStore {
    static let shared = AnimeDubIndexStore()
    private(set) var index: AnimeDubIndex?
    @ObservationIgnored private var inflight: Task<Void, Never>?

    func ensureLoaded() async {
        if index != nil { return }
        if inflight == nil { inflight = Task { await self.load() } }
        await inflight?.value
    }

    private func load() async {
        let rows = await AnimeDubFeed.shared.entries(now: Date()) { url in
            try? await HTTPClient().json(url.absoluteString, timeout: 15)
        }
        inflight = nil
        if !rows.isEmpty { index = AnimeDubIndex(rows: rows) }
    }
}
