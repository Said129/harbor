import Foundation

struct SimklSession: Codable, Equatable, Sendable {
    let accessToken: String
    var username: String?
    var valid: Bool { SimklEndpoint.validToken(accessToken) && (username.map { $0.utf8.count <= 1_024 && $0.rangeOfCharacter(from: .controlCharacters) == nil } ?? true) }
}
struct SimklPin: Equatable, Sendable {
    let userCode: String
    let verificationURL: URL
    let expiresIn: TimeInterval
    let pollInterval: TimeInterval
    init(_ value: JSONValue) throws {
        guard let code = value["user_code"].string, code.range(of: "^[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
              let expires = value["expires_in"].integer, (1...86_400).contains(expires),
              let interval = value["interval"].integer, (1...3_600).contains(interval) else { throw HarborError(code: "simkl-pin") }
        // Open the provider's fixed origin. Neither a response URL nor a PIN can
        // turn this authorization link into an arbitrary external destination.
        userCode = code; verificationURL = URL(string: "https://simkl.com/pin/" + code)!
        expiresIn = TimeInterval(expires); pollInterval = TimeInterval(interval)
    }
}
