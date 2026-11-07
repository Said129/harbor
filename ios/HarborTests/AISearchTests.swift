import XCTest
@testable import Harbor

private final class ScriptedAISearch: AISearchTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [AISearchReply]
    private var sent: [URLRequest] = []
    init(_ replies: [AISearchReply]) { self.replies = replies }
    var requests: [URLRequest] { lock.withLock { sent } }
    func send(_ request: URLRequest) async throws -> AISearchReply {
        lock.withLock {
            sent.append(request)
            return replies.isEmpty ? AISearchReply(status: 500, data: Data()) : replies.removeFirst()
        }
    }
}

/// A chat-completions reply whose only message is `content`.
private func chatReply(_ content: String, status: Int = 200) -> AISearchReply {
    let object: [String: Any] = ["choices": [["message": ["content": content]]]]
    return AISearchReply(status: status, data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
}

private func providerError(_ message: String, code: Int) -> AISearchReply {
    let object: [String: Any] = ["error": ["message": message, "code": code]]
    return AISearchReply(status: 200, data: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
}

private func body(_ request: URLRequest) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(request.httpBody))
}

private func media(_ id: String, _ name: String, year: String? = nil, type: String = "movie") -> Media {
    var value = Media(id: id, type: type, name: name)
    value.releaseInfo = year
    return value
}

private func suggestion(_ title: String, year: Int? = nil, type: String? = nil, season: Int? = nil, episode: Int? = nil, episodeTitle: String? = nil) -> AISearchSuggestion {
    AISearchSuggestion(title: title, year: year, type: type, season: season, episode: episode, episodeTitle: episodeTitle)
}

/// Desktop's AI search rules (`src/lib/ai-search.ts`, `src/lib/ai-models.ts`, `src/lib/jina-search.ts`), with canned replies only.
final class AISearchTests: XCTestCase {
    func testModelRulesFollowDesktopCatalog() {
        XCTAssertEqual(AISearchCatalog.provider(for: "llama-3.3-70b-versatile"), .groq)
        XCTAssertEqual(AISearchCatalog.service(for: "llama-3.3-70b-versatile"), .groq)
        XCTAssertEqual(AISearchCatalog.service(for: "openai/gpt-4o-mini"), .openrouter)
        XCTAssertEqual(AISearchCatalog.provider(for: "x-ai/some-new-model"), .xai, "An unknown id takes its vendor prefix")
        XCTAssertEqual(AISearchCatalog.provider(for: "vendor/unknown"), .openai, "An unknown vendor counts as OpenAI, as on Desktop")
        XCTAssertEqual(AISearchCatalog.migrate("google/gemini-flash-1.5"), "google/gemini-3.1-flash-lite")
        XCTAssertEqual(AISearchCatalog.resolvedModel("   "), AISearchCatalog.defaultModel, "An empty choice uses the default model")
        XCTAssertFalse(AISearchCatalog.supportsSampling("anthropic/claude-sonnet-5"))
        XCTAssertTrue(AISearchCatalog.supportsSampling("anthropic/claude-haiku-4.5"))
        XCTAssertFalse(AISearchCatalog.supportsJSONSchema("openai/gpt-oss-20b:free"), "A ':free' id gets prompt-only JSON")
        XCTAssertTrue(AISearchCatalog.supportsJSONSchema("openai/gpt-4o-mini"))
    }

    func testRequestBodyFollowsModelCapabilities() {
        let schema = AISearchRequest.body(model: "openai/gpt-4o-mini", query: "heist films", webContext: nil)
        XCTAssertEqual(schema["temperature"], .number(0.4))
        XCTAssertEqual(schema["max_tokens"].integer, 2_000)
        XCTAssertNotEqual(schema["response_format"], .null)
        let system = schema["messages"].array.first?["content"].string ?? ""
        XCTAssertTrue(system.hasSuffix("\"results\" key, as {\"results\": [ ... ]}."), "Schema models get the wrapper note")
        XCTAssertEqual(schema["messages"].array.last?["content"].string, "heist films")

        let free = AISearchRequest.body(model: AISearchCatalog.defaultModel, query: "heist films", webContext: nil)
        XCTAssertEqual(free["response_format"], .null, "Free models get no response_format")
        XCTAssertNotEqual(free["temperature"], .null)

        let claude = AISearchRequest.body(model: "anthropic/claude-sonnet-5", query: "heist films", webContext: nil)
        XCTAssertEqual(claude["temperature"], .null, "Claude Sonnet 5 rejects a temperature")
    }

    func testWebContextIsAddedToTheSystemText() {
        let body = AISearchRequest.body(model: "openai/gpt-4o-mini", query: "x", webContext: "[1] Heat (1995) — https://www.imdb.com/title/tt0113277/")
        let system = body["messages"].array.first?["content"].string ?? ""
        XCTAssertTrue(system.contains("Live web context for this query"))
        XCTAssertTrue(system.contains("[1] Heat (1995)"))
    }

    func testOpenRouterSendsRefererAndGroqDoesNot() throws {
        let open = try XCTUnwrap(AISearchRequest.urlRequest(service: .openrouter, key: "or-test-key", model: "openai/gpt-4o-mini", query: "q", webContext: nil))
        XCTAssertEqual(open.url?.host, "openrouter.ai")
        XCTAssertEqual(open.value(forHTTPHeaderField: "X-Title"), "Harbor")
        XCTAssertEqual(open.value(forHTTPHeaderField: "HTTP-Referer"), "https://harbor.site")
        XCTAssertEqual(open.value(forHTTPHeaderField: "Authorization"), "Bearer or-test-key")

        let groq = try XCTUnwrap(AISearchRequest.urlRequest(service: .groq, key: "gsk-test-key", model: "llama-3.3-70b-versatile", query: "q", webContext: nil))
        XCTAssertEqual(groq.url?.host, "api.groq.com")
        XCTAssertNil(groq.value(forHTTPHeaderField: "X-Title"))
        XCTAssertNil(groq.value(forHTTPHeaderField: "HTTP-Referer"))
    }

    func testWrappedResultsAreParsed() {
        let content = #"{"results":[{"title":"Heat","year":1995,"type":"movie","season":null,"episode":null,"episodeTitle":null}]}"#
        XCTAssertEqual(AISearchRequest.parseSuggestions(content), [suggestion("Heat", year: 1995, type: "movie")])
    }

    func testFencedArrayIsRecoveredAndTitlesAreDeduplicated() {
        let content = "Here you go:\n```json\n[{\"title\":\"Heat\",\"type\":\"movie\"},{\"title\":\"heat\"},{\"title\":\"  \"},{\"title\":\"Collateral\",\"year\":2004.4}]\n```"
        let found = AISearchRequest.parseSuggestions(content)
        XCTAssertEqual(found.map(\.title), ["Heat", "Collateral"])
        XCTAssertEqual(found.last?.year, 2004, "Years are rounded to whole numbers")
    }

    func testEpisodeFieldsSurviveParsing() {
        let content = #"[{"title":"South Park","type":"series","season":13,"episode":5,"episodeTitle":"Fishsticks"}]"#
        XCTAssertEqual(AISearchRequest.parseSuggestions(content), [suggestion("South Park", type: "series", season: 13, episode: 5, episodeTitle: "Fishsticks")])
    }

    func testSuggestionsAreCappedAtTwelve() {
        let items = (1...14).map { "{\"title\":\"Film \($0)\"}" }.joined(separator: ",")
        XCTAssertEqual(AISearchRequest.parseSuggestions("[" + items + "]").count, AISearchRequest.maxSuggestions)
    }

    func testStatusCodesMapToDesktopFailures() {
        XCTAssertEqual(AISearchFailure.from(status: 401), .rejectedKey)
        XCTAssertEqual(AISearchFailure.from(status: 402), .outOfCredits)
        XCTAssertEqual(AISearchFailure.from(status: 404), .modelMissing)
        XCTAssertEqual(AISearchFailure.from(status: 413), .requestTooBig)
        XCTAssertEqual(AISearchFailure.from(status: 429), .rateLimited)
        XCTAssertEqual(AISearchFailure.from(status: 500), .status(500))
        XCTAssertEqual(AISearchFailure.from(status: 0), .unknown)
    }

    func testErrorInsideASuccessfulReplyIsMapped() async throws {
        let transport = ScriptedAISearch([providerError("Too many requests", code: 429)])
        do {
            _ = try await AISearchClient(transport: transport).suggest(service: .openrouter, key: "or-test-key", model: "openai/gpt-4o-mini", query: "heist")
            XCTFail("A provider error must throw")
        } catch let error as AISearchError {
            XCTAssertEqual(error.failure, .rateLimited)
            XCTAssertEqual(error.detail, "Too many requests")
        }
    }

    func testHTTPFailureKeepsTheProviderText() async throws {
        let transport = ScriptedAISearch([AISearchReply(status: 401, data: Data("bad key".utf8))])
        do {
            _ = try await AISearchClient(transport: transport).suggest(service: .groq, key: "gsk-test-key", model: "", query: "heist")
            XCTFail("A 401 must throw")
        } catch let error as AISearchError {
            XCTAssertEqual(error.failure, .rejectedKey)
            XCTAssertEqual(error.detail, "bad key")
        }
    }

    func testEmptyContentIsReportedAsNothingUsable() async throws {
        let transport = ScriptedAISearch([chatReply("   ")])
        do {
            _ = try await AISearchClient(transport: transport).suggest(service: .openrouter, key: "or-test-key", model: "", query: "heist")
            XCTFail("An empty reply must throw")
        } catch let error as AISearchError {
            XCTAssertEqual(error.failure, .emptyReply)
        }
    }

    func testWithoutKeyNothingIsSent() async throws {
        let transport = ScriptedAISearch([])
        let found = try await AISearchClient(transport: transport).suggest(service: .groq, key: "   ", model: "", query: "heist")
        XCTAssertEqual(found, [])
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testClientSendsTheTrimmedQueryAndReturnsTheTitles() async throws {
        let transport = ScriptedAISearch([chatReply(#"{"results":[{"title":"Heat","year":1995,"type":"movie"}]}"#)])
        let found = try await AISearchClient(transport: transport).suggest(service: .groq, key: "gsk-test-key", model: "llama-3.3-70b-versatile", query: "  heist movies  ")
        XCTAssertEqual(found.map(\.title), ["Heat"])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.host, "api.groq.com")
        let sent = try body(request)
        XCTAssertEqual(sent["model"].string, "llama-3.3-70b-versatile")
        XCTAssertEqual(sent["messages"].array.last?["content"].string, "heist movies")
    }

    func testBestMatchPrefersExactTitleThenTypeAndYear() {
        let pool = [media("tv1", "Heat", year: "2000", type: "series"), media("m1", "Heat", year: "1995"), media("m2", "Heat 2", year: "2024")]
        XCTAssertEqual(AISearchResolver.bestMatch(pool, for: suggestion("Heat", year: 1995, type: "movie"))?.id, "m1")
        XCTAssertEqual(AISearchResolver.bestMatch([media("s", "Heat", type: "series"), media("m", "Heat")], for: suggestion("Heat"))?.id, "s", "A tie keeps the first candidate")
        XCTAssertNil(AISearchResolver.bestMatch(pool, for: suggestion("Gladiator")), "No name match gives no result")
    }

    func testResolveKeepsOneRowPerTitleAndEpisode() async {
        let heat = media("tt0113277", "Heat", year: "1995")
        let park = media("sp", "South Park", type: "series")
        let suggestions = [
            suggestion("Heat", year: 1995, type: "movie"),
            suggestion("Heat", type: "movie"),
            suggestion("South Park", type: "series", season: 13, episode: 5, episodeTitle: "Fishsticks"),
            suggestion("South Park", type: "series", season: 13, episode: 6, episodeTitle: "Jewbilee"),
            suggestion("Unknown Film"),
        ]
        let results = await AISearchResolver.resolve(suggestions) { title in
            if title == "Heat" { return [heat] }
            if title == "South Park" { return [park] }
            return []
        }
        XCTAssertEqual(results.map(\.id), ["tt0113277", "sp:13:5", "sp:13:6"])
        XCTAssertEqual(results[1].episodeTitle, "Fishsticks")
        XCTAssertNil(results[0].season, "A movie keeps no episode fields")
    }

    func testWebHitsAreReadFromReaderMarkdown() {
        let markdown = """
        ## [Heat (1995) - IMDb](https://duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.imdb.com%2Ftitle%2Ftt0113277%2F&rut=abc)
        [Heat (1995) - IMDb overview page](https://duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.imdb.com%2Ftitle%2Ftt0113277%2F)
        Crime drama with Al Pacino.
        """
        let hits = AISearchWeb.parseHits(markdown)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.url, "https://www.imdb.com/title/tt0113277/")
        XCTAssertEqual(hits.first?.title, "Heat (1995) - IMDb overview page")
    }

    func testPreferencesDefaultToOpenRouterWithoutWebContext() throws {
        let suite = "harbor.ai-search.tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let loaded = AISearchPreferences.load(defaults)
        XCTAssertEqual(loaded, AISearchPreferences())
        XCTAssertEqual(loaded.resolvedModel, AISearchCatalog.defaultModel)
        var changed = loaded
        changed.service = .groq
        changed.model = "openai/gpt-oss-120b"
        changed.webSearch = true
        changed.save(defaults)
        XCTAssertEqual(AISearchPreferences.load(defaults), changed)
        defaults.removePersistentDomain(forName: suite)
    }
}
