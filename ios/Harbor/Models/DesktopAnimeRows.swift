import CryptoKit
import Foundation

struct DesktopAnimeRows: Decodable, Sendable {
    struct Plan: Decodable, Sendable {
        let path: String
        let parameters: [String: String]
        let factor: Int
        let offset: Int
        func request(page: Int) throws -> (path: String, parameters: [String: String]) {
            guard (1...100).contains(page) else { throw HarborError(code: "anime-page") }
            var values = parameters; values["page"] = String(page * factor + offset); values["limit"] = "25"
            return (path, values)
        }
    }
    struct Row: Decodable, Sendable, Identifiable {
        let key: String
        let title: String
        let ranked: Bool
        let pool: String
        let plans: [Plan]
        let filter: String
        var id: String { "anime-" + key }
        var rail: DiscoveryRail {
            let translated = DesktopInterfaceText.value(title)
            let name = translated.replacingOccurrences(of: "^Top\\s*", with: "", options: [.regularExpression, .caseInsensitive])
            let label = ranked ? DesktopInterfaceText.value("Top 10 {name}", variables: ["name": name]) : translated
            return .init(id: id, title: label, kind: "anime", path: "desktop-anime:" + key, ranked: ranked)
        }
    }
    private struct Asset: Decodable { let schema: Int; let reference: String; let inputs: [String: String]; let payload: String; let sha256: String }
    let rows: [Row]
    let sequelPattern: String
    let memberCeiling: Double
    let scoredByFloor: Double
    private static let cached: Result<Self, Error> = Result {
        guard let url = Bundle.main.url(forResource: "DesktopAnimeRows", withExtension: "json") else { throw HarborError(code: "anime-row-assets") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 256 * 1024 else { throw HarborError(code: "anime-row-assets") }
        let asset = try JSONDecoder().decode(Asset.self, from: bytes)
        let digest = SHA256.hash(data: Data(asset.payload.utf8)).map { String(format: "%02x", $0) }.joined()
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987", asset.inputs.count == 2,
              asset.sha256 == digest, digest == "c93283912307110958fa851758c172629fc2fc8ffa8693d53402a6275adafffb" else { throw HarborError(code: "anime-row-assets") }
        let value = try JSONDecoder().decode(Self.self, from: Data(asset.payload.utf8))
        guard value.rows.count == 20, Set(value.rows.map(\.key)).count == 20,
              value.rows.allSatisfy({ !$0.key.isEmpty && !$0.plans.isEmpty && $0.plans.count <= 2 && ["none", "gems"].contains($0.filter)
                  && $0.plans.allSatisfy({ ["anime", "top/anime", "seasons/now", "seasons/upcoming"].contains($0.path) && [1, 2].contains($0.factor) && (-1...0).contains($0.offset) }) }) else { throw HarborError(code: "anime-row-assets") }
        return value
    }
    static func read() throws -> Self { try cached.get() }
    func filtered(_ items: [JSONValue], for row: Row) throws -> [JSONValue] {
        guard items.count <= 100 else { throw HarborError(code: "anime-row-response") }
        guard row.filter == "gems" else { return items }
        let sequel = try NSRegularExpression(pattern: sequelPattern, options: .caseInsensitive)
        var seen = Set<Double>()
        // The original accepts an ID only after the popularity, vote and sequel checks.
        // A rejected duplicate must not hide a later eligible provider row.
        let selected = items.filter { item in
            guard let id = item["mal_id"].numericValue, id.isFinite, id > 0, id.rounded() == id,
                  !seen.contains(id), (item["members"].numericValue ?? 0) <= memberCeiling,
                  (item["scored_by"].numericValue ?? 0) >= scoredByFloor else { return false }
            for key in ["title_english", "title", "title_japanese"] {
                if let title = item[key].string, sequel.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil { return false }
            }
            seen.insert(id); return true
        }
        return selected.enumerated().sorted {
            let first = $0.element["score"].numericValue ?? 0, second = $1.element["score"].numericValue ?? 0
            return first == second ? $0.offset < $1.offset : first > second
        }.map(\.element)
    }
}
