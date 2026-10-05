import Foundation
import Observation

@MainActor @Observable
final class InterfacePreferences {
    static let shared = InterfacePreferences()
    private let storage = UserDefaults.standard
    var homeMode = UserDefaults.standard.string(forKey: "homeMode") ?? "harbor" { didSet { storage.set(homeMode, forKey: "homeMode") } }
    var showImdbBadge = UserDefaults.standard.object(forKey: "showImdbBadge") as? Bool ?? true { didSet { storage.set(showImdbBadge, forKey: "showImdbBadge") } }
    var showTmdbBadge = UserDefaults.standard.object(forKey: "showTmdbBadge") as? Bool ?? false { didSet { storage.set(showTmdbBadge, forKey: "showTmdbBadge") } }
    var showWatchedButton = UserDefaults.standard.object(forKey: "showWatchedButton") as? Bool ?? true { didSet { storage.set(showWatchedButton, forKey: "showWatchedButton") } }
    var showEpisodeDescription = UserDefaults.standard.object(forKey: "showEpisodeDescription") as? Bool ?? true { didSet { storage.set(showEpisodeDescription, forKey: "showEpisodeDescription") } }
    var hideSpoilers = UserDefaults.standard.object(forKey: "hideSpoilers") as? Bool ?? false { didSet { storage.set(hideSpoilers, forKey: "hideSpoilers") } }
    var blurEpisodes = UserDefaults.standard.object(forKey: "blurEpisodes") as? Bool ?? false { didSet { storage.set(blurEpisodes, forKey: "blurEpisodes") } }
    var navigationOrder = UserDefaults.standard.stringArray(forKey: "iphone.nav.order") ?? [] { didSet { storage.set(navigationOrder, forKey: "iphone.nav.order") } }
    var navigationHidden = Set(UserDefaults.standard.stringArray(forKey: "iphone.nav.hidden") ?? []) { didSet { storage.set(Array(navigationHidden), forKey: "iphone.nav.hidden") } }
    var navigationNames = UserDefaults.standard.dictionary(forKey: "iphone.nav.names") as? [String: String] ?? [:] { didSet { storage.set(navigationNames, forKey: "iphone.nav.names") } }
    var orderedSections: [HarborSection] {
        var seen = Set<HarborSection>()
        return (navigationOrder.compactMap(HarborSection.init(rawValue:)) + HarborSection.allCases).filter { seen.insert($0).inserted }
    }
    var visibleSections: [HarborSection] { orderedSections.filter { !navigationHidden.contains($0.rawValue) || $0 == .settings || $0 == .home } }
    func label(_ section: HarborSection) -> String { navigationNames[section.rawValue].flatMap { $0.isEmpty ? nil : $0 } ?? section.title }
    func resetNavigation() { navigationOrder = []; navigationHidden = []; navigationNames = [:] }
}
