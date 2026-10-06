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
