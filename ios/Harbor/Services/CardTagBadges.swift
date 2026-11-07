import Foundation

/// Where a poster's watchlist bookmark sits (Desktop's `watchlistBadge` in `defaults.ts`, `WATCHLIST_POS` in `components/pick-card.tsx`).
enum CardWatchlistPosition: String, CaseIterable, Sendable {
    case off, topStart, topEnd, bottomStart, bottomEnd

    /// Desktop's default is `topEnd`; an unknown or missing stored value reads as that default.
    static func restored(_ raw: String?) -> CardWatchlistPosition {
        raw.flatMap { CardWatchlistPosition(rawValue: $0) } ?? .topEnd
    }
}

/// The text tags a poster can carry (Desktop's `DUB` literal and `New` badge in `components/pick-card.tsx`).
/// The order is Desktop's stacking order in the top-start column: DUB first, New under it.
enum CardTag: String, CaseIterable, Sendable {
    case dub, new

    /// The English source string; the view passes it through `DesktopInterfaceText.value`.
    var title: String { self == .dub ? "DUB" : "New" }
}

/// Where the bookmark is drawn: which corner, and the top inset in points that Desktop's `circleTop` gives it.
struct CardBookmarkPlacement: Equatable, Sendable {
    let isTop: Bool
    let isStart: Bool
    let topInset: Double
}

/// The pure rules for the non-score badges on a poster: which tags show, their order, the bookmark corner, and the anime
/// detail score. Score chips are in `CardRatingPolicy` (`Services/CardRatings.swift`).
enum CardTagPolicy {
    /// Desktop shows the New and DUB tags only, never more than one of each, so a card carries at most two.
    static let maximumTags = 2

    /// Desktop's `isAnimeCardId` in `components/pick-card.tsx`.
    static func isAnimeCardID(_ id: String) -> Bool {
        id.range(of: "^(kitsu|mal|anilist|anidb|simkl):", options: .regularExpression) != nil
    }

    /// The tags for one card, in order. DUB needs the setting, an anime id and a match in the dub feed; it is not gated by
    /// "Show tags on cards" (Desktop checks `showDubBadge` outside the `showCardBadges` block). New needs the tag setting and
    /// a release year equal to the current year, written exactly as Desktop compares it (`deriveBadge`).
    static func tags(id: String, releaseInfo: String?, year: Int, showsCardTags: Bool, showsDub: Bool, hasDub: Bool) -> [CardTag] {
        var result: [CardTag] = []
        if showsDub && isAnimeCardID(id) && hasDub { result.append(.dub) }
        if showsCardTags && isNew(releaseInfo: releaseInfo, year: year) { result.append(.new) }
        return Array(result.prefix(maximumTags))
    }

    /// Desktop's `deriveBadge`: the release year string must equal the current year exactly.
    static func isNew(releaseInfo: String?, year: Int) -> Bool {
        releaseInfo == String(year)
    }

    /// The bookmark shows on a saved title when the setting places it somewhere.
    static func showsBookmark(_ position: CardWatchlistPosition, bookmarked: Bool) -> Bool {
        bookmarked && position != .off
    }

    /// Desktop's `WATCHLIST_POS`. A top-start bookmark is pushed down past the tags it shares a column with, as Desktop's
    /// `circleTop` does when the Top 10 ribbon is on; the other corners keep the fixed inset.
    static func bookmarkPlacement(_ position: CardWatchlistPosition, tagCount: Int) -> CardBookmarkPlacement? {
        switch position {
        case .off: return nil
        case .topStart: return CardBookmarkPlacement(isTop: true, isStart: true, topInset: circleTop(tagCount))
        case .topEnd: return CardBookmarkPlacement(isTop: true, isStart: false, topInset: 6)
        case .bottomStart: return CardBookmarkPlacement(isTop: false, isStart: true, topInset: 0)
        case .bottomEnd: return CardBookmarkPlacement(isTop: false, isStart: false, topInset: 0)
        }
    }

    /// Desktop's `circleTop`: the top inset in points for the bookmark after `slots` tags above it.
    static func circleTop(_ slots: Int) -> Double {
        if slots <= 0 { return 6 }
        if slots == 1 { return 34 }
        if slots == 2 { return 62 }
        if slots == 3 { return 90 }
        return 118
    }

    /// Desktop's `hero-ratings.tsx`: an anime title's primary rating is MyAnimeList's catalog score, shown unless the
    /// ratings matrix hides "mal" (`InterfacePreferences.detailRatingsHidden`). Desktop's `showMalDetail` maps to that set.
    static func malDetailItem(_ media: Media, detailHidden: Set<String>) -> DetailRatings.Item? {
        guard !detailHidden.contains("mal"), isAnimeCardID(media.id),
              let score = CardRatingPolicy.text(.mal, anime: true, inlineRating: media.imdbRating, inlineSource: media.ratingSource,
                                                scores: CardRatingScores()) else { return nil }
        return DetailRatings.Item(id: "mal", label: "MyAnimeList", value: score, link: nil)
    }
}

/// The AniSchedule dub feed as a lookup by MyAnimeList and AniList id (Desktop's `byMal` and `byAnilist` in
/// `lib/providers/anime-dub-sub.ts`). Built once per feed reply, not per card.
struct AnimeDubIndex: Equatable, Sendable {
    private let malIDs: Set<Int>
    private let anilistIDs: Set<Int>

    init(rows: [JSONValue]) {
        var mal = Set<Int>()
        var anilist = Set<Int>()
        for row in rows {
            let media = row["media"]["media"]
            if let id = Self.wholeID(media["idMal"]) { mal.insert(id) }
            if let id = Self.wholeID(media["id"]) { anilist.insert(id) }
        }
        malIDs = mal
        anilistIDs = anilist
    }

    /// True for `mal:N` and `anilist:N` ids with a dub listed. Other id kinds never have a dub here (Desktop's `animeHasDub`).
    func hasDub(_ metaID: String) -> Bool {
        if let id = Self.numberAfter("mal:", in: metaID) { return malIDs.contains(id) }
        if let id = Self.numberAfter("anilist:", in: metaID) { return anilistIDs.contains(id) }
        return false
    }

    private static func numberAfter(_ prefix: String, in metaID: String) -> Int? {
        guard metaID.hasPrefix(prefix) else { return nil }
        return Int(metaID.dropFirst(prefix.count))
    }

    private static func wholeID(_ value: JSONValue) -> Int? {
        guard let number = value.numericValue, number.isFinite, number >= 0, number == number.rounded(.towardZero) else { return nil }
        return Int(exactly: number)
    }
}
