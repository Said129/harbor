import CryptoKit
import Foundation

enum HarborReadingHTMLAssets {
    private struct Asset: Decodable {
        struct Program: Decodable { let source: String; let sha256: String }
        let schema: Int
        let reference: String
        let inputs: [String: String]
        let program: Program
    }
    static func source() throws -> String {
        guard let url = Bundle.main.url(forResource: "ReadingHTMLAssets", withExtension: "json") else { throw HarborPluginRuntimeError("reading-html-assets") }
        let data = try Data(contentsOf: url)
        guard data.count <= 512 * 1024 else { throw HarborPluginRuntimeError("reading-html-assets") }
        let asset = try JSONDecoder().decode(Asset.self, from: data)
        let hash = SHA256.hash(data: Data(asset.program.source.utf8)).map { String(format: "%02x", $0) }.joined()
        guard asset.schema == 1, asset.reference == "0834340cec5531650bfe78cd628628702e636987", asset.inputs.count == 5,
              hash == asset.program.sha256, hash == "03037e3519b6c30e1d7d3c494f705fd94b5346875d60f6aea5fe977b5ce1d437" else { throw HarborPluginRuntimeError("reading-html-assets") }
        return asset.program.source
    }
}
