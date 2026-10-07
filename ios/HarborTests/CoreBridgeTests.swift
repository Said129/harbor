import XCTest
@testable import Harbor

final class CoreBridgeTests: XCTestCase {
    func testPublicDirectoryContractsUseNativeManifestValidation() async throws {
        let manifest: JSONValue = .object(["id": .string("directory-test"), "name": .string("Catalog test"), "version": .string("1.0.0"), "resources": .array([.string("catalog")]), "types": .array([.string("movie")]), "catalogs": .array([])])
        let valid: JSONValue = .object(["manifest": manifest, "transportUrl": .string("https://example.org/manifest.json")])
        let unsafe: JSONValue = .object(["manifest": manifest, "transportUrl": .string("https://private:credential@example.org/manifest.json")])
        let invalid: JSONValue = .object(["manifest": .object(["id": .string("missing-name")]), "transportUrl": .string("https://example.org/manifest.json")])
        let flat = try await AddonDirectory.parse(.array([unsafe, invalid, valid, valid]))
        let wrapped = try await AddonDirectory.parse(.object(["addons": .array([valid])]))
        XCTAssertEqual(flat.count, 1)
        XCTAssertEqual(flat.first?.id, wrapped.first?.id)
        XCTAssertEqual(flat.first?.category, .metadata)
        XCTAssertEqual(flat.first?.adult, false, "The bundled Desktop filter must be available")
        var adult = try XCTUnwrap(flat.first)
        adult.manifest = .object(["id": .string("filter-test"), "name": .string("D0uj1n source")])
        XCTAssertTrue(adult.adult, "Discovery must preserve Desktop's normalized content filter")
        do { _ = try await AddonDirectory.parse(.object(["error": .string("failed")])); XCTFail("A failure response must not replace discovery with a valid empty catalog") }
        catch let error as HarborError { XCTAssertEqual(error.code, "addon-directory-response") }
    }
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
