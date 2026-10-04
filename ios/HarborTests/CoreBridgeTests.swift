import XCTest
@testable import Harbor

final class CoreBridgeTests: XCTestCase {
    func testABITransportAndMemoryOwnershipRepeatedly() throws {
        let request = Data(#"{"operation":"normalizeAddon","url":"stremio://example.com/configure"}"#.utf8)
        for _ in 0..<100 {
            let result = try CoreBridge.invoke(request, as: JSONValue.self)
            XCTAssertEqual(result["url"].string, "https://example.com/manifest.json")
        }
    }

    func testErrorsDoNotEchoSensitivePayloads() {
        let request = Data(#"{"operation":"unknown","token":"private-token"}"#.utf8)
        XCTAssertThrowsError(try CoreBridge.invoke(request, as: JSONValue.self)) { error in
            XCTAssertEqual((error as? HarborError)?.code, "invalid-request")
            XCTAssertFalse(error.localizedDescription.contains("private-token"))
        }
    }

    func testUnsignedIntegerAndUnknownFieldsRoundTrip() throws {
        let data = Data(#"{"size":18446744073709551615,"headers":{"Authorization":"private"},"future":[true,null]}"#.utf8)
        let original = try JSONDecoder().decode(JSONValue.self, from: data)
        let output = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(original, output)
        XCTAssertEqual(original["size"], .unsigned(UInt64.max))
    }

    func testNativeStreamEngineLinksAndRanksRealContractShape() throws {
        let request = Data(#"{"operation":"rank","streams":[{"addonId":"sample","addonName":"Sample","title":"Example.2020.1080p.WEB-DL.H264.AAC","url":"https://example.com/video.mp4"}],"trust":{"disabled":true},"score":{}}"#.utf8)
        let result = try CoreBridge.invoke(request, as: JSONValue.self)
        XCTAssertEqual(result["picker"]["all"].array.count, 1)
        XCTAssertEqual(result["picker"]["all"].array.first?["resolution"].string, "1080p")
    }
}
