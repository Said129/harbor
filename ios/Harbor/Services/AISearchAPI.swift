import Foundation

/// One title the model suggested (Desktop's `AiSuggestion`).
struct AISearchSuggestion: Equatable, Sendable {
    var title: String
    var year: Int?
    var type: String?
    var season: Int?
    var episode: Int?
    var episodeTitle: String?
}

/// Desktop's AI failure messages (`AiErrorMessageKey`), chosen from the HTTP status by `friendlyAiError`.
enum AISearchFailure: Equatable, Sendable {
    case rejectedKey, outOfCredits, modelMissing, requestTooBig, rateLimited, emptyReply, status(Int), unknown

    static func from(status: Int) -> AISearchFailure {
        switch status {
        case 401: .rejectedKey
        case 402: .outOfCredits
        case 404: .modelMissing
        case 413: .requestTooBig
        case 429: .rateLimited
        case 0: .unknown
        default: .status(status)
        }
    }

    var message: String {
        switch self {
        case .rejectedKey: DesktopInterfaceText.value("Your API key was rejected. Check it in Settings, AI search.")
        case .outOfCredits: DesktopInterfaceText.value("Your account is out of credits for this model. Pick a free model or top up.")
        case .modelMissing: DesktopInterfaceText.value("This model no longer exists at the provider. Pick another model (hold the AI button).")
        case .requestTooBig: DesktopInterfaceText.value("That request was too big for this model. Pick a model with a larger context.")
        case .rateLimited: DesktopInterfaceText.value("The model is rate-limited right now. Try again in a moment or switch models.")
        case .emptyReply: DesktopInterfaceText.value("The model replied with nothing usable. Try another model (hold the AI button) or rephrase.")
        case .status(let code): DesktopInterfaceText.value("AI search failed ({status}).", variables: ["status": String(code)])
        case .unknown: DesktopInterfaceText.value("AI search failed.")
        }
    }
}

/// Desktop's `AiSearchError`: the friendly failure, plus the start (140 characters) of the provider's own text.
struct AISearchError: Error, Equatable, Sendable {
    let failure: AISearchFailure
    var detail: String? = nil

    var message: String { failure.message }

    /// Desktop's `friendlyAiError`.
    static func from(status: Int, providerText: String) -> AISearchError {
        AISearchError(failure: AISearchFailure.from(status: status), detail: clippedDetail(providerText))
    }

    static func clippedDetail(_ text: String) -> String? {
        let value = String(text.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct AISearchReply: Sendable {
    let status: Int
    let data: Data
}

protocol AISearchTransport: Sendable {
    func send(_ request: URLRequest) async throws -> AISearchReply
}

/// Only the three hosts this feature talks to: the two chat services and Jina Reader.
struct AISearchHTTPTransport: AISearchTransport {
    private static let allowedHosts: Set<String> = ["openrouter.ai", "api.groq.com", "r.jina.ai"]
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func send(_ request: URLRequest) async throws -> AISearchReply {
        guard request.url?.scheme == "https", let host = request.url?.host, Self.allowedHosts.contains(host) else {
            throw HarborError(code: "ai-search-request")
        }
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HarborError(code: "invalid-http-response") }
        return AISearchReply(status: http.statusCode, data: data)
    }
}

/// Desktop's chat request for one search (`aiSuggest` in `src/lib/ai-search.ts`).
enum AISearchRequest {
    static let openRouterURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")
    static let groqURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")
    /// `HARBOR_API_BASE` from `src/lib/config/endpoints.ts`, sent to OpenRouter as the referer.
    static let referer = "https://harbor.site"
    static let maxSuggestions = 12

    static let systemPrompt = #"""
    You are a film and TV discovery engine for a media app. The user describes what they want to watch in natural language. Reply with ONLY a JSON array (no prose, no markdown code fences) of up to 12 specific, real movies or TV shows that best match, most relevant first. Each element is an object: {"title": string, "year": number, "type": "movie" or "series"}. If the user is clearly asking about a SPECIFIC EPISODE (by plot, scene, character, quote, or meme, for example 'the seinfeld one about the puffy shirt'), return that show as the first result and add its "season" and "episode" numbers plus "episodeTitle", like {"title": "South Park", "type": "series", "season": 13, "episode": 5, "episodeTitle": "Fishsticks"}. Use your own knowledge of the show to pick the exact episode. Use the original or most internationally recognized title. When live web context is provided below, treat it as authoritative ground truth for fact-grounded queries (people's filmographies, box office, recency, regional titles, memes, current seasons/episodes): use it as your primary source and cite the exact title/year it mentions rather than guessing from training data.
    """#

    static let schemaNote = #"Return the array under a top-level "results" key, as {"results": [ ... ]}."#

    static let suggestionSchema: JSONValue = .object([
        "type": .string("json_schema"),
        "json_schema": .object([
            "name": .string("harbor_suggestions"),
            "strict": .bool(true),
            "schema": resultsSchema,
        ]),
    ])

    private static let resultsSchema: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([.string("results")]),
        "properties": .object([
            "results": .object(["type": .string("array"), "items": itemSchema]),
        ]),
    ])

    private static let itemSchema: JSONValue = {
        let required: [JSONValue] = ["title", "year", "type", "season", "episode", "episodeTitle"].map { JSONValue.string($0) }
        let properties: [String: JSONValue] = [
            "title": .object(["type": .string("string")]),
            "year": .object(["type": nullable("number")]),
            "type": .object(["type": nullable("string"), "enum": .array([.string("movie"), .string("series"), .null])]),
            "season": .object(["type": nullable("number")]),
            "episode": .object(["type": nullable("number")]),
            "episodeTitle": .object(["type": nullable("string")]),
        ]
        return .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array(required),
            "properties": .object(properties),
        ])
    }()

    private static func nullable(_ type: String) -> JSONValue {
        .array([.string(type), .null])
    }

    /// The system text: the prompt, plus the live web context when there is some.
    static func systemText(webContext: String?) -> String {
        guard let context = webContext, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return systemPrompt }
        return systemPrompt + "\n\nLive web context for this query (use it when relevant, fall back to your own knowledge otherwise):\n" + context
    }

    /// The JSON body. Temperature, schema and the schema note depend on the model id, as on Desktop.
    static func body(model: String, query: String, webContext: String?) -> JSONValue {
        let schema = AISearchCatalog.supportsJSONSchema(model)
        let system = systemText(webContext: webContext)
        let content = schema ? system + "\n\n" + schemaNote : system
        var object: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .integer(2_000),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(content)]),
                .object(["role": .string("user"), "content": .string(query)]),
            ]),
        ]
        if AISearchCatalog.supportsSampling(model) { object["temperature"] = .number(0.4) }
        if schema { object["response_format"] = suggestionSchema }
        return .object(object)
    }

    static func urlRequest(service: AISearchService, key: String, model: String, query: String, webContext: String?) -> URLRequest? {
        guard let url = service == .groq ? groqURL : openRouterURL else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if service == .openrouter {
            request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Harbor", forHTTPHeaderField: "X-Title")
        }
        guard let data = try? JSONEncoder().encode(body(model: model, query: query, webContext: webContext)) else { return nil }
        request.httpBody = data
        return request
    }

    /// Desktop's reply handling: HTTP failures, then `error` inside a 200 reply, then the message text.
    static func parseReply(status: Int, data: Data) throws -> [AISearchSuggestion] {
        let text = String(decoding: data, as: UTF8.self)
        guard (200..<300).contains(status) else { throw AISearchError.from(status: status, providerText: text) }
        let json = decodeJSON(text) ?? .null
        if json["error"] != .null {
            let code = wholeNumber(json["error"]["code"]) ?? 0
            throw AISearchError.from(status: code, providerText: json["error"]["message"].string ?? "")
        }
        let content = (json["choices"].array.first ?? .null)["message"]["content"].string ?? ""
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AISearchError(failure: .emptyReply)
        }
        return parseSuggestions(content)
    }

    /// Desktop's `parseSuggestions`: a `{"results": [...]}` wrapper, or the first JSON array in the text.
    static func parseSuggestions(_ content: String) -> [AISearchSuggestion] {
        let items: [JSONValue]
        if let wrapped = wrappedResults(content) {
            items = wrapped
        } else {
            guard let span = extractJSONArray(content), let parsed = decodeJSON(span) else { return [] }
            items = parsed.array
        }
        var out: [AISearchSuggestion] = []
        var seen = Set<String>()
        for item in items {
            let title = (item["title"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, seen.insert(title.lowercased()).inserted else { continue }
            let type = item["type"].string
            let episodeTitle = (item["episodeTitle"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(AISearchSuggestion(
                title: title,
                year: wholeNumber(item["year"]),
                type: type == "movie" || type == "series" ? type : nil,
                season: wholeNumber(item["season"]),
                episode: wholeNumber(item["episode"]),
                episodeTitle: episodeTitle.isEmpty ? nil : episodeTitle
            ))
            if out.count >= maxSuggestions { break }
        }
        return out
    }

    /// Desktop's `extractJsonArray`: the first `[{ ... }]` span, skipping brackets inside strings.
    static func extractJSONArray(_ raw: String) -> String? {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
        guard let found = cleaned.range(of: #"\[\s*\{"#, options: .regularExpression) else { return nil }
        let characters = Array(cleaned)
        let start = cleaned.distance(from: cleaned.startIndex, to: found.lowerBound)
        var index = start
        var depth = 0
        var inString = false
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
            } else if character == "\"" {
                inString = true
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
                if depth == 0 { return String(characters[start...index]) }
            }
            index += 1
        }
        return nil
    }

    private static func wrappedResults(_ content: String) -> [JSONValue]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let json = decodeJSON(trimmed), case .array(let items) = json["results"] else { return nil }
        return items
    }

    static func decodeJSON(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// A whole number from a JSON value, as Desktop's `Math.round` on finite numbers.
    static func wholeNumber(_ value: JSONValue) -> Int? {
        switch value {
        case .integer(let number): Int(exactly: number)
        case .unsigned(let number): Int(exactly: number)
        case .number(let number): number.isFinite && abs(number) < 1e15 ? Int(number.rounded()) : nil
        default: nil
        }
    }
}

/// Desktop's `aiSuggest` call: no request without a key or a query.
struct AISearchClient: Sendable {
    let transport: any AISearchTransport

    func suggest(service: AISearchService, key: String, model: String, query: String, webContext: String? = nil) async throws -> [AISearchSuggestion] {
        let apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !text.isEmpty else { return [] }
        guard let request = AISearchRequest.urlRequest(service: service, key: apiKey, model: AISearchCatalog.resolvedModel(model), query: text, webContext: webContext) else {
            throw AISearchError(failure: .unknown)
        }
        let reply = try await transport.send(request)
        return try AISearchRequest.parseReply(status: reply.status, data: reply.data)
    }
}

/// A DuckDuckGo result read through Jina Reader (Desktop's `WebHit`).
struct AISearchWebHit: Equatable, Sendable {
    let title: String
    let url: String
    let snippet: String
}

/// Desktop's live web context (`src/lib/jina-search.ts`): DuckDuckGo results, the best hits read through Jina Reader.
struct AISearchWeb: Sendable {
    static let readerBase = "https://r.jina.ai/"
    static let maxHits = 8
    static let maxSnippet = 800
    let transport: any AISearchTransport

    /// Desktop's `enrichWithContent`: the prompt text, or "" when nothing was found.
    func context(for query: String, jinaKey: String) async throws -> String {
        let hits = try await search(query, jinaKey: jinaKey)
        guard !hits.isEmpty else { return "" }
        // Same order as Desktop's stable sort: priority sites first, then the rest.
        let promoted = hits.filter { Self.priority($0.url) > 0 } + hits.filter { Self.priority($0.url) == 0 }
        var picks = Array(promoted.prefix(3))
        picks += Array(promoted.dropFirst(3).filter { Self.priority($0.url) > 0 }.prefix(1))
        let pages = await readPages(Array(picks.prefix(4)), jinaKey: jinaKey)
        let finalHits = hits.map { hit -> AISearchWebHit in
            guard let text = pages[hit.url] else { return hit }
            return AISearchWebHit(title: hit.title, url: hit.url, snippet: text)
        }
        return Self.promptText(finalHits)
    }

    func search(_ query: String, jinaKey: String) async throws -> [AISearchWebHit] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let upstream = "https://html.duckduckgo.com/html/?q=" + Self.encodeComponent(text)
        let markdown = try await Self.readerText(upstream, jinaKey: jinaKey, transport: transport)
        return Self.parseHits(markdown)
    }

    private func readPages(_ hits: [AISearchWebHit], jinaKey: String) async -> [String: String] {
        let transport = self.transport
        var pages: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for hit in hits {
                group.addTask {
                    guard let markdown = try? await AISearchWeb.readerText(hit.url, jinaKey: jinaKey, transport: transport) else {
                        return (hit.url, nil)
                    }
                    return (hit.url, AISearchWeb.cleanPage(markdown))
                }
            }
            for await (url, text) in group {
                if let text { pages[url] = text }
            }
        }
        return pages
    }

    static func readerText(_ target: String, jinaKey: String, transport: any AISearchTransport) async throws -> String {
        guard let url = URL(string: readerBase + target) else { throw HarborError(code: "ai-search-web-url") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        let key = jinaKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
        let reply = try await transport.send(request)
        guard (200..<300).contains(reply.status) else { throw HarborError(code: "ai-search-web-\(reply.status)") }
        return String(decoding: reply.data, as: UTF8.self)
    }

    /// Desktop's `parseHits`: result headings from the reader's markdown, with the link text as the title.
    static func parseHits(_ markdown: String) -> [AISearchWebHit] {
        let lines = markdown.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var hits: [AISearchWebHit] = []
        var seen = Set<String>()
        for index in lines.indices {
            guard hits.count < maxHits else { break }
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("![") || trimmed.hasPrefix("{#") { continue }
            guard let heading = captures(headingPattern, in: line), heading.count == 2 else { continue }
            var url = decodeURL(heading[1].trimmingCharacters(in: .whitespaces))
            if !isUsable(url) { url = substitutedURL(lines, after: index) ?? url }
            guard isUsable(url), url.hasPrefix("http://") || url.hasPrefix("https://"), !seen.contains(url) else { continue }
            var title = cleanText(heading[0])
            for next in (index + 1)..<max(index + 1, min(lines.count, index + 12)) {
                let candidate = lines[next]
                if candidate.trimmingCharacters(in: .whitespaces).hasPrefix("![") { continue }
                guard let link = captures(linkPattern, in: candidate) else { continue }
                let text = cleanText(link[0])
                if text.count > 18 && text != title && !text.hasPrefix("![Image") {
                    title = text
                    break
                }
            }
            guard title.count >= 6 else { continue }
            seen.insert(url)
            hits.append(AISearchWebHit(title: title, url: url, snippet: String(title.prefix(maxSnippet))))
        }
        return hits
    }

    static func promptText(_ hits: [AISearchWebHit]) -> String {
        hits.prefix(maxHits).enumerated()
            .map { "[\($0.offset + 1)] \($0.element.title) — \($0.element.url)\n\($0.element.snippet)" }
            .joined(separator: "\n\n")
    }

    /// Desktop's page cleanup: the first 60 lines, without images, link targets and heading marks, at most 1,200 characters.
    static func cleanPage(_ markdown: String) -> String {
        let head = markdown.components(separatedBy: "\n").prefix(60).joined(separator: "\n")
        var text = head.replacingOccurrences(of: #"!\[[^\]]*\]\([^)]*\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        text = text.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
        return String(text.prefix(1_200)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func priority(_ url: String) -> Int {
        let lowered = url.lowercased()
        let sites = ["wikipedia.org", "themoviedb.org", "rottentomatoes.com", "letterboxd.com", "metacritic.com"]
        return sites.contains { lowered.contains($0) } ? 1 : 0
    }

    static func encodeComponent(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "-_.!~*'()").union(.alphanumerics)
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    private static let headingPattern = #"^\s*##\s*\[([^\]]+)\]\(([^)]+)\)"#
    private static let linkPattern = #"^\s*\[([^\]]+)\]\(([^)]+)\)"#

    private static func isUsable(_ url: String) -> Bool {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        return !host.isEmpty && !host.contains("duckduckgo.com")
    }

    private static func substitutedURL(_ lines: [String], after index: Int) -> String? {
        for next in (index + 1)..<max(index + 1, min(lines.count, index + 12)) {
            let line = lines[next]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("![") { continue }
            guard let link = captures(linkPattern, in: line) else { continue }
            let candidate = decodeURL(link[1].trimmingCharacters(in: .whitespaces))
            if isUsable(candidate) { return candidate }
        }
        return nil
    }

    /// DuckDuckGo redirect links carry the real address in `uddg`.
    private static func decodeURL(_ raw: String) -> String {
        guard let components = URLComponents(string: raw), components.host == "duckduckgo.com", components.path == "/l/",
              let real = components.queryItems?.first(where: { $0.name == "uddg" })?.value, !real.isEmpty else { return raw }
        return real.removingPercentEncoding ?? real
    }

    private static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: "*", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { group in
            Range(match.range(at: group), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
