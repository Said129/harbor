import XCTest

/// Independent cases let the remaining routes execute even if another feature reports a failure.
@MainActor final class HarborReadingCompletionNavigationTests: XCTestCase {
    func testReadingSourcesOnIPhone() { ReadingPluginUIRoute(owner: self).verify("iphone") }
    func testReadingSourcesOnIPad() { ReadingPluginUIRoute(owner: self).verify("ipad") }
    func testBookCatalogOnIPhone() { EBookCatalogUIRoute(owner: self).verify("iphone") }
    func testBookCatalogOnIPad() { EBookCatalogUIRoute(owner: self).verify("ipad") }
    func testReadingBulkOnIPhone() { ReadingBulkUIRoute(owner: self).verify("iphone") }
    func testReadingBulkOnIPad() { ReadingBulkUIRoute(owner: self).verify("ipad") }
    func testBookMetadataOnIPhone() { EBookMetadataUIRoute(owner: self).verify("iphone") }
    func testBookMetadataOnIPad() { EBookMetadataUIRoute(owner: self).verify("ipad") }
}
