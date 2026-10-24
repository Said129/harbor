import Foundation

/// A secondary local profile never falls back to the household primary. The
/// migrated primary may resolve its old device ID to Desktop's primary sync ID.
struct DesktopLayoutProfileTarget: Equatable, Sendable {
    let id: String
    let primary: Bool
    func resolve(in roster: HarborRoster) -> JSONValue? {
        guard !id.isEmpty, id.utf8.count <= 256 else { return nil }
        if let exact = roster.profile(id) { return exact }
        return primary ? roster.primary() : nil
    }
}
