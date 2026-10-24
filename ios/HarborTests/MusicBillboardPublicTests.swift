import XCTest
import Darwin
@testable import Harbor

@MainActor final class MusicBillboardPublicTests: XCTestCase {
    func testActualPublicHot100KeepsItsPublishedDateRankAndOriginalCatalogIdentity() async throws {
        let scope = PluginExecutionScope(owner: "owned-public-billboard", activation: UUID())
        let client = MusicBillboardClient(scope: scope, currentScope: { scope }); defer { client.dispose() }
        let ranking: MusicBillboardRanking
        do { ranking = try await client.ranking("hot-100") }
        catch {
            let addresses = await Task.detached { MusicBillboardPublicTests.publicSourceAddresses() }.value
            let attachment = XCTAttachment(string: addresses.joined(separator: "\n")); attachment.name = "billboard-public-source-dns"; attachment.lifetime = .keepAlways; add(attachment)
            throw error
        }
        XCTAssertEqual(ranking.chartId, "hot-100"); XCTAssertNotNil(ranking.dateValue)
        XCTAssertEqual(ranking.entries.first?.rank, 1); XCTAssertEqual(ranking.entries.count, 100)
        XCTAssertEqual(Set(ranking.entries.map(\.rank)).count, 100)
        for entry in ranking.entries {
            guard case .track(let track) = entry.item else { XCTFail("Hot 100 is a track chart"); return }
            XCTAssertTrue(track.id.hasPrefix("billboard:hot-100:")); XCTAssertEqual(track.connectorId, "catalog"); XCTAssertNil(track.playbackUrl)
        }
    }
    nonisolated private static func publicSourceAddresses() -> [String] {
        var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo("www.billboard.com", "443", &hints, &result)
        guard status == 0 else { return ["DNS status: " + String(status)] }
        defer { if let result { freeaddrinfo(result) } }
        var addresses: [String] = [], cursor = result
        while let row = cursor {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(row.pointee.ai_addr, row.pointee.ai_addrlen, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
            cursor = row.pointee.ai_next
        }
        return addresses.sorted()
    }
}
