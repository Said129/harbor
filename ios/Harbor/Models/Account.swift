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

    func records(for next: [Addon]) -> [JSONValue] {
        next.map { addon in
            let original = zip(addons, records).first { $0.0.transportUrl == addon.transportUrl }?.1
            var fields: [String: JSONValue]
            if case .object(let value) = original { fields = value }
            else { fields = ["transportName": .string(""), "flags": .object(["official": .bool(false), "protected": .bool(false)])] }
            fields["transportUrl"] = .string(addon.transportUrl)
            fields["manifest"] = addon.manifest
            return .object(fields)
        }
    }
}

struct SavedAccount: Codable, Sendable {
    var version = 1
    let session: AccountSession
    var collection: AccountCollection
}
