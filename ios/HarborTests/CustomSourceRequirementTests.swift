import XCTest
@testable import Harbor

final class CustomSourceRequirementTests: XCTestCase {
    private func folder(provider: String? = nil, addon: String = "owned.addon") throws -> DesktopSourceFolder {
        var fields: [String: JSONValue] = ["id": .string("owned-folder"), "title": .string("Owned folder"), "tileShape": .string("LANDSCAPE"),
            "catalogSources": .array([.object(["addonId": .string(addon), "type": .string("movie"), "catalogId": .string("owned")])])]
        if let provider {
            fields["sources"] = .array([.object(["provider": .string(provider), "mediaType": .string("MOVIE"),
                "tmdbSourceType": .string("DISCOVER"), "traktListId": .integer(1)])])
        }
        return try XCTUnwrap(DesktopSourceFolder(.object(fields)))
    }
    func testNativeFoldersExplainTheirRequiredTMDBKeyBeforeUsingCatalogFallbacksOrMakingRequests() throws {
        for provider in ["tmdb", "trakt"] {
            let value = try folder(provider: provider)
            XCTAssertEqual(value.missingRequirement(hasTMDBKey: false, addons: []), .tmdbKey)
            XCTAssertNil(value.missingRequirement(hasTMDBKey: true, addons: []), "The native source has priority over the optional missing catalog addon")
        }
    }
    func testMissingAndDisabledAddonsAreExplainedWhileAnUndeclaredBuiltinCinemetaRemainsAvailable() throws {
        let owned = try folder(), missing = DesktopSourceFolder.Requirement.addon("owned.addon")
        XCTAssertEqual(owned.missingRequirement(hasTMDBKey: false, addons: []), missing)
        let disabled = Addon(manifest: .object(["id": .string("owned.addon")]), transportUrl: "https://owned.invalid/manifest.json", enabled: false)
        XCTAssertEqual(owned.missingRequirement(hasTMDBKey: false, addons: [disabled]), missing)
        let installed = Addon(manifest: disabled.manifest, transportUrl: disabled.transportUrl, enabled: true)
        XCTAssertNil(owned.missingRequirement(hasTMDBKey: false, addons: [installed]))
        let cinemeta = try folder(addon: "com.linvo.cinemeta")
        XCTAssertNil(cinemeta.missingRequirement(hasTMDBKey: false, addons: []))
        let explicitChoice = Addon(manifest: .object(["id": .string("com.linvo.cinemeta")]), transportUrl: "https://owned.invalid/manifest.json", enabled: false)
        XCTAssertEqual(cinemeta.missingRequirement(hasTMDBKey: false, addons: [explicitChoice]), .addon("com.linvo.cinemeta"))
    }
}
