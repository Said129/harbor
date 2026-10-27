import Foundation

enum TraktConfiguration {
    static let clientID = "71ef7ea86333eab031c8830f8200df1f2f16ef9a3335a67470be4950ac80b925"
    static let tokenBase = "https://harborcommunity.site"
    static let verificationURL = URL(string: "https://trakt.tv/activate")!
}
struct TraktSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let createdAt: Double
    let expiresIn: Double
    var username: String?
    var valid: Bool {
        SimklEndpoint.validToken(accessToken) && SimklEndpoint.validToken(refreshToken)
            && createdAt.isFinite && createdAt >= 0 && createdAt <= 8_640_000_000_000
            && expiresIn.isFinite && expiresIn > 0 && expiresIn <= 315_360_000
            && (username.map { $0.utf8.count <= 1_024 && $0.rangeOfCharacter(from: .controlCharacters) == nil } ?? true)
    }
    init(accessToken: String, refreshToken: String, createdAt: Double, expiresIn: Double, username: String? = nil) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.createdAt = createdAt; self.expiresIn = expiresIn; self.username = username
    }
    init(_ value: JSONValue, username: String? = nil) throws {
        guard let access = value["access_token"].string, let refresh = value["refresh_token"].string,
              let created = value["created_at"].numericValue, let expires = value["expires_in"].numericValue else { throw HarborError(code: "trakt-session") }
        self.init(accessToken: access, refreshToken: refresh, createdAt: created, expiresIn: expires, username: username)
        guard valid else { throw HarborError(code: "trakt-session") }
    }
}
struct TraktPin: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let expiresIn: TimeInterval
    let interval: TimeInterval
    var verificationURL: URL { TraktConfiguration.verificationURL }
    init(_ value: JSONValue) throws {
        guard let device = value["device_code"].string, SimklEndpoint.validToken(device), device.utf8.count <= 4_096,
              let user = value["user_code"].string, user.range(of: "^[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
              let expires = value["expires_in"].numericValue, expires.isFinite, (1...86_400).contains(expires),
              let interval = value["interval"].numericValue, interval.isFinite, (1...3_600).contains(interval) else { throw HarborError(code: "trakt-code") }
        deviceCode = device; userCode = user; expiresIn = expires; self.interval = interval
    }
}
enum TraktEndpoint: Sendable {
    case deviceCode, poll(String), refresh(String), me, playback
    var authenticated: Bool { switch self { case .me, .playback: true; default: false } }
    func request(token: String? = nil) throws -> URLRequest {
        let url: URL, body: JSONValue?
        switch self {
        case .deviceCode:
            url = URL(string: "https://api.trakt.tv/oauth/device/code")!; body = .object(["client_id": .string(TraktConfiguration.clientID)])
        case .poll(let code):
            guard SimklEndpoint.validToken(code), code.utf8.count <= 4_096 else { throw HarborError(code: "trakt-code") }
            url = URL(string: TraktConfiguration.tokenBase + "/api/trakt/device-token")!; body = .object(["code": .string(code)])
        case .refresh(let token):
            guard SimklEndpoint.validToken(token) else { throw HarborError(code: "trakt-session") }
            url = URL(string: TraktConfiguration.tokenBase + "/api/trakt/token")!; body = .object(["refresh_token": .string(token), "grant_type": .string("refresh_token")])
        case .me: url = URL(string: "https://api.trakt.tv/users/me")!; body = nil
        case .playback: url = URL(string: "https://api.trakt.tv/sync/playback?limit=40")!; body = nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version"); request.setValue(TraktConfiguration.clientID, forHTTPHeaderField: "trakt-api-key")
        if authenticated {
            guard let token, SimklEndpoint.validToken(token) else { throw HarborError(code: "trakt-not-connected") }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body { request.httpBody = try JSONEncoder().encode(body) }; return request
    }
}
struct TraktReply: Sendable {
    let status: Int
    let data: Data
    var retryAfter: String? = nil
    func value() throws -> JSONValue {
        guard (200..<300).contains(status) else { throw TraktAPIError(status: status) }
        if status == 204 { return .null }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { throw HarborError(code: "trakt-response") }; return value
    }
    var retryDelay: TimeInterval {
        guard let delay = retryAfter.flatMap(Double.init), delay.isFinite else { return 1 }; return min(30, max(1, delay))
    }
}
struct TraktAPIError: Error, Sendable { let status: Int }
