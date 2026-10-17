import Foundation

struct AccountUser: Codable, Sendable {
    let id: String
    let email: String?
    let fullname: String?
    enum CodingKeys: String, CodingKey { case id = "_id", email, fullname }
    var displayName: String {
        if let fullname, !fullname.isEmpty { return fullname }
        return email ?? "Cuenta Stremio"
    }
}

struct AccountSession: Codable, Sendable {
    let authKey: String
    let user: AccountUser
}

struct AccountCollection: Codable, Sendable {
    var addons: [Addon]
    var records: [JSONValue]

    func merging(_ next: [Addon], into fresh: [Addon]) -> [Addon] {
        let baseline = Dictionary(addons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let desired = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remote = Dictionary(fresh.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let removed = Set(baseline.keys).subtracting(desired.keys)
        var merged = fresh.filter { !removed.contains($0.id) }.map { addon -> Addon in
            guard let local = desired[addon.id] else { return addon }
            var result = baseline[addon.id]?.manifest != local.manifest ? local : addon
            result.enabled = local.enabled
            return result
        }
        // A remote removal stays removed unless this device installed/reconfigured it.
        merged += next.filter { remote[$0.id] == nil && (baseline[$0.id] == nil || baseline[$0.id]?.manifest != $0.manifest) }
        let existingOrder = addons.map(\.id).filter { desired[$0] != nil }
        let localOrder = next.map(\.id).filter { baseline[$0] != nil }
        if existingOrder != localOrder {
            let indices = Dictionary(next.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
            let slots = merged.indices.filter { indices[merged[$0].id] != nil }
            let ordered = slots.map { merged[$0] }.sorted { (indices[$0.id] ?? 0) < (indices[$1.id] ?? 0) }
            for (slot, addon) in zip(slots, ordered) { merged[slot] = addon }
        }
        return merged
    }

    func records(for next: [Addon], replacing replacements: [String: String] = [:]) -> [JSONValue] {
        next.map { addon in
            let originalURL = replacements[addon.transportUrl] ?? addon.transportUrl
            let original = zip(addons, records).first { $0.0.transportUrl == originalURL }
            var fields: [String: JSONValue]
            if case .object(let value) = original?.1 { fields = value }
            else { fields = ["transportName": .string(""), "flags": .object(["official": .bool(false), "protected": .bool(false)])] }
            fields["transportUrl"] = .string(addon.transportUrl)
            // A reorder/remove must preserve the complete cloud manifest, including
            // nested fields the native protocol does not consume. Refresh only
            // an installed/reinstalled manifest that has actually changed.
            if original?.0.manifest != addon.manifest { fields["manifest"] = addon.manifest }
            return .object(fields)
        }
    }
}

struct SavedAccount: Codable, Sendable {
    var version = 1
    let session: AccountSession
    var collection: AccountCollection
}
