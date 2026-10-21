import XCTest

@MainActor final class HarborCombinedReadingNavigationTests: XCTestCase {
    func testAllPendingReadingCatalogAndBulkInterfacesOnIPhone() { verify("iphone") }
    func testAllPendingReadingCatalogAndBulkInterfacesOnIPad() { verify("ipad") }
    private func verify(_ device: String) {
        continueAfterFailure = false
        ReadingPluginUIRoute(owner: self).verify(device)
        EBookCatalogUIRoute(owner: self).verify(device)
        ReadingBulkUIRoute(owner: self).verify(device)
    }
}
