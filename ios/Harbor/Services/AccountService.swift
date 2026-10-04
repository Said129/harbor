import Foundation

struct AccountService: Sendable {
    private struct Plan: Decodable, Sendable { let url: String; let body: JSONValue }
    private let core = CoreBridge()
    private let http = HTTPClient()

    func login(email: String, password: String) async throws -> AccountSession {
        try await call("login", ["email": .string(email), "password": .string(password)])
    }

    func session(authKey: String) async throws -> AccountSession {
        let user: AccountUser = try await call("user", ["authKey": .string(authKey)])
        return AccountSession(authKey: authKey, user: user)
    }

    func addons(_ session: AccountSession) async throws -> AccountCollection {
        try await call("addons", ["authKey": .string(session.authKey)])
    }

    func save(_ collection: AccountCollection, session: AccountSession) async throws {
        struct Saved: Decodable, Sendable { let saved: Bool }
        let result: Saved = try await call("setAddons", ["authKey": .string(session.authKey), "addons": .array(collection.records)])
        guard result.saved else { throw HarborError(code: "invalid-account-response") }
    }

    private func call<T: Decodable & Sendable>(_ action: String, _ fields: [String: JSONValue]) async throws -> T {
        let plan: Plan = try await core.call("accountRequest", ["action": .string(action), "fields": .object(fields)])
        let response = try await http.post(plan.url, body: plan.body)
        return try await core.call("accountResponse", ["action": .string(action), "response": response])
    }
}
