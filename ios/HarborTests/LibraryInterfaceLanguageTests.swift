import Foundation
import XCTest
@testable import Harbor

@MainActor final class LibraryInterfaceLanguageTests: XCTestCase {
    private struct Reference: Decodable {
        let reference: String
        let reference_version: String
        let keys: [String]
        let mobile_instruction: String
        let mobile_translations: [String: String]
        let catalogs: [String: [String: String]]
    }
    func testLibraryLabelsUsePinnedDesktopCatalogsAndExplicitLocaleWithoutChangingSavedLanguage() throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "library-labels-reference", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: file))
        XCTAssertEqual(reference.reference, "0834340cec5531650bfe78cd628628702e636987")
        XCTAssertEqual(reference.reference_version, "0.9.132")
        XCTAssertEqual(Set(reference.catalogs.keys), Set(InterfaceLanguage.all.map(\.code)))
        let defaults = UserDefaults.standard, previous = defaults.string(forKey: "uiLanguage")
        defer { defaults.set(previous, forKey: "uiLanguage") }
        defaults.set("es", forKey: "uiLanguage")
        for language in InterfaceLanguage.all {
            let expected = try XCTUnwrap(reference.catalogs[language.code])
            for key in reference.keys {
                XCTAssertEqual(DesktopInterfaceText.value(key, language: language.code), expected[key], "\(language.code): \(key)")
            }
            XCTAssertEqual(DesktopInterfaceText.value(reference.mobile_instruction, language: language.code), reference.mobile_translations[language.code])
            let episode = DesktopInterfaceText.value("S{season} E{episode}", variables: ["season": "5", "episode": "23"], language: language.code)
            XCTAssertEqual(episode, expected["S{season} E{episode}"]?.replacingOccurrences(of: "{season}", with: "5").replacingOccurrences(of: "{episode}", with: "23"))
        }
        XCTAssertEqual(DesktopInterfaceText.value("Your collection.", language: "en_US"), reference.catalogs["en"]?["Your collection."])
        XCTAssertEqual(DesktopInterfaceText.value("Your collection.", language: "es-ES"), reference.catalogs["es"]?["Your collection."])
        XCTAssertEqual(defaults.string(forKey: "uiLanguage"), "es")
        XCTAssertEqual(DesktopInterfaceText.value("Your collection."), reference.catalogs["es"]?["Your collection."])
    }
}
