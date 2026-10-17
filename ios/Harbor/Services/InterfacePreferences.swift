import Foundation
import Observation

@MainActor @Observable
final class InterfacePreferences {
    static let shared = InterfacePreferences()
    private let storage = UserDefaults.standard
    let navigation = ScopedNavigationPreferences()
    var navIconAnimations = UserDefaults.standard.object(forKey: "navIconAnimations") as? Bool ?? true { didSet { storage.set(navIconAnimations, forKey: "navIconAnimations") } }
    var autoRotateBanners = UserDefaults.standard.object(forKey: "interface.autoRotateBanners") as? Bool ?? true { didSet { storage.set(autoRotateBanners, forKey: "interface.autoRotateBanners") } }
    var homeMode = UserDefaults.standard.string(forKey: "homeMode") ?? "harbor" { didSet { storage.set(homeMode, forKey: "homeMode") } }
    var showImdbBadge = UserDefaults.standard.object(forKey: "showImdbBadge") as? Bool ?? true { didSet { storage.set(showImdbBadge, forKey: "showImdbBadge") } }
    var showTmdbBadge = UserDefaults.standard.object(forKey: "showTmdbBadge") as? Bool ?? false { didSet { storage.set(showTmdbBadge, forKey: "showTmdbBadge") } }
    var showWatchedButton = UserDefaults.standard.object(forKey: "showWatchedButton") as? Bool ?? true { didSet { storage.set(showWatchedButton, forKey: "showWatchedButton") } }
    var showEpisodeDescription = UserDefaults.standard.object(forKey: "showEpisodeDescription") as? Bool ?? true { didSet { storage.set(showEpisodeDescription, forKey: "showEpisodeDescription") } }
    var hideSpoilers = UserDefaults.standard.object(forKey: "hideSpoilers") as? Bool ?? false { didSet { storage.set(hideSpoilers, forKey: "hideSpoilers") } }
    var blurEpisodes = UserDefaults.standard.object(forKey: "blurEpisodes") as? Bool ?? false { didSet { storage.set(blurEpisodes, forKey: "blurEpisodes") } }
    var spoilerHideTitles = UserDefaults.standard.object(forKey: "spoilerHideTitles") as? Bool ?? true { didSet { storage.set(spoilerHideTitles, forKey: "spoilerHideTitles") } }
    var spoilerHideDescriptions = UserDefaults.standard.object(forKey: "spoilerHideDescriptions") as? Bool ?? true { didSet { storage.set(spoilerHideDescriptions, forKey: "spoilerHideDescriptions") } }
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
}
