import XCTest
@testable import Harbor

final class AccountCollectionTests: XCTestCase {
    func testReorderPreservesCompleteConfiguredCloudRecords() throws {
        let request = Data(#"{"operation":"accountResponse","action":"addons","response":{"result":{"addons":[{"transportUrl":"https://example.org/config-a/manifest.json","transportName":"A","flags":{"protected":true},"manifest":{"id":"same","name":"A","catalogs":[{"id":"catalog","type":"movie","futureCatalogField":{"keep":true}}]}},{"transportUrl":"https://example.org/config-b/manifest.json","flags":{"official":false},"manifest":{"id":"same","name":"B"}}]}}}"#.utf8)
        let collection = try CoreBridge.invoke(request, as: AccountCollection.self)
        let reordered = [collection.addons[1], collection.addons[0]]
        XCTAssertEqual(collection.records(for: reordered), [collection.records[1], collection.records[0]])
        XCTAssertEqual(collection.records(for: [collection.addons[1]]), [collection.records[1]])
    }
}
