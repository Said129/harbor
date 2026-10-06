import Foundation

private final class AccountRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct HTTPClient: Sendable {
    private static let metadataSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
    private static let accountSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: AccountRedirectPolicy(), delegateQueue: nil)
    }()

    func post(_ value: String, body: JSONValue) async throws -> JSONValue {
        let allowed = ["login", "getUser", "addonCollectionGet", "addonCollectionSet", "datastoreMeta", "datastoreGet", "datastorePut"].map { "https://api.strem.io/api/\($0)" }
        guard allowed.contains(value), let url = URL(string: value) else { throw HarborError(code: "invalid-account-request") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await receive(request, session: Self.accountSession)
    }

    func json(_ value: String, timeout: TimeInterval = 8, credentialed: Bool = false) async throws -> JSONValue {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme) else { throw HarborError(code: "invalid-url") }
        let request = URLRequest(url: url, cachePolicy: credentialed ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy, timeoutInterval: max(15, timeout))
        for attempt in 0..<2 {
            do { return try await receive(request, session: credentialed ? Self.accountSession : Self.metadataSession) }
            catch let error as HarborError {
                guard attempt == 0, error.code == "network" || error.code == "http-429" || error.code.hasPrefix("http-5") else { throw error }
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw HarborError(code: "network")
    }

    private func receive(_ input: URLRequest, session: URLSession) async throws -> JSONValue {
        var request = input
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Harbor-iOS/0.1", forHTTPHeaderField: "User-Agent")
        await Diagnostics.shared.record(.requestStarted)
        do {
            // Streaming bytes caps metadata payloads before allocating an unbounded Data.
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw HarborError(code: "invalid-http-response") }
            guard (200..<300).contains(response.statusCode) else { throw HarborError(code: "http-\(response.statusCode)") }
            let limit = 8 * 1024 * 1024
            guard response.expectedContentLength <= Int64(limit) else { throw HarborError(code: "response-too-large") }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < limit else { throw HarborError(code: "response-too-large") }
                data.append(byte)
            }
            let json = try JSONDecoder().decode(JSONValue.self, from: data)
            await Diagnostics.shared.record(.requestCompleted, count: data.count)
            return json
        } catch let error as HarborError {
            await Diagnostics.shared.recordFailure(error)
            throw error
        }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch {
            let safe = HarborError(code: "network") // Foundation descriptions may include secret URLs.
            await Diagnostics.shared.recordFailure(safe)
            throw safe
        }
    }
}
