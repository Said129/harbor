import Foundation
import Observation

@MainActor @Observable
final class InterfacePreferences {
    static let shared = InterfacePreferences()
    let navigation = ScopedNavigationPreferences()
    var navIconAnimations = UserDefaults.standard.object(forKey: "navIconAnimations") as? Bool ?? true { didSet { persist(navIconAnimations, forKey: "navIconAnimations") } }
    var autoRotateBanners = UserDefaults.standard.object(forKey: "interface.autoRotateBanners") as? Bool ?? true { didSet { persist(autoRotateBanners, forKey: "interface.autoRotateBanners") } }
    var homeMode = UserDefaults.standard.string(forKey: "homeMode") ?? "harbor" { didSet { persist(homeMode, forKey: "homeMode") } }
    var showImdbBadge = UserDefaults.standard.object(forKey: "showImdbBadge") as? Bool ?? true { didSet { persist(showImdbBadge, forKey: "showImdbBadge") } }
    var showTmdbBadge = UserDefaults.standard.object(forKey: "showTmdbBadge") as? Bool ?? false { didSet { persist(showTmdbBadge, forKey: "showTmdbBadge") } }
    /// Desktop's card score chips (`defaults.ts`): RT, MAL and SIMKL on by default; the MDBList and audience chips off.
    var showRtBadge = UserDefaults.standard.object(forKey: "showRtBadge") as? Bool ?? true { didSet { persist(showRtBadge, forKey: "showRtBadge") } }
    var showMalBadge = UserDefaults.standard.object(forKey: "showMalBadge") as? Bool ?? true { didSet { persist(showMalBadge, forKey: "showMalBadge") } }
    var showSimklBadge = UserDefaults.standard.object(forKey: "showSimklBadge") as? Bool ?? true { didSet { persist(showSimklBadge, forKey: "showSimklBadge") } }
    /// Desktop's `simklShowCommunityRatings` (default on): the SIMKL community score on cards and on detail pages.
    var simklShowCommunityRatings = UserDefaults.standard.object(forKey: "simklShowCommunityRatings") as? Bool ?? true { didSet { persist(simklShowCommunityRatings, forKey: "simklShowCommunityRatings") } }
    var showPopcornBadge = UserDefaults.standard.object(forKey: "showPopcornBadge") as? Bool ?? false { didSet { persist(showPopcornBadge, forKey: "showPopcornBadge") } }
    var showMetacriticBadge = UserDefaults.standard.object(forKey: "showMetacriticBadge") as? Bool ?? false { didSet { persist(showMetacriticBadge, forKey: "showMetacriticBadge") } }
    var showLetterboxdBadge = UserDefaults.standard.object(forKey: "showLetterboxdBadge") as? Bool ?? false { didSet { persist(showLetterboxdBadge, forKey: "showLetterboxdBadge") } }
    var showMdblistBadge = UserDefaults.standard.object(forKey: "showMdblistBadge") as? Bool ?? false { didSet { persist(showMdblistBadge, forKey: "showMdblistBadge") } }
    var showTraktBadge = UserDefaults.standard.object(forKey: "showTraktBadge") as? Bool ?? false { didSet { persist(showTraktBadge, forKey: "showTraktBadge") } }
    /// Desktop's `cardBadgeLimit` (default 3) and `badgePlacement` ("top" or "bottom", default "bottom").
    var cardBadgeLimit = UserDefaults.standard.object(forKey: "cardBadgeLimit") as? Int ?? 3 { didSet { persist(cardBadgeLimit, forKey: "cardBadgeLimit") } }
    var badgePlacement = UserDefaults.standard.string(forKey: "badgePlacement") == "top" ? "top" : "bottom" { didSet { persist(badgePlacement, forKey: "badgePlacement") } }
    /// Desktop's `watchlistBadge` ("off", "topStart", "topEnd", "bottomStart" or "bottomEnd"; default "topEnd"): the bookmark on saved posters.
    var watchlistBadge = CardWatchlistPosition.restored(UserDefaults.standard.string(forKey: "watchlistBadge")).rawValue { didSet { persist(watchlistBadge, forKey: "watchlistBadge") } }
    /// Desktop's `showDubBadge` (default on): the DUB tag on anime cards with an English dub.
    var showDubBadge = UserDefaults.standard.object(forKey: "showDubBadge") as? Bool ?? true { didSet { persist(showDubBadge, forKey: "showDubBadge") } }
    /// Desktop's `showCardBadges` (default on, "Show tags on cards"): the New tag on cards.
    var showCardBadges = UserDefaults.standard.object(forKey: "showCardBadges") as? Bool ?? true { didSet { persist(showCardBadges, forKey: "showCardBadges") } }
    var showWatchedButton = UserDefaults.standard.object(forKey: "showWatchedButton") as? Bool ?? true { didSet { persist(showWatchedButton, forKey: "showWatchedButton") } }
    /// Desktop's `showWatchedBadge` (default on): the watched check on posters and episode rows.
    var showWatchedBadge = UserDefaults.standard.object(forKey: "showWatchedBadge") as? Bool ?? true { didSet { persist(showWatchedBadge, forKey: "showWatchedBadge") } }
    /// Desktop's `wrappedButton` (default true): the Stats entry in the library header.
    var wrappedButton = UserDefaults.standard.object(forKey: "wrappedButton") as? Bool ?? true { didSet { persist(wrappedButton, forKey: "wrappedButton") } }
    var showEpisodeDescription = UserDefaults.standard.object(forKey: "showEpisodeDescription") as? Bool ?? true { didSet { persist(showEpisodeDescription, forKey: "showEpisodeDescription") } }
    /// Desktop's `showEpisodeRating`: the IMDb rating on each episode's picture.
    var showEpisodeRating = UserDefaults.standard.object(forKey: "showEpisodeRating") as? Bool ?? true { didSet { persist(showEpisodeRating, forKey: "showEpisodeRating") } }
    var hideWatchedInCatalogs = UserDefaults.standard.object(forKey: "hideWatchedInCatalogs") as? Bool ?? false { didSet { persist(hideWatchedInCatalogs, forKey: "hideWatchedInCatalogs") } }
    var hideUnreleased = UserDefaults.standard.object(forKey: "hideUnreleased") as? Bool ?? false { didSet { persist(hideUnreleased, forKey: "hideUnreleased") } }
    /// Desktop's `homeShowAllAddonRows`: Home keeps addon rows that repeat a built-in row instead of merging them.
    var homeShowAllAddonRows = UserDefaults.standard.object(forKey: "homeShowAllAddonRows") as? Bool ?? false { didSet { persist(homeShowAllAddonRows, forKey: "homeShowAllAddonRows") } }
    /// Desktop's `catalogsPinned` and `catalogsHidden`: catalog keys pinned to the top of the Catalogs screen (in order) and catalogs hidden from it.
    var catalogsPinned = UserDefaults.standard.stringArray(forKey: "catalogsPinned") ?? [] { didSet { persist(catalogsPinned, forKey: "catalogsPinned") } }
    var catalogsHidden = UserDefaults.standard.stringArray(forKey: "catalogsHidden") ?? [] { didSet { persist(catalogsHidden, forKey: "catalogsHidden") } }
    /// Desktop's `homeLanguages`: Home rows keep titles whose original language is in this list. Empty shows every language.
    var homeLanguages = UserDefaults.standard.stringArray(forKey: "homeLanguages") ?? [] { didSet { persist(homeLanguages, forKey: "homeLanguages") } }
    /// Desktop's `animeOnlyInAnimeRoom`: Home's Continue Watching leaves out anime, which the Anime page still shows.
    var animeOnlyInAnimeRoom = UserDefaults.standard.object(forKey: "animeOnlyInAnimeRoom") as? Bool ?? true { didSet { persist(animeOnlyInAnimeRoom, forKey: "animeOnlyInAnimeRoom") } }
    /// Desktop's `libraryBookmarkedOnly`: the Watchlist lists only saved titles, not entries Stremio auto-added on play.
    var libraryBookmarkedOnly = UserDefaults.standard.object(forKey: "libraryBookmarkedOnly") as? Bool ?? true { didSet { persist(libraryBookmarkedOnly, forKey: "libraryBookmarkedOnly") } }
    /// Desktop's `cwAdvanceNext`: a finished episode moves its Continue Watching card to the next episode.
    var cwAdvanceNext = UserDefaults.standard.object(forKey: "cwAdvanceNext") as? Bool ?? true { didSet { persist(cwAdvanceNext, forKey: "cwAdvanceNext") } }
    /// Desktop's `cwHideCaughtUp` (default on): a series whose aired episodes are all watched leaves Continue Watching until a new one airs.
    var cwHideCaughtUp = UserDefaults.standard.object(forKey: "cwHideCaughtUp") as? Bool ?? true { didSet { persist(cwHideCaughtUp, forKey: "cwHideCaughtUp") } }
    /// Desktop's `cwPreferEpisodeStill` (default off): the episode still leads a Continue Watching card instead of the series artwork.
    var cwPreferEpisodeStill = UserDefaults.standard.object(forKey: "cwPreferEpisodeStill") as? Bool ?? false { didSet { persist(cwPreferEpisodeStill, forKey: "cwPreferEpisodeStill") } }
    /// Desktop's `animeCwEnd` (default "hide"): what a finished series shows while its next episode has not aired. "timer" shows a countdown.
    var animeCwEnd = UserDefaults.standard.string(forKey: "animeCwEnd") == "timer" ? "timer" : "hide" { didSet { persist(animeCwEnd, forKey: "animeCwEnd") } }
    var caughtUpEnd: ContinueWatchingEnd { ContinueWatchingEnd(rawValue: animeCwEnd) ?? .hide }
    /// Desktop's `homeNewEpisodes` (default off): a "New Episodes" row under Continue Watching for recently aired episodes.
    var homeNewEpisodes = UserDefaults.standard.object(forKey: "homeNewEpisodes") as? Bool ?? false { didSet { persist(homeNewEpisodes, forKey: "homeNewEpisodes") } }
    /// Desktop's `episodeSort`: "oldest" lists a season from its first episode, "newest" from its last.
    var episodeSort = UserDefaults.standard.string(forKey: "episodeSort") == "newest" ? "newest" : "oldest" { didSet { persist(episodeSort, forKey: "episodeSort") } }
    /// Desktop's `episodeHiding`: adds Hide episode to the episode menu and skips hidden episodes in Up Next.
    var episodeHiding = UserDefaults.standard.object(forKey: "episodeHiding") as? Bool ?? false { didSet { persist(episodeHiding, forKey: "episodeHiding") } }
    /// Desktop's `episodeLayout` ("list", "strip" or "grid"): how the episode list shows its episodes. Read through `EpisodeLayoutPolicy.layout`.
    var episodeLayout = UserDefaults.standard.string(forKey: "episodeLayout") ?? "list" { didSet { persist(episodeLayout, forKey: "episodeLayout") } }
    /// Desktop's `episodeCardScale` (default 1): the size of strip and grid episode cards.
    var episodeCardScale = UserDefaults.standard.object(forKey: "episodeCardScale") as? Double ?? 1 { didSet { persist(episodeCardScale, forKey: "episodeCardScale") } }
    /// Desktop's `episodeArcGroups` (default false): browse a show's TMDB story arcs in the episode list. Needs a TMDB key.
    var episodeArcGroups = UserDefaults.standard.object(forKey: "episodeArcGroups") as? Bool ?? false { didSet { persist(episodeArcGroups, forKey: "episodeArcGroups") } }
    /// Desktop's `showTraktComments`: a comments section on movie and show pages.
    var showTraktComments = UserDefaults.standard.object(forKey: "showTraktComments") as? Bool ?? false { didSet { persist(showTraktComments, forKey: "showTraktComments") } }
    /// Desktop's `blurComments`: comments stay blurred until revealed, spoiler or not.
    var blurComments = UserDefaults.standard.object(forKey: "blurComments") as? Bool ?? false { didSet { persist(blurComments, forKey: "blurComments") } }
    /// Ratings turned off in the detail column of Desktop's ratings matrix (`DetailRatings.sources` ids); empty shows them all.
    var detailRatingsHidden = Set(UserDefaults.standard.stringArray(forKey: "ratings.detailHidden") ?? []) { didSet { persist(detailRatingsHidden.sorted(), forKey: "ratings.detailHidden") } }
    /// Desktop's `showDetailRatings` (default on): the master switch for the ratings row on detail pages. The per-provider toggles stay in `detailRatingsHidden`.
    var showDetailRatings = UserDefaults.standard.object(forKey: "showDetailRatings") as? Bool ?? true { didSet { persist(showDetailRatings, forKey: "showDetailRatings") } }
    /// Desktop's `preferCustomMetaAddon` (default off): an installed metadata addon is asked before Cinemeta. Hook: `HarborService.addonMetadata`.
    var preferCustomMetaAddon = UserDefaults.standard.object(forKey: "preferCustomMetaAddon") as? Bool ?? false { didSet { persist(preferCustomMetaAddon, forKey: "preferCustomMetaAddon") } }
    var hideSpoilers = UserDefaults.standard.object(forKey: "hideSpoilers") as? Bool ?? false { didSet { persist(hideSpoilers, forKey: "hideSpoilers") } }
    var blurEpisodes = UserDefaults.standard.object(forKey: "blurEpisodes") as? Bool ?? false { didSet { persist(blurEpisodes, forKey: "blurEpisodes") } }
    var spoilerHideTitles = UserDefaults.standard.object(forKey: "spoilerHideTitles") as? Bool ?? true { didSet { persist(spoilerHideTitles, forKey: "spoilerHideTitles") } }
    var spoilerHideDescriptions = UserDefaults.standard.object(forKey: "spoilerHideDescriptions") as? Bool ?? true { didSet { persist(spoilerHideDescriptions, forKey: "spoilerHideDescriptions") } }
    /// Desktop's `spoilerSkipNext` (default on): the next episode to watch stays clear. Read by the episode rows through `UISettingsPolicy.spoilerMask` and by the Up Next card in `PlayerView`.
    var spoilerSkipNext = UserDefaults.standard.object(forKey: "spoilerSkipNext") as? Bool ?? true { didSet { persist(spoilerSkipNext, forKey: "spoilerSkipNext") } }
    /// Desktop's `playerTitleSeriesFirst` (default off): the series name leads the player title. Stored for the player title hook in `UISettingsPolicy.titleLines`; no view reads it yet.
    var playerTitleSeriesFirst = UserDefaults.standard.object(forKey: "playerTitleSeriesFirst") as? Bool ?? false { didSet { persist(playerTitleSeriesFirst, forKey: "playerTitleSeriesFirst") } }
    /// Desktop's `deleteWatchedDownloads` (default off): a download is removed once playback reaches 90 percent. Hook: `PlaybackProgressCommit.save` for download sessions; no view reads it yet.
    var deleteWatchedDownloads = UserDefaults.standard.object(forKey: "deleteWatchedDownloads") as? Bool ?? false { didSet { persist(deleteWatchedDownloads, forKey: "deleteWatchedDownloads") } }
    var navigationOrder: [String] { get { navigation.value.order } set { navigation.change { $0.order = newValue } } }
    var navigationHidden: Set<String> { get { navigation.value.hidden } set { navigation.change { $0.hidden = newValue } } }
    var navigationNames: [String: String] { get { navigation.value.renamed } set { navigation.change { $0.renamed = newValue } } }
    var defaultNavigationOrder: [String] {
        let native = Set(HarborSection.allCases.map(\.rawValue))
        let desktop = DesktopNavigationLayout.referenceOrder.filter { native.contains($0) }
        guard let addons = desktop.firstIndex(of: "addons") else { return desktop + ["search"] }
        var result = desktop; result.insert("search", at: addons); return result
    }
    var orderedSections: [HarborSection] {
        var seen = Set<HarborSection>()
        return ((navigationOrder + defaultNavigationOrder).compactMap(HarborSection.init(rawValue:)) + HarborSection.allCases).filter { seen.insert($0).inserted }
    }
    var visibleSections: [HarborSection] { orderedSections.filter { !navigationHidden.contains($0.rawValue) || $0 == .settings || $0 == .home } }
    func label(_ section: HarborSection) -> String { navigationNames[section.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? DesktopInterfaceText.value(section.title) }
    func resetNavigation() { navigation.change { $0 = NativeNavigationLayout() } }

    private var reloading = false
    private func persist(_ value: Any?, forKey key: String) {
        if !reloading { UserDefaults.standard.set(value, forKey: key) }
    }
    func reloadPreferences() {
        reloading = true; defer { reloading = false }
        navIconAnimations = UserDefaults.standard.object(forKey: "navIconAnimations") as? Bool ?? true
        autoRotateBanners = UserDefaults.standard.object(forKey: "interface.autoRotateBanners") as? Bool ?? true
        homeMode = UserDefaults.standard.string(forKey: "homeMode") ?? "harbor"
        showImdbBadge = UserDefaults.standard.object(forKey: "showImdbBadge") as? Bool ?? true
        showTmdbBadge = UserDefaults.standard.object(forKey: "showTmdbBadge") as? Bool ?? false
        showRtBadge = UserDefaults.standard.object(forKey: "showRtBadge") as? Bool ?? true
        showMalBadge = UserDefaults.standard.object(forKey: "showMalBadge") as? Bool ?? true
        showSimklBadge = UserDefaults.standard.object(forKey: "showSimklBadge") as? Bool ?? true
        simklShowCommunityRatings = UserDefaults.standard.object(forKey: "simklShowCommunityRatings") as? Bool ?? true
        showPopcornBadge = UserDefaults.standard.object(forKey: "showPopcornBadge") as? Bool ?? false
        showMetacriticBadge = UserDefaults.standard.object(forKey: "showMetacriticBadge") as? Bool ?? false
        showLetterboxdBadge = UserDefaults.standard.object(forKey: "showLetterboxdBadge") as? Bool ?? false
        showMdblistBadge = UserDefaults.standard.object(forKey: "showMdblistBadge") as? Bool ?? false
        showTraktBadge = UserDefaults.standard.object(forKey: "showTraktBadge") as? Bool ?? false
        cardBadgeLimit = UserDefaults.standard.object(forKey: "cardBadgeLimit") as? Int ?? 3
        badgePlacement = UserDefaults.standard.string(forKey: "badgePlacement") == "top" ? "top" : "bottom"
        watchlistBadge = CardWatchlistPosition.restored(UserDefaults.standard.string(forKey: "watchlistBadge")).rawValue
        showDubBadge = UserDefaults.standard.object(forKey: "showDubBadge") as? Bool ?? true
        showCardBadges = UserDefaults.standard.object(forKey: "showCardBadges") as? Bool ?? true
        showWatchedButton = UserDefaults.standard.object(forKey: "showWatchedButton") as? Bool ?? true
        showWatchedBadge = UserDefaults.standard.object(forKey: "showWatchedBadge") as? Bool ?? true
        wrappedButton = UserDefaults.standard.object(forKey: "wrappedButton") as? Bool ?? true
        showEpisodeDescription = UserDefaults.standard.object(forKey: "showEpisodeDescription") as? Bool ?? true
        showEpisodeRating = UserDefaults.standard.object(forKey: "showEpisodeRating") as? Bool ?? true
        hideWatchedInCatalogs = UserDefaults.standard.object(forKey: "hideWatchedInCatalogs") as? Bool ?? false
        hideUnreleased = UserDefaults.standard.object(forKey: "hideUnreleased") as? Bool ?? false
        homeShowAllAddonRows = UserDefaults.standard.object(forKey: "homeShowAllAddonRows") as? Bool ?? false
        catalogsPinned = UserDefaults.standard.stringArray(forKey: "catalogsPinned") ?? []
        catalogsHidden = UserDefaults.standard.stringArray(forKey: "catalogsHidden") ?? []
        homeLanguages = UserDefaults.standard.stringArray(forKey: "homeLanguages") ?? []
        animeOnlyInAnimeRoom = UserDefaults.standard.object(forKey: "animeOnlyInAnimeRoom") as? Bool ?? true
        libraryBookmarkedOnly = UserDefaults.standard.object(forKey: "libraryBookmarkedOnly") as? Bool ?? true
        cwAdvanceNext = UserDefaults.standard.object(forKey: "cwAdvanceNext") as? Bool ?? true
        cwHideCaughtUp = UserDefaults.standard.object(forKey: "cwHideCaughtUp") as? Bool ?? true
        cwPreferEpisodeStill = UserDefaults.standard.object(forKey: "cwPreferEpisodeStill") as? Bool ?? false
        animeCwEnd = UserDefaults.standard.string(forKey: "animeCwEnd") == "timer" ? "timer" : "hide"
        homeNewEpisodes = UserDefaults.standard.object(forKey: "homeNewEpisodes") as? Bool ?? false
        episodeSort = UserDefaults.standard.string(forKey: "episodeSort") == "newest" ? "newest" : "oldest"
        episodeHiding = UserDefaults.standard.object(forKey: "episodeHiding") as? Bool ?? false
        episodeLayout = UserDefaults.standard.string(forKey: "episodeLayout") ?? "list"
        episodeCardScale = UserDefaults.standard.object(forKey: "episodeCardScale") as? Double ?? 1
        episodeArcGroups = UserDefaults.standard.object(forKey: "episodeArcGroups") as? Bool ?? false
        showTraktComments = UserDefaults.standard.object(forKey: "showTraktComments") as? Bool ?? false
        blurComments = UserDefaults.standard.object(forKey: "blurComments") as? Bool ?? false
        detailRatingsHidden = Set(UserDefaults.standard.stringArray(forKey: "ratings.detailHidden") ?? [])
        showDetailRatings = UserDefaults.standard.object(forKey: "showDetailRatings") as? Bool ?? true
        preferCustomMetaAddon = UserDefaults.standard.object(forKey: "preferCustomMetaAddon") as? Bool ?? false
        hideSpoilers = UserDefaults.standard.object(forKey: "hideSpoilers") as? Bool ?? false
        blurEpisodes = UserDefaults.standard.object(forKey: "blurEpisodes") as? Bool ?? false
        spoilerHideTitles = UserDefaults.standard.object(forKey: "spoilerHideTitles") as? Bool ?? true
        spoilerHideDescriptions = UserDefaults.standard.object(forKey: "spoilerHideDescriptions") as? Bool ?? true
        spoilerSkipNext = UserDefaults.standard.object(forKey: "spoilerSkipNext") as? Bool ?? true
        playerTitleSeriesFirst = UserDefaults.standard.object(forKey: "playerTitleSeriesFirst") as? Bool ?? false
        deleteWatchedDownloads = UserDefaults.standard.object(forKey: "deleteWatchedDownloads") as? Bool ?? false
    }
}
