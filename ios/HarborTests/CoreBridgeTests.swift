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

    @MainActor
    func testExportedDiagnosticsWhitelistCodesWithoutLeakingPayloads() throws {
        let diagnostics = Diagnostics()
        diagnostics.recordFailure(HarborError(code: "http-403"))
        diagnostics.recordFailure(HarborError(code: "https://example.com/private-token"))
        diagnostics.recordFailure(HarborError(code: "mpv--3"))
        diagnostics.recordFailure(HarborError(code: "keychain-read--34018"))
        diagnostics.recordFailure(HarborError(code: "keychain-write--25291"))
        diagnostics.recordFailure(HarborError(code: "keychain-write-private-token"))
        let export = try diagnostics.export()
        let text = try String(contentsOf: export, encoding: .utf8)
        XCTAssertTrue(text.contains("code=http-403"))
        XCTAssertTrue(text.contains("code=mpv--3"))
        XCTAssertTrue(text.contains("code=keychain-read--34018"))
        XCTAssertTrue(text.contains("code=keychain-write--25291"))
        XCTAssertTrue(text.contains("code=unknown"))
        XCTAssertFalse(text.contains("private-token"))
        XCTAssertFalse(text.contains("example.com"))
    }
}
