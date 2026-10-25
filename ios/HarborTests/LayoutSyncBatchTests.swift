import XCTest
@testable import Harbor

@MainActor final class LayoutSyncBatchTests: XCTestCase {
    func testAllValidSectionsApplyInTheirOriginalOrderWithinOneAccountLease() async throws {
        var applied: [String] = [], checks = 0
        let steps = ["nav", "services", "home", "anime"].map { name in HarborLayoutSyncBatch.Step { applied.append(name) } }
        try await HarborLayoutSyncBatch.run(steps) { checks += 1 }
        XCTAssertEqual(applied, ["nav", "services", "home", "anime"]); XCTAssertEqual(checks, 8)
    }
    func testAnInvalidNavigationDocumentDoesNotBlockIndependentServicesHomeAndAnime() async throws {
        var applied: [String] = []
        do {
            try await HarborLayoutSyncBatch.run([
                .init { throw HarborError(code: "navigation-sync-value") },
                .init { applied.append("services") }, .init { applied.append("home") }, .init { applied.append("anime") },
            ]) { }
            XCTFail("The failed section must still be reported")
        } catch let error as HarborError { XCTAssertEqual(error.code, "navigation-sync-value") }
        XCTAssertEqual(applied, ["services", "home", "anime"])
    }
    func testSeveralSectionFailuresKeepTheFirstErrorAndStillApplyTheRemainingValidSection() async throws {
        var applied = false
        do {
            try await HarborLayoutSyncBatch.run([
                .init { throw HarborError(code: "navigation-sync-store") },
                .init { throw HarborError(code: "streaming-sync-value") },
                .init { applied = true }, .init { throw HarborError(code: "page-sync-value") },
            ]) { }
            XCTFail("Preserve the first section error")
        } catch let error as HarborError { XCTAssertEqual(error.code, "navigation-sync-store") }
        XCTAssertTrue(applied)
    }
    func testAuthenticationAndRateLimitingStopThePassEvenAfterAnEarlierLocalFailure() async throws {
        for code in ["http-401", "http-403", "http-429", "profile-auth-response", "account-changed"] {
            var later = false
            do {
                try await HarborLayoutSyncBatch.run([
                    .init { throw HarborError(code: "navigation-sync-value") },
                    .init { throw HarborError(code: code) }, .init { later = true },
                ]) { }
                XCTFail("Stop for " + code)
            } catch let error as HarborError { XCTAssertEqual(error.code, code) }
            XCTAssertFalse(later)
        }
    }
    func testAnAccountChangeWhileASectionIsSuspendedPreventsEveryLaterSection() async throws {
        var current = true, later = false
        do {
            try await HarborLayoutSyncBatch.run([
                .init { current = false }, .init { later = true },
            ]) { guard current else { throw HarborError(code: "account-changed") } }
            XCTFail("A retired lease cannot continue")
        } catch let error as HarborError { XCTAssertEqual(error.code, "account-changed") }
        XCTAssertFalse(later)
    }
    func testCancellationAndNetworkLossDoNotContinueMakingRequestsForOtherSections() async throws {
        let failures: [Error] = [CancellationError(), URLError(.timedOut)]
        for failure in failures {
            var later = false
            do {
                try await HarborLayoutSyncBatch.run([.init { throw failure }, .init { later = true }]) { }
                XCTFail("A cancelled or disconnected pass stops")
            } catch { XCTAssertTrue(error is CancellationError || error is URLError) }
            XCTAssertFalse(later)
        }
    }
}
