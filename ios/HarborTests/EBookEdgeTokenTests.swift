import XCTest
@testable import Harbor

final class EBookEdgeTokenTests: XCTestCase {
    func testActualJavaScriptCoreMatches129IndependentV2TokensAndNativeRequestKeepsThePublicClientToken() async throws {
        struct Fixture: Decodable { struct Case: Decodable { let unix: Double; let salt: String; let expected: String }; let cases: [Case] }
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "edge-token-v2-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file)); XCTAssertEqual(fixture.cases.count, 129)
        let program = EBookEdgeTokenProgram()
        for item in fixture.cases {
            let date = Date(timeIntervalSince1970: item.unix), actual = try await program.token(date: date)
            XCTAssertEqual(EBookEdgeProtocol.salt(at: date), item.salt); XCTAssertEqual(actual, item.expected)
        }
        let first = try XCTUnwrap(fixture.cases.last), date = Date(timeIntervalSince1970: first.unix)
        let token = try await program.token(date: date)
        let request = try EBookEdgeProtocol.request(voices: false, date: date, token: token, protocolVersion: "2-143.0.3650.75")
        let url = try XCTUnwrap(request.url), query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "TrustedClientToken" }?.value, EBookEdgeProtocol.token)
        XCTAssertEqual(query.first { $0.name == "Sec-MS-GEC" }?.value, first.expected)
        XCTAssertEqual(query.first { $0.name == "Sec-MS-GEC-Version" }?.value, "2-143.0.3650.75")
    }
    @MainActor func testNarratorObserverLifetimeReleasesTheOwnerWithoutCrossingActorIsolation() {
        weak var released: EBookNarrator?
        autoreleasepool { let narrator = EBookNarrator(); released = narrator; narrator.prepare(owner: "owned-lifetime-" + UUID().uuidString) }
        XCTAssertNil(released)
    }
}
