import CryptoKit
import Foundation

/// Desktop's DebridSlug: the five providers of lib/debrid.
enum DebridProvider: String, CaseIterable, Identifiable, Sendable {
    case rd, tb, ad, pm, dl
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rd: "Real-Debrid"
        case .tb: "TorBox"
        case .ad: "AllDebrid"
        case .pm: "Premiumize"
        case .dl: "Debrid-Link"
        }
    }
    /// Desktop's settings labels, in its order.
    var keyLabel: String {
        switch self {
        case .rd: "Real-Debrid API token"
        case .tb: "TorBox API key"
        case .ad: "AllDebrid API key"
        case .pm: "Premiumize API key"
        case .dl: "Debrid-Link API key"
        }
    }
    var placeholder: String { self == .rd ? "API token" : "API key" }
    /// Where the owner creates the key, as shown beside the field in Desktop.
    var keyPage: (label: String, url: String) {
        switch self {
        case .rd: ("real-debrid.com/apitoken", "https://real-debrid.com/apitoken")
        case .tb: ("torbox.app/settings", "https://torbox.app/settings")
        case .ad: ("alldebrid.com/apikeys", "https://alldebrid.com/apikeys/")
        case .pm: ("premiumize.me/account", "https://www.premiumize.me/account")
        case .dl: ("debrid-link.com/webapp/apikey", "https://debrid-link.com/webapp/apikey")
        }
    }
    var note: String {
        switch self {
        case .rd: "Used to check cache and unrestrict links. Harbor never adds or removes anything on your account on its own."
        case .tb: "Same read-only usage as Real-Debrid. Also lets you queue uncached sources from the play picker."
        case .ad: "AllDebrid deprecated their cache-check endpoint, so streams may show as unknown until you actually hit Play."
        case .pm: "Uses the directdl endpoint, which skips queueing for anything already cached."
        case .dl: "EU-hosted, fast cache check. Same read-only usage as the others."
        }
    }
    /// The single API host the provider's key may ever be sent to.
    var host: String {
        switch self {
        case .rd: "api.real-debrid.com"
        case .tb: "api.torbox.app"
        case .ad: "api.alldebrid.com"
        case .pm: "www.premiumize.me"
        case .dl: "debrid-link.com"
        }
    }
}

struct DebridAccount: Decodable, Equatable, Sendable {
    let slug: String
    var username: String?
    var email: String?
    let premium: Bool
    /// Unix seconds.
    var premiumUntil: Double?
    var trafficUsed: Double?
    var trafficLimit: Double?
}

struct DebridLink: Decodable, Equatable, Sendable {
    struct Subtitle: Decodable, Equatable, Sendable { let url: String; var lang: String?; var id: String? }
    let url: String
    var fileIdx: Int?
    var filename: String?
    var filesize: Double?
    var headers: [String: String]?
    var notWebReady: Bool?
    var subtitles: [Subtitle]?
}

struct DebridQueued: Decodable, Equatable, Sendable { let id: String }

struct DebridLibraryEntry: Decodable, Equatable, Sendable {
    let slug: String
    let id: String
    let hash: String
    let name: String
    var size: Double?
}

/// Desktop's DebridResult. The provider's raw error body is deliberately not decoded.
enum DebridOutcome<Value: Decodable & Sendable>: Decodable, Sendable {
    case success(Value)
    case failure(code: String, status: Int)
    private enum Keys: String, CodingKey { case ok, data, code, status }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if try container.decode(Bool.self, forKey: .ok) { self = .success(try container.decode(Value.self, forKey: .data)) }
        else {
            self = .failure(code: (try? container.decode(String.self, forKey: .code)) ?? "unknown", status: (try? container.decode(Int.self, forKey: .status)) ?? 0)
        }
    }
    var value: Value? { if case .success(let value) = self { value } else { nil } }
    var failureCode: String? { if case .failure(let code, _) = self { code } else { nil } }
}

/// The pinned original debrid clients, verified before any provider is contacted.
struct DebridAsset: Decodable, Sendable {
    struct Program: Decodable, Sendable { let source: String; let sha256: String }
    let schema: Int
    let reference: String
    let inputs: [String: String]
    let program: Program
    private static let cached: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "DebridAssets", withExtension: "json") else { throw HarborError(code: "debrid-assets") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 2 * 1024 * 1024 else { throw HarborError(code: "debrid-assets") }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        let digest = SHA256.hash(data: Data(value.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard value.schema == 1, value.reference == "0834340cec5531650bfe78cd628628702e636987", value.inputs.count == 8,
              digest == value.program.sha256, digest == "2be2bffda8261d1137573b56deaa6e11b48ef71755de81756de3d9086fc54a94" else { throw HarborError(code: "debrid-assets") }
        return value
    }
    static func read() throws -> Self { try cached.get() }
}
