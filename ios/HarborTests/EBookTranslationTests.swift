import XCTest
@testable import Harbor

private actor TranslationNetworkProbe: EBookTranslationNetworking {
    let lines: [String]
    let delay: UInt64
    private(set) var requests: [URLRequest] = []
    init(finish: String = "stop", delay: UInt64 = 0) throws {
        self.delay = delay
        let chunk: JSONValue = .object(["choices": .array([.object(["delta": .object(["content": .string("<chapter_title>Puerto</chapter_title><chapter_body>Texto traducido 😀</chapter_body>")])])])])
        let end: JSONValue = .object(["choices": .array([.object(["finish_reason": .string(finish)])])])
        lines = [": heartbeat", "data: " + String(decoding: try JSONEncoder().encode(chunk), as: UTF8.self), "data: " + String(decoding: try JSONEncoder().encode(end), as: UTF8.self), "data: [DONE]"]
    }
    func stream(_ request: URLRequest, receive: @escaping @Sendable (String) async throws -> Void) async throws {
        requests.append(request)
        for line in lines { if delay > 0 { try await Task.sleep(nanoseconds: delay) }; try Task.checkCancellation(); try await receive(line) }
    }
}

final class EBookTranslationTests: XCTestCase {
    func testActualJavaScriptCoreMatchesOriginalRequestsSevenStreamCasesAndFourCacheIdentities() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ebook-translation-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        XCTAssertEqual(fixture["cases"].array.count, 7); XCTAssertEqual(fixture["slots"].array.count, 4)
        for item in fixture["cases"].array {
            let program = EBookTranslationProgram(), expected = item["results"].array
            var failed = false
            for (index, operation) in item["operations"].array.enumerated() {
                do {
                    let actual = try await program.apply(operation)
                    XCTAssertTrue(expected.indices.contains(index)); if expected.indices.contains(index) { XCTAssertEqual(actual, expected[index], item["name"].string ?? "Stream") }
                } catch { XCTAssertNotEqual(item["failure"], .null); failed = true; break }
            }
            XCTAssertEqual(failed, item["failure"] != .null)
        }
        let program = EBookTranslationProgram()
        for item in fixture["slots"].array {
            var input = try XCTUnwrap(item["input"].objectValue); input["operation"] = .string("prepare")
            let prepared = try await program.apply(.object(input)); XCTAssertEqual(prepared["slot"], item["expected"])
        }
        var input = try XCTUnwrap(fixture["request"]["input"].objectValue); input["operation"] = .string("prepare")
        let prepared = try await program.apply(.object(input)); XCTAssertEqual(prepared, fixture["request"]["expected"])
    }

    func testNativeRequestCoalescesAndDurableProfileCacheSurvivesReopeningBeforeAutomaticOrKeyChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("translation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let network = try TranslationNetworkProbe(delay: 40_000_000), cache = try EBookTranslationCache(owner: "owner", directory: directory)
        let client = try EBookTranslationClient(owner: "owner", network: network, cache: cache)
        var settings = EBookTranslationSettings(); settings.enabled = true; settings.apiKey = " fixture-owned-key "; settings.targetLanguage = "es"
        let snapshot = settings
        async let first = client.translate(source: "Owned source chapter", title: "Harbor", settings: snapshot)
        async let second = client.translate(source: "Owned source chapter", title: "Harbor", settings: snapshot)
        let values = try await [first, second]
        XCTAssertEqual(values[0], values[1]); XCTAssertEqual(values[0].text, "Texto traducido 😀")
        let requests = await network.requests; XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-owned-key")
        let body = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["stream"], .bool(true)); XCTAssertEqual(body["thinking"]["type"], .string("disabled"))
        XCTAssertFalse(String(decoding: request.httpBody!, as: UTF8.self).contains("fixture-owned-key"))
        settings.enabled = false; settings.apiKey = ""
        let reopened = try EBookTranslationClient(owner: "owner", network: network, cache: EBookTranslationCache(owner: "owner", directory: directory))
        let cached = try await reopened.translate(source: "Owned source chapter", title: "Harbor", settings: settings)
        XCTAssertEqual(cached, values[0]); let count = await network.requests.count; XCTAssertEqual(count, 1)
        let other = try EBookTranslationClient(owner: "other", network: network, cache: EBookTranslationCache(owner: "other", directory: directory))
        let untouched = try await other.translate(source: "Owned source chapter", title: "Harbor", settings: settings)
        XCTAssertEqual(untouched.text, "Owned source chapter")
        do { _ = try await other.translate(source: "Owned source chapter", title: "Harbor", settings: settings, manual: true); XCTFail("Manual translation must require this profile's own key") }
        catch EBookTranslationError.missingKey {} catch { XCTFail("Unexpected missing-key error") }
    }

    func testCancellationAndTruncatedResponsesNeverPublishOrCachePartialChapterText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("translation-cancel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try EBookTranslationCache(owner: "owned", directory: directory), network = try TranslationNetworkProbe(delay: 2_000_000_000)
        let client = try EBookTranslationClient(owner: "owned", network: network, cache: cache)
        var settings = EBookTranslationSettings(); settings.enabled = true; settings.apiKey = "fixture-owned-key"
        let snapshot = settings
        let task = Task { try await client.translate(source: "Cancel owned chapter", title: "Harbor", settings: snapshot) }
        for _ in 0..<200 { if !(await network.requests).isEmpty { break }; try await Task.sleep(nanoseconds: 5_000_000) }
        let count = await network.requests.count; XCTAssertEqual(count, 1); task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled chapter must not appear") } catch is CancellationError {}
        let truncated = try EBookTranslationClient(owner: "owned", network: TranslationNetworkProbe(finish: "length"), cache: cache)
        do { _ = try await truncated.translate(source: "Cancel owned chapter", title: "Harbor", settings: settings); XCTFail("Truncated XML must not be cached") }
        catch EBookTranslationError.truncated {} catch { XCTFail("Unexpected truncation error") }
        settings.enabled = false; settings.apiKey = ""
        let original = try await client.translate(source: "Cancel owned chapter", title: "Harbor", settings: settings)
        XCTAssertEqual(original.text, "Cancel owned chapter")
    }

    func testTranslatedBlocksKeepIllustrationsSourceAnchorsAndEveryReturnedParagraph() throws {
        let picture = Data([1, 2, 3])
        let original = [EBookBlock(id: 9, text: "Original title", heading: true), .init(id: 12, text: "Picture", image: picture), .init(id: 27, text: "Original body")]
        let translated = EBookTranslatedChapter.blocks("Título\n\nPrimer párrafo\n\nSegundo párrafo", original: original)
        XCTAssertEqual(translated.map(\.text), ["Título", "Picture", "Primer párrafo", "Segundo párrafo"])
        XCTAssertEqual(translated.prefix(3).map(\.id), [9, 12, 27]); XCTAssertEqual(Set(translated.map(\.id)).count, 4)
        XCTAssertTrue(translated[0].heading); XCTAssertEqual(translated[1].image, picture)
        let fewer = EBookTranslatedChapter.blocks("One paragraph", original: original)
        XCTAssertEqual(fewer.map(\.id), [9, 12]); XCTAssertEqual(fewer[1].image, picture)
    }

    @MainActor func testKeychainSettingsStayWithinTheirProfileAndInvalidHeaderCannotOverwriteSavedConfiguration() throws {
        let owner = "translation-settings-" + UUID().uuidString, other = owner + ".other"
        defer { try? KeychainStore().remove(EBookTranslationSettings.key(owner)); try? KeychainStore().remove(EBookTranslationSettings.key(other)) }
        var settings = EBookTranslationSettings(); settings.enabled = true; settings.apiKey = " fixture-owned-key "; settings.targetLanguage = "fr"; settings.model = "deepseek-v4-pro"
        try settings.save(owner: owner)
        let saved = try EBookTranslationSettings.load(owner: owner)
        XCTAssertEqual(saved.apiKey, "fixture-owned-key"); XCTAssertEqual(saved.model, "deepseek-v4-pro"); XCTAssertEqual(saved.targetLanguage, "fr"); XCTAssertTrue(saved.automatic)
        XCTAssertEqual(try EBookTranslationSettings.load(owner: other).apiKey, "")
        settings.apiKey = "invalid\r\nheader"; XCTAssertThrowsError(try settings.save(owner: owner))
        XCTAssertEqual(try EBookTranslationSettings.load(owner: owner), saved)
        settings = saved; settings.enabled = false; try settings.save(owner: owner)
        XCTAssertFalse(try EBookTranslationSettings.load(owner: owner).automatic)
        XCTAssertEqual(try EBookTranslationSettings.load(owner: owner).apiKey, "fixture-owned-key")
    }
}
