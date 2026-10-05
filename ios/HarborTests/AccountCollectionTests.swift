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

    func testNullableStremioCollectionLoadsNativeCatalogsAndPreservesCloudManifest() throws {
        let request = Data(#"{"operation":"accountResponse","action":"addons","response":{"result":{"addons":[{"transportUrl":"https://example.org/configured/manifest.json","manifest":{"id":"nullable-contract","name":"Configured addon","types":["movie"],"idPrefixes":null,"resources":["meta",{"name":"stream","types":["movie"],"idPrefixes":null},{"name":"subtitles","types":null,"idPrefixes":null}],"catalogs":[{"id":"popular","type":"movie","name":null,"extra":[{"name":"genre","options":null}]}]}}]}}}"#.utf8)
        let collection = try CoreBridge.invoke(request, as: AccountCollection.self)
        XCTAssertEqual(collection.addons.count, 1)
        XCTAssertEqual(collection.records(for: collection.addons), collection.records)

        let catalogs = try JSONEncoder().encode(JSONValue.object([
            "operation": .string("catalogs"),
            "addons": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(collection.addons))
        ]))
        let plans = try CoreBridge.invoke(catalogs, as: [RequestPlan].self)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].title, "Configured addon")
        XCTAssertEqual(plans[0].catalog?.name, "")
        XCTAssertEqual(plans[0].catalog?.extra[0].options, [])
    }
}
