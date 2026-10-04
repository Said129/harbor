import Foundation

struct HTTPClient: Sendable {
    func json(_ value: String, timeout: TimeInterval = 8) async throws -> JSONValue {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme) else { throw HarborError(code: "invalid-url") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            // Streaming bytes caps metadata payloads before allocating an unbounded Data.
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
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
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch let error as HarborError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch { throw HarborError(code: "network") } // Foundation descriptions may include secret URLs.
    }
}
