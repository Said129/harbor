import CryptoKit
import Foundation

struct MusicBillboardReference: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let group: String
    let country: String
    let kind: String
    var url: URL { URL(string: "https://www.billboard.com/charts/" + id + "/")! }
}
struct MusicBillboardRanking: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Identifiable {
        let rank: Int
        let item: MusicCatalogItem
        var id: String { item.id }
    }
    let chartId: String
    let date: String
    let entries: [Entry]
    var sourceURL: URL? { URL(string: "https://www.billboard.com/charts/" + chartId + "/" + date + "/") }
    var dateValue: Date? { ISO8601DateFormatter().date(from: date + "T12:00:00Z") }
}
struct MusicBillboardAsset: Decodable, Sendable {
    struct Program: Decodable, Sendable { let source: String; let sha256: String }
    let schema: Int
    let reference: String
    let inputs: [String: String]
    let charts: [MusicBillboardReference]
    let program: Program
    private static let cached: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "MusicBillboardAssets", withExtension: "json") else { throw HarborError(code: "music-billboard-assets") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 2 * 1024 * 1024 else { throw HarborError(code: "music-billboard-assets") }
        let value = try JSONDecoder().decode(Self.self, from: bytes)
        let digest = SHA256.hash(data: Data(value.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard value.schema == 1, value.reference == "0834340cec5531650bfe78cd628628702e636987", value.inputs.count == 6,
              digest == value.program.sha256, digest == "93fcb838655aa9ab47739cc921d9120cecf9ac00f0cfea44896740f2b70af287",
              value.charts.count == 196, Set(value.charts.map(\.id)).count == 196,
              value.charts.allSatisfy({ ["track", "album", "artist"].contains($0.kind) && $0.id.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil }) else { throw HarborError(code: "music-billboard-assets") }
        return value
    }
    static func read() throws -> Self { try cached.get() }
}
