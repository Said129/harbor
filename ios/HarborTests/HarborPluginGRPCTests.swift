import XCTest
@testable import Harbor

final class HarborPluginGRPCTests: XCTestCase {
    private func fixture() throws -> JSONValue {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "plugin-grpc-reference", withExtension: "json", subdirectory: "Fixtures"))
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
        XCTAssertEqual(result["reference"].string, "0834340cec5531650bfe78cd628628702e636987")
        return result
    }

    func testRequestBase64AndNetworkByteOrderMatchDesktopFrames() throws {
        let rows = try fixture()["requests"].array; XCTAssertEqual(rows.count, 14)
        for row in rows {
            let input = try XCTUnwrap(row["input"].string)
            if let error = row["error"].string {
                XCTAssertThrowsError(try HarborPluginGRPC.requestFrame(input)) { XCTAssertEqual(($0 as? HarborPluginGRPCError)?.rawValue, error) }
            } else {
                XCTAssertEqual(try HarborPluginGRPC.requestFrame(input).base64EncodedString(), row["expected"]["frame"].string)
            }
        }
    }

    func testMessagesTrailersStatusAndPercentEncodedErrorsMatchDesktop() throws {
        for row in try fixture()["responses"].array where row["error"] == .null {
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(row["bytes"].string)))
            let headers = row["headers"].objectValue.compactMapValues(\.string)
            let response = try HarborPluginGRPC.response(status: try XCTUnwrap(row["status"].integer), headers: headers, bytes: bytes)
            XCTAssertEqual(try JSONValue.encoded(response), row["expected"])
        }
    }

    func testTruncatedCompressedAndInvalidFlagFramesPreserveReferenceErrors() throws {
        var count = 0
        for row in try fixture()["responses"].array {
            guard let error = row["error"].string else { continue }; count += 1
            let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(row["bytes"].string)))
            XCTAssertThrowsError(try HarborPluginGRPC.response(status: 200, headers: [:], bytes: bytes)) { XCTAssertEqual(($0 as? HarborPluginGRPCError)?.rawValue, error) }
        }
        XCTAssertEqual(count, 5)
    }

    func testReferenceTimeoutClampAndEightMegabyteRequestBound() throws {
        for row in try fixture()["timeouts"].array {
            let value = try? row["value"].decoded(Double.self)
            XCTAssertEqual(HarborPluginGRPC.timeoutMilliseconds(value), try row["expected"].decoded(Double.self))
        }
        let oversized = Data(repeating: 0, count: HarborPluginGRPC.maximumBytes + 1).base64EncodedString()
        XCTAssertThrowsError(try HarborPluginGRPC.requestFrame(oversized)) { XCTAssertEqual($0 as? HarborPluginGRPCError, .tooLarge) }
    }
}
