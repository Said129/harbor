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
    var showWatchedButton = UserDefaults.standard.object(forKey: "showWatchedButton") as? Bool ?? true { didSet { persist(showWatchedButton, forKey: "showWatchedButton") } }
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
    var hideSpoilers = UserDefaults.standard.object(forKey: "hideSpoilers") as? Bool ?? false { didSet { persist(hideSpoilers, forKey: "hideSpoilers") } }
    var blurEpisodes = UserDefaults.standard.object(forKey: "blurEpisodes") as? Bool ?? false { didSet { persist(blurEpisodes, forKey: "blurEpisodes") } }
    var spoilerHideTitles = UserDefaults.standard.object(forKey: "spoilerHideTitles") as? Bool ?? true { didSet { persist(spoilerHideTitles, forKey: "spoilerHideTitles") } }
    var spoilerHideDescriptions = UserDefaults.standard.object(forKey: "spoilerHideDescriptions") as? Bool ?? true { didSet { persist(spoilerHideDescriptions, forKey: "spoilerHideDescriptions") } }
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
        showWatchedButton = UserDefaults.standard.object(forKey: "showWatchedButton") as? Bool ?? true
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
        episodeSort = UserDefaults.standard.string(forKey: "episodeSort") == "newest" ? "newest" : "oldest"
        episodeHiding = UserDefaults.standard.object(forKey: "episodeHiding") as? Bool ?? false
        episodeLayout = UserDefaults.standard.string(forKey: "episodeLayout") ?? "list"
        episodeCardScale = UserDefaults.standard.object(forKey: "episodeCardScale") as? Double ?? 1
        episodeArcGroups = UserDefaults.standard.object(forKey: "episodeArcGroups") as? Bool ?? false
        showTraktComments = UserDefaults.standard.object(forKey: "showTraktComments") as? Bool ?? false
        blurComments = UserDefaults.standard.object(forKey: "blurComments") as? Bool ?? false
        detailRatingsHidden = Set(UserDefaults.standard.stringArray(forKey: "ratings.detailHidden") ?? [])
        hideSpoilers = UserDefaults.standard.object(forKey: "hideSpoilers") as? Bool ?? false
        blurEpisodes = UserDefaults.standard.object(forKey: "blurEpisodes") as? Bool ?? false
        spoilerHideTitles = UserDefaults.standard.object(forKey: "spoilerHideTitles") as? Bool ?? true
        spoilerHideDescriptions = UserDefaults.standard.object(forKey: "spoilerHideDescriptions") as? Bool ?? true
    }
}
