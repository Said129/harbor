import Foundation
import Observation

/// Desktop's `isTop10` set, scoped to the current profile activation. Home replaces it with the first ten titles from its
/// first visible row after excluding the featured slides; ranked rows on other pages do not seed membership.
@MainActor @Observable
final class TopTenRibbonIndexStore {
    static let shared = TopTenRibbonIndexStore()

    private(set) var ids: Set<String> = []
    private(set) var normalizedNames: Set<String> = []
    private var profileActivationID: UUID?

    func replaceHomeTopTen(_ metas: [Media], profileActivationID: UUID) {
        if self.profileActivationID != profileActivationID {
            self.profileActivationID = profileActivationID
            ids.removeAll()
            normalizedNames.removeAll()
        }

        var nextIDs = Set<String>()
        var nextNames = Set<String>()
        for media in metas.prefix(10) {
            guard !media.id.isEmpty else { continue }
            nextIDs.insert(media.id)
            let name = Self.normalize(media.name)
            if !name.isEmpty { nextNames.insert(name) }
        }
        if ids != nextIDs { ids = nextIDs }
        if normalizedNames != nextNames { normalizedNames = nextNames }
    }

    func contains(_ media: Media, profileActivationID: UUID) -> Bool {
        guard self.profileActivationID == profileActivationID else { return false }
        return ids.contains(media.id) || normalizedNames.contains(Self.normalize(media.name))
    }

    /// Matches Desktop's `top10-set.ts`: lowercase, then keep ASCII letters and digits only.
    private static func normalize(_ value: String) -> String {
        String(value.lowercased().unicodeScalars.filter { scalar in
            (48...57).contains(scalar.value) || (97...122).contains(scalar.value)
        })
    }
}
